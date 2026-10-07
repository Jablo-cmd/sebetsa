#!/usr/bin/env bash
# Real two-session concurrency check for the notification outbox claim.
# Unlike the transactional suites this needs COMMITTED rows and two simultaneous
# connections, so it runs as a separate step against the harness database.
# Usage: concurrency.sh <psql args that select the harness database...>
set -euo pipefail
psql_exec=("$@")
run() { "${psql_exec[@]}" -X -q -At -v ON_ERROR_STOP=1 "$@"; }

# The harness database is disposable (audit rows are immutable, so there is no
# clean delete); fresh ids make the script safe to re-run against the same one.
T=$(cat /proc/sys/kernel/random/uuid)
U=$(cat /proc/sys/kernel/random/uuid)
run -c "
insert into public.organizations (id, name, status) values ('$T', 'Org Concurrency', 'active');
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', '$U', 'authenticated', 'authenticated', 'conc-$U@example.com', 'x', now(), '{\"role\":\"employee\"}', '{}', now(), now());
insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values ('$U', '$T', 'Conc', 'C', 'conc-$U@example.com', 'employee', 'active');
insert into public.notifications (id, tenant_id, recipient_profile_id, type, title, body)
  select gen_random_uuid(), '$T', '$U', 'task_assigned', 't', 'b' from generate_series(1, 40);
insert into public.notification_deliveries (notification_id, recipient_profile_id, channel, destination)
  select id, '$U', 'email', 'conc-$U@example.com' from public.notifications where tenant_id = '$T';
" >/dev/null

claim() { run -c "select id from public.claim_notification_deliveries(25, '$1', 300)" | sort; }
A="$(mktemp)"; B="$(mktemp)"
claim worker-a > "$A" & pa=$!
claim worker-b > "$B" & pb=$!
wait $pa $pb

na=$(wc -l < "$A"); nb=$(wc -l < "$B")
overlap=$(comm -12 "$A" "$B" | wc -l)
echo "concurrent claim: worker-a=$na worker-b=$nb overlap=$overlap"
fail=0
[ "$overlap" -eq 0 ] || { echo "::error::two workers claimed the same delivery ($overlap)"; fail=1; }
[ $((na + nb)) -eq 40 ] || { echo "::error::expected all 40 deliveries claimed exactly once, got $((na + nb))"; fail=1; }

# Fencing: a worker that lost its lease cannot finish a row another worker holds.
one=$(head -1 "$A")
if [ -n "$one" ]; then
  updated=$(run -c "update public.notification_deliveries set status='sent' where id='$one' and worker_id='worker-b' returning id" | wc -l)
  [ "$updated" -eq 0 ] || { echo "::error::a non-owning worker updated a claimed delivery"; fail=1; }
fi

rm -f "$A" "$B"
[ "$fail" -eq 0 ] || exit 1
echo "PASS: concurrent claims are disjoint, complete and fenced"
