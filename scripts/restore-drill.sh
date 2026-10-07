#!/usr/bin/env bash
# Local logical backup/restore drill.
#
# Dumps a populated, migrated Sebetsa database (the RLS harness database after a run), restores it into a fresh
# database, and proves the restore is faithful: identical row counts and content checksums for every public table,
# RLS and FORCE RLS still on, no anon grants, audit immutability still enforced.
#
# THIS IS NOT A SUPABASE BACKUP OR PITR RESTORE. It proves the schema and data survive a dump/restore and that the
# security posture is part of the schema. It says nothing about the hosted project's backup schedule, retention,
# PITR window, storage buckets, or restore time. Never point it at a hosted project.
#
# Usage: SOURCE_URL=postgresql://postgres@localhost:55432/sebetsa_rls_test?host=/tmp \
#        ADMIN_URL=postgresql://postgres@localhost:55432/postgres?host=/tmp scripts/restore-drill.sh
set -euo pipefail

SOURCE_URL="${SOURCE_URL:?SOURCE_URL (populated, migrated database) is required}"
ADMIN_URL="${ADMIN_URL:?ADMIN_URL (maintenance database on the same cluster) is required}"
case "$SOURCE_URL$ADMIN_URL" in
  *supabase.co*|*supabase.com*|*pooler*) echo "Refusing to run against a hosted Supabase project." >&2; exit 2 ;;
esac

RESTORE_DB="sebetsa_restore_drill"
# Same cluster, different database name: swap the database in the URL path.
RESTORE_URL="${SOURCE_URL%%\?*}"; RESTORE_URL="${RESTORE_URL%/*}/${RESTORE_DB}"
[[ "$SOURCE_URL" == *\?* ]] && RESTORE_URL="${RESTORE_URL}?${SOURCE_URL#*\?}"
DUMP="$(mktemp -d)/sebetsa.dump"

checksums() {
  psql -X -At "$1" <<'SQL'
select format('%s|%s|%s', c.relname,
  (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from public.%I', c.relname), false, true, '')))[1]::text,
  (xpath('/row/h/text()', query_to_xml(format('select coalesce(md5(string_agg(t::text, '''' order by t::text)), ''-'') as h from public.%I t', c.relname), false, true, '')))[1]::text)
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r'
order by c.relname;
SQL
}

now_ms() { python3 -c 'import time; print(int(time.time()*1000))'; }

echo "== Source"
checksums "$SOURCE_URL" > "$DUMP.src"
tables=$(wc -l < "$DUMP.src")
rows=$(awk -F'|' '{s+=$2} END {print s+0}' "$DUMP.src")
echo "tables=$tables rows=$rows"

t0=$(now_ms)
pg_dump -Fc -f "$DUMP" "$SOURCE_URL"
t1=$(now_ms)
echo "dump: $((t1 - t0)) ms, $(du -h "$DUMP" | cut -f1)"

psql -X -q "$ADMIN_URL" -c "DROP DATABASE IF EXISTS $RESTORE_DB WITH (FORCE);" -c "CREATE DATABASE $RESTORE_DB;"
t2=$(now_ms)
pg_restore --no-owner --exit-on-error -d "$RESTORE_URL" "$DUMP"
t3=$(now_ms)
echo "restore: $((t3 - t2)) ms"

echo "== Verification"
checksums "$RESTORE_URL" > "$DUMP.dst"
if diff -q "$DUMP.src" "$DUMP.dst" >/dev/null; then
  echo "PASS: every public table restored with identical row count and content checksum ($tables tables, $rows rows)"
else
  echo "FAIL: restored data differs"; diff "$DUMP.src" "$DUMP.dst" | head -20; exit 1
fi

psql -X -At "$RESTORE_URL" <<'SQL' | tee "$DUMP.sec"
select 'rls_missing=' || count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relkind = 'r' and not (c.relrowsecurity and c.relforcerowsecurity);
select 'anon_table_grants=' || count(*) from information_schema.role_table_grants where table_schema = 'public' and grantee = 'anon';
select 'policies=' || count(*) from pg_policies where schemaname = 'public';
select 'definer_functions_unpinned=' || count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.prosecdef and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%');
SQL
grep -q '^rls_missing=0$' "$DUMP.sec" && grep -q '^anon_table_grants=0$' "$DUMP.sec" && grep -q '^definer_functions_unpinned=0$' "$DUMP.sec" \
  || { echo "FAIL: security posture changed by restore"; exit 1; }
echo "PASS: RLS and FORCE RLS on every table, no anon grants, definer functions pin search_path"

if psql -X -q -v ON_ERROR_STOP=1 "$RESTORE_URL" -c "delete from public.audit_log" 2>/dev/null; then
  echo "FAIL: audit_log deletable after restore"; exit 1
fi
echo "PASS: audit_log is still immutable after restore"

psql -X -q "$ADMIN_URL" -c "DROP DATABASE IF EXISTS $RESTORE_DB WITH (FORCE);"
echo "Drill complete. Restore database dropped."
