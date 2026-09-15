-- Sebetsa — P1 security remediation (production-readiness audit,
-- docs/PRODUCTION_READINESS_AUDIT.md, High finding: storage-layer
-- medical/disciplinary sensitivity bypass).
--
-- employee_documents_select (20260913120000_employee_documents.sql)
-- correctly restricts 'medical'/'disciplinary' document_type rows to
-- organization_administrator/hr_user (narrower than the general
-- can_manage_employees() tier, which also includes operations_manager).
-- The storage.objects policy never replicated this — it only checked
-- tenant/employee path segments, so an operations_manager (excluded at
-- the metadata layer) could call the Storage API directly
-- (`.storage.from('employee-documents').list(...)`/`createSignedUrl()`)
-- and read a medical/disciplinary file's bytes despite never being able
-- to see that row in the employee_documents table. The migration's own
-- comment rationalized this as "the frontend never requests a signed URL
-- for a document the metadata query didn't return" — a trust-the-client
-- assumption, not a real boundary.
--
-- Fixed by joining storage.objects.name directly to
-- employee_documents.storage_path (an exact 1:1 match — every uploaded
-- object's storage path is stored on its own metadata row at insert time,
-- see create_document_upload_slot()/replace_document()) and reproducing
-- the metadata table's exact document_type check, rather than re-deriving
-- ownership from path segments alone. This also fails closed for any
-- object with no matching metadata row, which the old path-parsing
-- approach did not.

drop policy if exists employee_documents_storage_select on storage.objects;

create policy employee_documents_storage_select on storage.objects for select to authenticated
  using (
    bucket_id = 'employee-documents'
    and exists (
      select 1 from public.employee_documents ed
      where ed.storage_path = storage.objects.name
        and (
          exists (select 1 from public.employees e where e.id = ed.employee_id and e.profile_id = auth.uid())
          or (
            ed.document_type not in ('medical', 'disciplinary')
            and public.can_manage_employees(ed.tenant_id)
          )
          or (
            ed.document_type in ('medical', 'disciplinary')
            and (
              coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('organization_administrator', 'hr_user')
              or public.is_platform_admin()
            )
          )
        )
    )
  );

comment on policy employee_documents_storage_select on storage.objects is
  'Mirrors employee_documents_select exactly, via a direct join on storage_path rather than re-deriving ownership from path segments — closes the medical/disciplinary sensitivity-tier bypass an operations_manager previously had through the Storage API (docs/PRODUCTION_READINESS_AUDIT.md, storage security finding).';
