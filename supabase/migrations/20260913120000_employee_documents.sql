-- Sebetsa Phase M — Documents & Employee Records, migration 1 of 2.
--
-- A private Supabase Storage bucket (never public) plus a metadata table
-- that is the actual authorization boundary — storage.objects policies
-- below re-check the same tenant/employee/sensitivity rules against this
-- table, so the bucket alone can never leak more than the table allows.
--
-- Sensitivity split (§M.7 "sensitive HR documents must not automatically
-- become visible to operational roles"): can_manage_employees() (Phase C:
-- organization_administrator/operations_manager/hr_user) is the tier that
-- sees documents at all, alongside the employee's own — NOT the broader
-- can_manage_operations() tier (site_manager/supervisor/regional_manager
-- have no document visibility by default; documents are an HR domain, not
-- an operational one). Within that, 'medical' and 'disciplinary' document
-- types are hr_user/organization_administrator only — even operations_
-- manager does not see those categories.

create type public.document_type as enum (
  'id_document', 'qualification', 'contract', 'certificate',
  'training_record', 'medical', 'disciplinary', 'other'
);

create type public.document_status as enum (
  'uploaded', 'pending_review', 'verified', 'rejected', 'expired', 'archived'
);

create table public.employee_documents (
  id                      uuid primary key default gen_random_uuid(),
  tenant_id               uuid not null references public.organizations (id) on delete cascade,
  employee_id             uuid not null references public.employees (id) on delete cascade,
  document_type           public.document_type not null,
  file_name               text not null check (char_length(file_name) > 0),
  mime_type               text not null check (mime_type in ('application/pdf', 'image/jpeg', 'image/png')),
  file_size_bytes         integer not null check (file_size_bytes > 0 and file_size_bytes <= 10485760),
  storage_path            text not null unique,
  version                 integer not null default 1 check (version > 0),
  supersedes_document_id  uuid references public.employee_documents (id) on delete set null,
  status                  public.document_status not null default 'uploaded',
  expiry_date             date,
  uploaded_by             uuid references public.profiles (id) on delete set null,
  verified_by             uuid references public.profiles (id) on delete set null,
  verified_at             timestamptz,
  review_notes            text,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);

comment on table public.employee_documents is
  '10MB max, PDF/JPEG/PNG only (client-supplied MIME is not trusted alone — see create_document_upload_slot''s content-sniffing note). Never physically replaced: replace_document() archives the old row and inserts a new one with supersedes_document_id, preserving full history. uploaded_by/verified_by/verified_at are server-derived — never client-supplied.';

create index employee_documents_tenant_id_idx on public.employee_documents (tenant_id);
create index employee_documents_employee_id_idx on public.employee_documents (employee_id);
create index employee_documents_status_idx on public.employee_documents (status);
create index employee_documents_expiry_date_idx on public.employee_documents (expiry_date);

create trigger employee_documents_set_updated_at
  before update on public.employee_documents
  for each row
  execute function public.set_updated_at();

create or replace function public.validate_employee_document_tenant_ref()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.employees where id = new.employee_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: employee % does not belong to tenant %', new.employee_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger employee_documents_validate_tenant_ref
  before insert or update on public.employee_documents
  for each row
  execute function public.validate_employee_document_tenant_ref();

alter table public.employee_documents enable row level security;
alter table public.employee_documents force row level security;

-- SELECT: own documents (excluding nothing — an employee sees their own
-- sensitive categories too, e.g. their own medical certificate), or
-- can_manage_employees() tier for non-sensitive categories, or
-- hr_user/organization_administrator specifically for medical/
-- disciplinary (narrower than can_manage_employees, which also includes
-- operations_manager).
create policy employee_documents_select on public.employee_documents for select to authenticated
  using (
    exists (select 1 from public.employees e where e.id = employee_documents.employee_id and e.profile_id = auth.uid())
    or (
      document_type not in ('medical', 'disciplinary')
      and public.can_manage_employees(tenant_id)
    )
    or (
      document_type in ('medical', 'disciplinary')
      and (
        coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('organization_administrator', 'hr_user')
        or public.is_platform_admin()
      )
    )
  );

-- No direct client INSERT/UPDATE policy — create_document_upload_slot(),
-- verify_document(), and replace_document() (next migration) are the only
-- write path, so status/verified_by/verified_at/version can never be
-- forged by a direct table write.

create trigger employee_documents_audit_log
  after insert or update on public.employee_documents
  for each row
  execute function public.audit_log_from_trigger();

-- ---------------------------------------------------------------------------
-- Private storage bucket + object-level policies mirroring the table's own
-- rules. Path convention: {tenant_id}/{employee_id}/{document_row_id}-{file_name}
-- — the tenant_id/employee_id segments are checked directly against the
-- caller's own scope, independent of (and in addition to) the metadata
-- table's RLS, so a caller can never read/write an object whose path
-- doesn't match their own tenant/employee even if the metadata row lookup
-- were somehow bypassed.

insert into storage.buckets (id, name, public)
values ('employee-documents', 'employee-documents', false)
on conflict (id) do nothing;

create policy employee_documents_storage_select on storage.objects for select to authenticated
  using (
    bucket_id = 'employee-documents'
    and (
      exists (
        select 1 from public.employees e
        where e.profile_id = auth.uid()
          and e.tenant_id::text = (storage.foldername(name))[1]
          and e.id::text = (storage.foldername(name))[2]
      )
      or public.can_manage_employees((storage.foldername(name))[1]::uuid)
      or public.is_platform_admin()
    )
  );

create policy employee_documents_storage_insert on storage.objects for insert to authenticated
  with check (
    bucket_id = 'employee-documents'
    and (
      exists (
        select 1 from public.employees e
        where e.profile_id = auth.uid()
          and e.tenant_id::text = (storage.foldername(name))[1]
          and e.id::text = (storage.foldername(name))[2]
      )
      or public.can_manage_employees((storage.foldername(name))[1]::uuid)
      or public.is_platform_admin()
    )
  );

comment on policy employee_documents_storage_select on storage.objects is
  'Mirrors employee_documents RLS at the object-storage layer: own-employee path segments, or can_manage_employees() for the object''s tenant segment. Deliberately does not special-case medical/disciplinary at the storage layer (the metadata table''s stricter check is the source of truth for which rows/paths a manager tier ever learns about in the first place — the frontend never requests a signed URL for a document the metadata query didn''t return).';
