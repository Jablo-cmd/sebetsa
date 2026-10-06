#!/usr/bin/env bash
# Disposable PostgreSQL RLS/trigger/SECURITY DEFINER regression harness.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MIGRATIONS_DIR="$REPO_ROOT/supabase/migrations"
CONTAINER_NAME="sebetsa-rls-harness-$$"
PGPASSWORD="harness"
PGPORT="55432"

cleanup() { docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker run -d --name "$CONTAINER_NAME" \
  -e POSTGRES_PASSWORD="$PGPASSWORD" \
  -e POSTGRES_DB=sebetsa_rls_test \
  -p "$PGPORT:5432" postgres:17-alpine >/dev/null

psql_exec() {
  PGPASSWORD="$PGPASSWORD" docker exec -i "$CONTAINER_NAME" \
    psql -v ON_ERROR_STOP=1 -U postgres -d sebetsa_rls_test "$@"
}

ready=false
for _ in $(seq 1 60); do
  if docker exec "$CONTAINER_NAME" psql -U postgres -d sebetsa_rls_test -c 'select 1' >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 1
done
if [ "$ready" != true ]; then
  docker logs "$CONTAINER_NAME" >&2 || true
  exit 1
fi

psql_exec < "$SCRIPT_DIR/00_auth_stub.sql"
psql_exec -c "CREATE ROLE anon NOLOGIN; CREATE ROLE service_role NOLOGIN;"
psql_exec < "$SCRIPT_DIR/01_test_util.sql"
for migration in "$MIGRATIONS_DIR"/*.sql; do
  echo "Applying $(basename "$migration")"
  psql_exec < "$migration"
done

for fixture in "$SCRIPT_DIR"/02_fixtures.sql "$SCRIPT_DIR"/04_employee_fixtures.sql "$SCRIPT_DIR"/06_employee_provisioning_fixtures.sql "$SCRIPT_DIR"/09_attendance_fixtures.sql; do
  echo "Loading $(basename "$fixture")"
  psql_exec < "$fixture"
done

for test_file in "$SCRIPT_DIR"/tests/*.test.sql; do
  echo "Testing $(basename "$test_file")"
  psql_exec < "$test_file"
done

psql_exec -c "select name, passed, detail from test_util.results order by id;"
FAIL_COUNT=$(psql_exec -t -A -c "select count(*) from test_util.results where not passed;")
TOTAL_COUNT=$(psql_exec -t -A -c "select count(*) from test_util.results;")

if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "ALL $TOTAL_COUNT TESTS PASSED"
  exit 0
fi

echo "$FAIL_COUNT of $TOTAL_COUNT TESTS FAILED"
exit 1
