#!/usr/bin/env bash
# Sebetsa RLS / trigger / SECURITY DEFINER regression harness.
#
# Applies every migration in supabase/migrations/ to a throwaway PostgreSQL
# database (with a minimal auth/storage stub standing in for Supabase), then
# runs every suite in supabase/rls-tests/tests/*.test.sql.
#
# Each suite is executed in its own psql process with ON_ERROR_STOP, so any
# `raise exception` (the suites' assertion mechanism) fails that suite. Suites
# wrap their fixtures in a transaction that is always rolled back, so they are
# independent of one another. Catalog-level suites additionally record rows in
# test_util.results, any of which being false fails the run.
#
# Modes:
#   default                 start a disposable postgres:17-alpine container
#                           (requires Docker; used by CI)
#   RLS_DATABASE_URL=...    use an existing, EMPTY, disposable database
#                           (e.g. a local throwaway cluster). The database is
#                           dropped and recreated — never point this at
#                           anything you care about.
#
# No repository secrets are used. The harness password is local-only.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MIGRATIONS_DIR="$REPO_ROOT/supabase/migrations"
DB_NAME="sebetsa_rls_test"

if [ -n "${RLS_DATABASE_URL:-}" ]; then
  MODE="url"
  case "$RLS_DATABASE_URL" in
    *supabase.co*|*supabase.com*|*pooler*)
      echo "::error::RLS_DATABASE_URL must point at a disposable local database, never a hosted Supabase project." >&2
      exit 2
      ;;
  esac
  ADMIN_URL="$RLS_DATABASE_URL"
  psql -v ON_ERROR_STOP=1 -q "$ADMIN_URL" -c "DROP DATABASE IF EXISTS $DB_NAME WITH (FORCE);" -c "CREATE DATABASE $DB_NAME;"
  TEST_URL="$(printf '%s' "$ADMIN_URL" | sed -E "s#/[^/?]*(\?|$)#/$DB_NAME\1#")"
  psql_exec() { psql -X -q -v ON_ERROR_STOP=1 "$TEST_URL" "$@"; }
else
  MODE="docker"
  CONTAINER_NAME="sebetsa-rls-harness-$$"
  cleanup() { docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true; }
  trap cleanup EXIT
  docker run -d --name "$CONTAINER_NAME" \
    -e POSTGRES_PASSWORD=harness \
    -e POSTGRES_DB="$DB_NAME" \
    postgres:17-alpine >/dev/null
  psql_exec() {
    docker exec -i "$CONTAINER_NAME" psql -X -q -v ON_ERROR_STOP=1 -U postgres -d "$DB_NAME" "$@"
  }
  ready=false
  for _ in $(seq 1 60); do
    if docker exec "$CONTAINER_NAME" pg_isready -U postgres -d "$DB_NAME" >/dev/null 2>&1 \
      && psql_exec -c 'select 1' >/dev/null 2>&1; then
      ready=true
      break
    fi
    sleep 1
  done
  if [ "$ready" != true ]; then
    docker logs "$CONTAINER_NAME" >&2 || true
    echo "::error::RLS harness database did not become ready" >&2
    exit 1
  fi
fi

echo "RLS harness mode: $MODE"

# Mirror Supabase: extensions live in their own schema, which is on the
# database's default search_path but NOT on a function's pinned search_path.
# (A pgcrypto call from a function pinned to `public, auth` fails here exactly
# as it would on a hosted project.)
psql_exec -c "CREATE SCHEMA IF NOT EXISTS extensions; CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;"
psql_exec -c "ALTER DATABASE $DB_NAME SET search_path = public, extensions;"
psql_exec < "$SCRIPT_DIR/00_auth_stub.sql"
psql_exec < "$SCRIPT_DIR/00_platform_stub.sql"
psql_exec < "$SCRIPT_DIR/01_test_util.sql"

for migration in "$MIGRATIONS_DIR"/*.sql; do
  echo "Applying $(basename "$migration")"
  psql_exec < "$migration"
done

suite_failures=()
suite_count=0
for test_file in "$SCRIPT_DIR"/tests/*.test.sql; do
  suite="$(basename "$test_file")"
  suite_count=$((suite_count + 1))
  echo "::group::Suite $suite"
  if psql_exec < "$test_file"; then
    echo "PASS suite $suite"
  else
    echo "::error::FAIL suite $suite"
    suite_failures+=("$suite")
  fi
  echo "::endgroup::"
done

echo "::group::Concurrency: notification outbox claim"
if [ "$MODE" = url ]; then
  conc_args=(psql "$TEST_URL")
else
  conc_args=(docker exec -i "$CONTAINER_NAME" psql -U postgres -d "$DB_NAME")
fi
if bash "$SCRIPT_DIR/concurrency.sh" "${conc_args[@]}"; then
  echo "PASS concurrency"
else
  echo "::error::FAIL concurrency"
  suite_failures+=("concurrency.sh")
fi
echo "::endgroup::"

psql_exec -c "select name, passed, detail from test_util.results order by id;"
RECORD_FAILS=$(psql_exec -t -A -c "select count(*) from test_util.results where not passed;")
RECORD_TOTAL=$(psql_exec -t -A -c "select count(*) from test_util.results;")

echo "Suites: $suite_count run, ${#suite_failures[@]} failed"
echo "Recorded assertions: $RECORD_TOTAL total, $RECORD_FAILS failed"

if [ "${#suite_failures[@]}" -gt 0 ] || [ "$RECORD_FAILS" -ne 0 ]; then
  for s in "${suite_failures[@]}"; do echo "  failed suite: $s"; done
  exit 1
fi
if [ "$suite_count" -eq 0 ]; then
  echo "::error::No RLS suites found — refusing to report a green run"
  exit 1
fi
echo "ALL $suite_count SUITES AND $RECORD_TOTAL RECORDED ASSERTIONS PASSED"
