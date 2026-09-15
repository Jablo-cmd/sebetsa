#!/usr/bin/env bash
# Docker-based Postgres RLS/trigger/SECURITY DEFINER regression harness for
# Sebetsa. Spins up a throwaway postgres:16-alpine container, applies a
# hand-built `auth`/`storage` schema stub (generic Supabase local-dev
# scaffolding — auth.uid()/auth.jwt() reading the request.jwt.claims GUC,
# a minimal storage.objects/storage.buckets, the authenticated/anon/
# service_role Postgres roles with Supabase's real default blanket table
# grants), applies every migration in supabase/migrations/ in order (the
# real, shipped SQL, not a copy), then runs every *.sql file in this
# directory. Each test file is self-contained — it seeds its own fixtures,
# impersonates each caller via `set local role authenticated` +
# `set local request.jwt.claims`, asserts with `raise exception
# 'SECURITY_FAILURE: ...'` / `'FAIL: ...'` on an unexpected result, and
# always ends with `rollback;` so nothing persists between files. A
# non-zero psql exit code (from `-v ON_ERROR_STOP=1`) means that file's
# assertions failed. Re-runnable from a clean state every time.
#
# Usage: supabase/rls-tests/run.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MIGRATIONS_DIR="$REPO_ROOT/supabase/migrations"
CONTAINER_NAME="sebetsa-rls-harness-$$"
PGPASSWORD="harness"
PGPORT="55432"

cleanup() {
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "==> starting postgres:16-alpine ($CONTAINER_NAME)"
docker run -d --name "$CONTAINER_NAME" \
  -e POSTGRES_PASSWORD="$PGPASSWORD" \
  -e POSTGRES_DB=sebetsa_rls_test \
  -p "$PGPORT:5432" \
  postgres:16-alpine >/dev/null

psql_exec() {
  PGPASSWORD="$PGPASSWORD" docker exec -i "$CONTAINER_NAME" \
    psql -v ON_ERROR_STOP=1 -U postgres -d sebetsa_rls_test "$@"
}

echo "==> waiting for postgres to accept connections"
ready=false
for _ in $(seq 1 60); do
  if PGPASSWORD="$PGPASSWORD" docker exec "$CONTAINER_NAME" \
      psql -U postgres -d sebetsa_rls_test -c 'select 1' >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 1
done
if [ "$ready" != true ]; then
  echo "postgres never became ready" >&2
  docker logs "$CONTAINER_NAME" >&2 || true
  exit 1
fi

echo "==> applying auth schema stub"
psql_exec < "$SCRIPT_DIR/00_auth_stub.sql"

echo "==> applying storage schema stub"
psql_exec < "$SCRIPT_DIR/00b_storage_stub.sql"

echo "==> applying migrations (supabase/migrations/*.sql, filename order)"
for migration in "$MIGRATIONS_DIR"/*.sql; do
  echo "    - $(basename "$migration")"
  psql_exec < "$migration"
done

echo
echo "==> running RLS regression suite"
FAIL_COUNT=0
TOTAL_COUNT=0
declare -a FAILED_FILES=()

for test_file in "$SCRIPT_DIR"/*.sql; do
  base="$(basename "$test_file")"
  case "$base" in
    00_auth_stub.sql|00b_storage_stub.sql) continue ;;
  esac
  TOTAL_COUNT=$((TOTAL_COUNT + 1))
  echo "    - $base"
  if ! psql_exec < "$test_file" > /tmp/rls-test-output-$$.log 2>&1; then
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAILED_FILES+=("$base")
    echo "      FAILED — output:"
    sed 's/^/      /' /tmp/rls-test-output-$$.log
  fi
  rm -f /tmp/rls-test-output-$$.log
done

echo
if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "==> ALL $TOTAL_COUNT RLS TEST FILES PASSED"
  exit 0
else
  echo "==> $FAIL_COUNT of $TOTAL_COUNT RLS TEST FILES FAILED: ${FAILED_FILES[*]}"
  exit 1
fi
