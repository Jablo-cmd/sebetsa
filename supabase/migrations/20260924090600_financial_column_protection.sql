-- Sebetsa Phase Z — Financial column protection (retroactive hardening).
--
-- A real gap found during this sprint's own adversarial review: the
-- pre-existing quotes_write_by_manager RLS policy (Phase R, prior pass)
-- is row-level only — it does not stop an authorized manager's direct
-- table UPDATE from setting quotes.subtotal/tax_amount/total_amount to
-- an arbitrary value, bypassing recompute_quote_totals() entirely.
--
-- The first fix attempted here was `revoke update (col) ... from
-- authenticated`. That does NOT work in this codebase, and adversarial
-- RLS testing caught it: 00_auth_stub.sql documents (and every real
-- Supabase project does) `alter default privileges in schema public
-- grant all on tables to authenticated`, which grants a TABLE-LEVEL
-- UPDATE privilege at CREATE TABLE time. Postgres column-level REVOKE
-- cannot narrow a table-level grant that already covers the same
-- privilege — the table-level grant wins. This is the exact "gotcha"
-- already documented against `profiles` in 20260911100300 (see its own
-- comment referencing 20260802151501): a column-level GRANT/REVOKE
-- alone is never sufficient here.
--
-- The mechanism that actually works, and is already proven elsewhere in
-- this codebase (public.prevent_direct_role_change() guarding
-- profiles.role), is a BEFORE UPDATE trigger gated by a transaction-
-- local flag that only the trusted SECURITY DEFINER RPC sets
-- immediately before its own UPDATE, and clears immediately after. A
-- real PostgREST call is always its own transaction, so the flag would
-- naturally revert at commit either way — it is explicitly reset here
-- too so the guarantee also holds for any caller (including this
-- codebase's own multi-statement RLS test transactions) that invokes
-- several RPCs inside one transaction.

create or replace function public.prevent_direct_quote_financial_change()
returns trigger
language plpgsql
as $$
begin
  if (
    new.subtotal is distinct from old.subtotal
    or new.tax_amount is distinct from old.tax_amount
    or new.total_amount is distinct from old.total_amount
  ) and coalesce(current_setting('app.allow_financial_recompute', true), '') <> 'true' then
    raise exception 'insufficient_privilege: quote subtotal/tax_amount/total_amount can only be changed via recompute_quote_totals()';
  end if;
  return new;
end;
$$;

create trigger quotes_prevent_direct_financial_change
  before update on public.quotes
  for each row
  execute function public.prevent_direct_quote_financial_change();

comment on function public.prevent_direct_quote_financial_change() is
  'Blocks any direct UPDATE of quotes.subtotal/tax_amount/total_amount unless app.allow_financial_recompute is set true for the current transaction — only recompute_quote_totals() sets it, immediately before its own UPDATE.';

-- Re-declare recompute_quote_totals() (originally defined in
-- 20260922090200_quotes_and_proposals.sql, already applied/pushed and
-- therefore never edited in place) purely to set the trusted flag before
-- its UPDATE. Behaviourally identical otherwise.
create or replace function public.recompute_quote_totals(p_quote_id uuid)
returns public.quotes
language plpgsql
security definer
set search_path = public
as $$
declare
  v_quote public.quotes;
  v_subtotal numeric(12, 2);
  v_tax numeric(12, 2);
  v_total numeric(12, 2);
begin
  select * into v_quote from public.quotes where id = p_quote_id;
  if not found then
    raise exception 'not_found: no quote %', p_quote_id;
  end if;

  if not public.can_manage_org_structure(v_quote.tenant_id) then
    raise exception 'insufficient_privilege: cannot recompute totals for this tenant';
  end if;

  select coalesce(sum(line_total), 0) into v_subtotal from public.quote_line_items where quote_id = p_quote_id;
  v_tax := round((v_subtotal - v_quote.discount_amount) * v_quote.tax_rate / 100.0, 2);
  v_total := v_subtotal - v_quote.discount_amount + v_tax;

  perform set_config('app.allow_financial_recompute', 'true', true);
  update public.quotes
    set subtotal = v_subtotal, tax_amount = v_tax, total_amount = v_total
    where id = p_quote_id
    returning * into v_quote;
  perform set_config('app.allow_financial_recompute', 'false', true);

  perform public.write_audit_log(v_quote.tenant_id, auth.uid(), 'quote_totals_recomputed', 'quotes', v_quote.id, null,
    jsonb_build_object('subtotal', v_subtotal, 'tax_amount', v_tax, 'total_amount', v_total));

  return v_quote;
end;
$$;

revoke execute on function public.recompute_quote_totals(uuid) from public, anon;
grant execute on function public.recompute_quote_totals(uuid) to authenticated;
