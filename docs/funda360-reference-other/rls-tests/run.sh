#!/usr/bin/env bash
# Docker-based Postgres RLS/trigger/SECURITY DEFINER verification harness.
#
# Spins up a throwaway postgres:16-alpine container, applies the hand-built
# auth schema stub, applies every migration in supabase/migrations/ in
# order (the real, shipped SQL — not a copy), loads fixture data, then runs
# every *.test.sql file under tests/. Exits non-zero if any recorded test
# failed. Re-runnable from a clean state every time; nothing here persists
# between runs.
#
# Usage: supabase/rls-tests/run.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MIGRATIONS_DIR="$REPO_ROOT/supabase/migrations"
CONTAINER_NAME="funda360-rls-harness-$$"
PGPASSWORD="harness"
PGPORT="55432"

cleanup() {
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "==> starting postgres:16-alpine ($CONTAINER_NAME)"
docker run -d --name "$CONTAINER_NAME" \
  -e POSTGRES_PASSWORD="$PGPASSWORD" \
  -e POSTGRES_DB=funda360_rls_test \
  -p "$PGPORT:5432" \
  postgres:16-alpine >/dev/null

psql_exec() {
  PGPASSWORD="$PGPASSWORD" docker exec -i "$CONTAINER_NAME" \
    psql -v ON_ERROR_STOP=1 -U postgres -d funda360_rls_test "$@"
}

echo "==> waiting for postgres to accept connections"
ready=false
for _ in $(seq 1 60); do
  if PGPASSWORD="$PGPASSWORD" docker exec "$CONTAINER_NAME" \
      psql -U postgres -d funda360_rls_test -c 'select 1' >/dev/null 2>&1; then
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

echo "==> applying test-recording helper"
psql_exec < "$SCRIPT_DIR/01_test_util.sql"

echo "==> applying storage schema stub"
psql_exec < "$SCRIPT_DIR/00b_storage_stub.sql"

echo "==> applying migrations (supabase/migrations/*.sql, filename order)"
for migration in "$MIGRATIONS_DIR"/*.sql; do
  echo "    - $(basename "$migration")"
  psql_exec < "$migration"
done

echo "==> loading fixtures"
psql_exec < "$SCRIPT_DIR/02_fixtures.sql"
psql_exec < "$SCRIPT_DIR/03_academic_fixtures.sql"
psql_exec < "$SCRIPT_DIR/04_employee_fixtures.sql"
psql_exec < "$SCRIPT_DIR/05_learner_fixtures.sql"
psql_exec < "$SCRIPT_DIR/06_employee_provisioning_fixtures.sql"
psql_exec < "$SCRIPT_DIR/07_guardian_emergency_contact_fixtures.sql"
psql_exec < "$SCRIPT_DIR/08_teaching_assignment_fixtures.sql"
psql_exec < "$SCRIPT_DIR/09_attendance_fixtures.sql"
psql_exec < "$SCRIPT_DIR/10_assessment_fixtures.sql"
psql_exec < "$SCRIPT_DIR/11_fees_behaviour_fixtures.sql"
psql_exec < "$SCRIPT_DIR/12_guardian_management_fixtures.sql"
psql_exec < "$SCRIPT_DIR/13_parent_portal_fixtures.sql"
psql_exec < "$SCRIPT_DIR/14_guardian_invitations_fixtures.sql"

echo "==> running regression tests"
for test_file in "$SCRIPT_DIR"/tests/*.test.sql; do
  echo "    - $(basename "$test_file")"
  psql_exec < "$test_file"
done

echo
echo "==> results"
psql_exec -c "select name, passed, detail from test_util.results order by id;"

FAIL_COUNT=$(psql_exec -t -A -c "select count(*) from test_util.results where not passed;")
TOTAL_COUNT=$(psql_exec -t -A -c "select count(*) from test_util.results;")

echo
if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "==> ALL $TOTAL_COUNT TESTS PASSED"
  exit 0
else
  echo "==> $FAIL_COUNT of $TOTAL_COUNT TESTS FAILED"
  exit 1
fi
