#!/usr/bin/env bash
# Regenerates src/lib/database.types.ts from the migrations.
#
# 1. Applies every migration to a disposable database via the RLS harness
#    (needs either Docker, or RLS_DATABASE_URL pointing at a throwaway
#    PostgreSQL server — see supabase/rls-tests/run.sh).
# 2. Generates TypeScript types from that database with the same generator the
#    Supabase CLI uses (@supabase/postgres-meta, version pinned below).
# 3. Post-processes: keeps the `graphql_public` schema block the hosted API
#    exposes, and lets default-null RPC arguments accept `null` (PostgREST does).
#
# Usage:
#   RLS_DATABASE_URL=postgresql://postgres@localhost:5432/postgres scripts/generate-db-types.sh
#   (CI runs it with --check to fail when the committed file is stale.)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="$ROOT/src/lib/database.types.ts"
PG_META_VERSION="0.100.0"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ -z "${RLS_DATABASE_URL:-}" ]; then
  echo "RLS_DATABASE_URL (a disposable PostgreSQL server) is required to generate types." >&2
  exit 2
fi

# Build the schema (the harness recreates database sebetsa_rls_test). Set
# SKIP_HARNESS=1 when that database has already been built (CI does this).
if [ "${SKIP_HARNESS:-}" != "1" ]; then
  bash "$ROOT/supabase/rls-tests/run.sh" > "$WORK/harness.log" 2>&1 || { tail -30 "$WORK/harness.log" >&2; echo "RLS harness failed; cannot generate types" >&2; exit 1; }
fi

GEN_URL="$(printf '%s' "$RLS_DATABASE_URL" | sed -E 's#/[^/?]*(\?|$)#/sebetsa_rls_test\1#')"

(cd "$WORK" && npm init -y >/dev/null 2>&1 && npm i "@supabase/postgres-meta@$PG_META_VERSION" --no-audit --no-fund >/dev/null 2>&1)
PG_META_DB_URL="$GEN_URL" PG_META_GENERATE_TYPES=typescript PG_META_GENERATE_TYPES_INCLUDED_SCHEMAS=public \
  node "$WORK/node_modules/@supabase/postgres-meta/dist/server/server.js" > "$WORK/generated.ts" 2> "$WORK/generator.err" \
  || { cat "$WORK/generator.err" >&2; exit 1; }

python3 - "$WORK/generated.ts" "$WORK/final.ts" <<'PY'
import re, sys
src = open(sys.argv[1]).read().split('\n')

graphql_type = '''  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }'''.split('\n')
graphql_const = ['  graphql_public: {', '    Enums: {},', '  },']

k = src.index('export type Database = {')
src[k + 1:k + 1] = graphql_type
c = src.index('export const Constants = {')
src[c + 1:c + 1] = graphql_const

out = '\n'.join(src)

# Arguments the app intentionally passes as NULL to PL/pgSQL functions whose SQL
# signature has no DEFAULT for them (a function body that treats NULL as "not
# given"). The generator cannot know this, so it is declared here, explicitly.
NULLABLE_ARGS = {
    'upsert_compliance_record': ['p_id', 'p_site_id', 'p_client_id', 'p_contract_id', 'p_responsible_profile_id', 'p_due_date', 'p_expiry_date'],
    'upsert_employee_qualification': ['p_id'],
}
for fn, args in NULLABLE_ARGS.items():
    m = re.search(r'^      ' + fn + r': \{\n        Args: \{\n(.*?)\n        \}\n', out, flags=re.M | re.S)
    if not m:
        raise SystemExit(f'generate-db-types: function {fn} not found for NULLABLE_ARGS')
    block = m.group(1)
    for arg in args:
        block, n = re.subn(r'^(\s+' + arg + r': )((?!.*\| null)[^\n]+)$', r'\1\2 | null', block, flags=re.M)
    out = out[:m.start(1)] + block + out[m.end(1):]
# RPC arguments with a SQL DEFAULT are optional and PostgREST accepts null for them.
out = re.sub(r'^(\s+p_[a-z0-9_]+\?: )((?!.*\| null)[^\n]+)$', r'\1\2 | null', out, flags=re.M)
open(sys.argv[2], 'w').write(out)
PY

# The E2E backend (e2e/utils/fakeBackend.ts) must know every table's columns and
# literal defaults exactly as PostgreSQL does. Emit them from the same database.
E2E_TARGET="$ROOT/e2e/utils/schemaDefaults.ts"
psql -X -At -F'|' "$GEN_URL" -c "select table_name, string_agg(column_name, ' ' order by ordinal_position) from information_schema.columns where table_schema='public' and table_name in (select tablename from pg_tables where schemaname='public') group by table_name order by 1" > "$WORK/columns.txt"
psql -X -At -F'|' "$GEN_URL" -c "select table_name, column_name, column_default from information_schema.columns where table_schema='public' and column_default is not null and column_default not like 'gen_random_uuid%' and column_default not like 'now()%' and column_default not like 'nextval%' and table_name in (select tablename from pg_tables where schemaname='public') order by 1,2" > "$WORK/defaults.txt"
python3 - "$WORK/columns.txt" "$WORK/defaults.txt" "$WORK/schemaDefaults.ts" <<'PY'
import json, re, sys
columns, defaults, out = sys.argv[1:4]
cols = {}
for line in open(columns):
    table, names = line.rstrip('\n').split('|', 1)
    cols[table] = names.split(' ')
lit, today = {}, {}
for line in open(defaults):
    table, column, value = line.rstrip('\n').split('|', 2)
    m = re.match(r"^'(.*)'::[\w\. \[\]\"]+$", value)
    if value == 'CURRENT_DATE':
        today.setdefault(table, []).append(column)
        continue
    if m:
        v = m.group(1)
    elif value in ('true', 'false'):
        v = value == 'true'
    elif re.match(r'^-?\d+$', value):
        v = int(value)
    elif re.match(r"^\(?'?-?\d+(\.\d+)?'?\)?(::numeric)?$", value):
        v = float(re.sub(r"[^\d.\-]", '', value))
    else:
        raise SystemExit(f'generate-db-types: unhandled column default {table}.{column} = {value}')
    lit.setdefault(table, {})[column] = v
header = '''/**
 * GENERATED by scripts/generate-db-types.sh from supabase/migrations — do not
 * edit. Column lists and literal defaults of the Sebetsa schema, applied by the
 * E2E fake backend on insert exactly as PostgreSQL would (function defaults —
 * ids, timestamps — are handled in fakeBackend.ts).
 */
'''
body = header
body += '/** Every column of every table: omitted nullable columns come back as null, like PostgREST. */\n'
body += 'export const TABLE_COLUMNS: Record<string, string[]> = ' + json.dumps(cols, indent=2) + ';\n\n'
body += '/** Defaults that depend on "today" (CURRENT_DATE): table -> columns. */\n'
body += 'export const CURRENT_DATE_DEFAULTS: Record<string, string[]> = ' + json.dumps(today, indent=2) + ';\n\n'
body += 'export const COLUMN_DEFAULTS: Record<string, Record<string, unknown>> = ' + json.dumps(lit, indent=2) + ';\n'
open(out, 'w').write(body)
PY

if [ "${1:-}" = "--check" ]; then
  stale=0
  if ! diff -q "$WORK/final.ts" "$TARGET" >/dev/null; then
    echo "::error::src/lib/database.types.ts is out of date with supabase/migrations. Run scripts/generate-db-types.sh and commit." >&2
    diff -u "$TARGET" "$WORK/final.ts" | head -40 >&2 || true
    stale=1
  fi
  if ! diff -q "$WORK/schemaDefaults.ts" "$E2E_TARGET" >/dev/null; then
    echo "::error::e2e/utils/schemaDefaults.ts is out of date with supabase/migrations. Run scripts/generate-db-types.sh and commit." >&2
    diff -u "$E2E_TARGET" "$WORK/schemaDefaults.ts" | head -40 >&2 || true
    stale=1
  fi
  [ "$stale" = 0 ] || exit 1
  echo "database.types.ts and e2e/utils/schemaDefaults.ts are up to date"
else
  cp "$WORK/final.ts" "$TARGET"
  cp "$WORK/schemaDefaults.ts" "$E2E_TARGET"
  echo "Wrote $TARGET and $E2E_TARGET"
fi
