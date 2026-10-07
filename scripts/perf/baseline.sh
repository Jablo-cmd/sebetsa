#!/usr/bin/env bash
# Performance baseline against a DISPOSABLE local database: seeds a realistic tenant, then measures every page-level query
# (execution time under RLS as three roles vs. no RLS, rows, payload), prints the plans' scan types, and runs a modest
# concurrent load. Never run against a hosted project.
#
#   ADMIN_URL=postgresql://postgres@localhost:55432/postgres?host=/tmp  TEMPLATE_DB=sebetsa_rls_test  scripts/perf/baseline.sh
set -euo pipefail
ADMIN_URL="${ADMIN_URL:?ADMIN_URL (maintenance database on a disposable cluster) is required}"
case "$ADMIN_URL" in *supabase.co*|*supabase.com*|*pooler*) echo "Refusing to run against a hosted project." >&2; exit 2;; esac
TEMPLATE_DB="${TEMPLATE_DB:-sebetsa_rls_test}"
PERF_DB="sebetsa_perf"
REGIONS="${REGIONS:-5}" CLIENTS="${CLIENTS:-20}" SITES="${SITES:-200}" EMPLOYEES="${EMPLOYEES:-2000}" DAYS="${DAYS:-30}"
CLIENTS_LOAD="${CLIENTS_LOAD:-20}" LOAD_SECONDS="${LOAD_SECONDS:-30}" RUNS="${RUNS:-7}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="${ADMIN_URL%%\?*}"; BASE="${BASE%/*}"; QS=""; [[ "$ADMIN_URL" == *\?* ]] && QS="?${ADMIN_URL#*\?}"
PERF_URL="$BASE/$PERF_DB$QS"

psql -X -q "$ADMIN_URL" -c "DROP DATABASE IF EXISTS $PERF_DB WITH (FORCE);" -c "CREATE DATABASE $PERF_DB TEMPLATE $TEMPLATE_DB;"
echo "== Seeding ($REGIONS regions, $CLIENTS clients, $SITES sites, $EMPLOYEES employees, $DAYS days)"
t0=$(date +%s)
psql -X -q -v regions="$REGIONS" -v clients="$CLIENTS" -v sites="$SITES" -v employees="$EMPLOYEES" -v days="$DAYS" "$PERF_URL" -f "$DIR/seed.sql"
echo "seeded in $(( $(date +%s) - t0 )) s"
psql -X -At "$PERF_URL" -c "select format('%-22s %s', t, n) from (values
  ('employees', (select count(*) from public.employees)), ('sites', (select count(*) from public.sites)),
  ('shifts', (select count(*) from public.shifts)), ('attendance_records', (select count(*) from public.attendance_records)),
  ('tasks', (select count(*) from public.tasks)), ('leave_requests', (select count(*) from public.leave_requests))) v(t, n);"
echo "database size: $(psql -X -At "$PERF_URL" -c "select pg_size_pretty(pg_database_size('$PERF_DB'))")"

echo "== Per-query measurement ($RUNS runs each after 1 warm-up; execution time in ms, median / max)"
psql -X -At -F'|' "$PERF_URL" -f "$DIR/queries.sql" > /tmp/perf_queries.txt
python3 - "$PERF_URL" "$RUNS" <<'PY'
import subprocess, sys, json, statistics
url, runs = sys.argv[1], int(sys.argv[2])
queries = [l.rstrip("\n").split("|", 1) for l in open("/tmp/perf_queries.txt") if "|" in l]
roles = {
  "no-RLS (owner)": None,
  "org admin": ("organization_administrator", "00000000-0000-0000-0000-00000000ab01"),
  "site manager (region scope)": ("site_manager", "00000000-0000-0000-0000-00000000ab02"),
  "employee": ("employee", "00000000-0000-0000-0000-00000000ab03"),
}
def run(sql_text):
    return subprocess.run(["psql", "-X", "-At", url, "-v", "ON_ERROR_STOP=1"], input=sql_text, capture_output=True, text=True)
def measure(q, role):
    pre = ""
    if role:
        pre = "set local role authenticated; select set_config('request.jwt.claims', '%s', true);" % json.dumps({"aal": "aal2", "sub": role[1], "app_metadata": {"role": role[0]}}).replace("'", "''")
    times, plan_info = [], ""
    for i in range(runs + 1):
        out = run("begin; %s explain (analyze, buffers, format json) %s; rollback;" % (pre, q))
        text = out.stdout.strip()
        if out.returncode != 0 or not text.startswith("["):
            return None, out.stderr.strip()[:200] or text[:200], 0, 0
        plan = json.loads(text)[0]
        if i > 0:
            times.append(plan["Execution Time"])
        if i == runs:
            def nodes(n):
                yield n
                for c in n.get("Plans", []): yield from nodes(c)
            kinds = sorted({n["Node Type"] for n in nodes(plan["Plan"]) if "Scan" in n["Node Type"]})
            plan_info = ", ".join(kinds)
            rows = plan["Plan"].get("Actual Rows", 0)
            buffers = plan["Plan"].get("Shared Hit Blocks", 0) + plan["Plan"].get("Shared Read Blocks", 0)
    # payload: JSON size of the result rows
    out = run("begin; %s select coalesce(sum(length(t::text)), 0), count(*) from (%s) t; rollback;" % (pre, q))
    nums = out.stdout.strip().splitlines()[-1].split("|") if out.stdout.strip() else ["0", "0"]
    return times, plan_info, int(nums[0] or 0), int(nums[1] or 0)
print("%-52s %-27s %9s %9s %8s %9s  %s" % ("query", "role", "median", "max", "rows", "payload", "scans"))
for name, q in queries:
    for rname, role in roles.items():
        times, info, payload, rows = measure(q, role)
        if times is None:
            print("%-52s %-27s ERROR %s" % (name[:52], rname, info)); continue
        print("%-52s %-27s %7.2fms %7.2fms %8d %8dB  %s" % (name[:52], rname, statistics.median(times), max(times), rows, payload, info))
PY

echo "== Concurrent load: $CLIENTS_LOAD clients, ${LOAD_SECONDS}s, mixed read workload as org admin / site manager / employee"
mkdir -p /tmp/perf_load && rm -f /tmp/perf_load/*
mk() { # name role-json sql weight
  printf '\\set one 1\nbegin;\nset local role authenticated;\nselect set_config('"'"'request.jwt.claims'"'"', '"'"'%s'"'"', true);\n%s;\ncommit;\n' "$2" "$3" > "/tmp/perf_load/$1.sql"
}
ADMIN='{"aal":"aal2","sub":"00000000-0000-0000-0000-00000000ab01","app_metadata":{"role":"organization_administrator"}}'
MGR='{"aal":"aal2","sub":"00000000-0000-0000-0000-00000000ab02","app_metadata":{"role":"site_manager"}}'
EMP='{"aal":"aal2","sub":"00000000-0000-0000-0000-00000000ab03","app_metadata":{"role":"employee"}}'
T="'00000000-0000-0000-0000-00000000aa01'"
mk metrics "$ADMIN" "select * from public.get_operational_metrics($T::uuid, current_date - 30, current_date)"
mk employees "$ADMIN" "select * from public.employees where tenant_id = $T order by last_name, first_name limit 25"
mk sites "$MGR" "select * from public.sites where tenant_id = $T order by name limit 25"
mk shifts "$MGR" "select * from public.shifts where tenant_id = $T and site_id = '00000000-0000-0000-0003-000000000007' and starts_at >= date_trunc('week', now()) and starts_at < date_trunc('week', now()) + interval '7 days'"
mk attendance "$MGR" "select * from public.attendance_records where tenant_id = $T and site_id = '00000000-0000-0000-0003-000000000007' and clock_in_at >= now() - interval '7 days' order by clock_in_at desc limit 50"
mk tasks_mgr "$ADMIN" "select * from public.tasks where tenant_id = $T and status in ('open','in_progress') order by due_at nulls last limit 50"
mk tasks_emp "$EMP" "select * from public.tasks where tenant_id = $T and assignee_id = '00000000-0000-0000-0004-000000000001' order by due_at limit 50"
mk myshifts "$EMP" "select * from public.shifts where tenant_id = $T and employee_id = '00000000-0000-0000-0004-000000000001' and starts_at >= now() order by starts_at limit 50"
pgbench -n -c "$CLIENTS_LOAD" -j 4 -T "$LOAD_SECONDS" -l --log-prefix /tmp/perf_load/log \
  -f /tmp/perf_load/metrics.sql@2 -f /tmp/perf_load/employees.sql@15 -f /tmp/perf_load/sites.sql@10 -f /tmp/perf_load/shifts.sql@20 \
  -f /tmp/perf_load/attendance.sql@15 -f /tmp/perf_load/tasks_mgr.sql@10 -f /tmp/perf_load/tasks_emp.sql@14 -f /tmp/perf_load/myshifts.sql@14 "$PERF_URL" | tee /tmp/perf_load/summary.txt
python3 - <<'PY'
import glob
lat=[]
for f in glob.glob('/tmp/perf_load/log*'):
    for l in open(f):
        p=l.split()
        if len(p)>=3 and p[1].lstrip('-').isdigit(): lat.append(int(p[2])/1000.0)
lat.sort()
if lat:
    q=lambda x: lat[min(len(lat)-1,int(len(lat)*x))]
    print("transactions=%d  latency ms: p50=%.1f p95=%.1f p99=%.1f max=%.1f" % (len(lat), q(.5), q(.95), q(.99), lat[-1]))
PY
psql -X -q "$ADMIN_URL" -c "DROP DATABASE IF EXISTS $PERF_DB WITH (FORCE);"
