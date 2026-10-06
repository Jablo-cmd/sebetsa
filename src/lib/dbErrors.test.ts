import { describe, it, expect } from 'vitest';
import { getDbErrorMessage } from '@/lib/dbErrors';

describe('getDbErrorMessage', () => {
  it('maps a custom insufficient_privilege RAISE EXCEPTION to safe copy', () => {
    const error = { message: 'insufficient_privilege: cannot manage employees for this tenant', code: 'P0001' };
    expect(getDbErrorMessage(error, 'fallback')).toBe("You don't have permission to do this.");
  });

  it('maps a custom not_found RAISE EXCEPTION to safe copy', () => {
    const error = { message: 'not_found: no employee 11110000-0000-0000-0000-000000000001', code: 'P0001' };
    expect(getDbErrorMessage(error, 'fallback')).toBe('The requested record could not be found.');
  });

  it('passes through a conflict: RAISE EXCEPTION message as-is (already user-facing, no schema names)', () => {
    const error = { message: 'conflict: employee already has an overlapping shift on monday', code: 'P0001' };
    expect(getDbErrorMessage(error, 'fallback')).toBe('employee already has an overlapping shift on monday');
  });

  it('maps a unique_violation SQLSTATE to safe copy without the constraint name', () => {
    const error = {
      message: 'duplicate key value violates unique constraint "employees_tenant_id_employee_number_key"',
      code: '23505',
    };
    const result = getDbErrorMessage(error, 'fallback');
    expect(result).not.toMatch(/employees_tenant_id_employee_number_key/);
    expect(result).toBe('This already exists — please check for a duplicate entry.');
  });

  it('maps a separation_of_duties RAISE EXCEPTION to an explanatory message', () => {
    const error = { message: 'separation_of_duties: leave.decide — you cannot act on your own record', code: '42501' };
    expect(getDbErrorMessage(error, 'fallback')).toMatch(/cannot approve, verify or close a record you raised/);
  });

  it('maps a cross_tenant_reference RAISE EXCEPTION without leaking ids', () => {
    const error = { message: 'cross_tenant_reference: site 123 does not belong to tenant 456', code: 'P0001' };
    const result = getDbErrorMessage(error, 'fallback');
    expect(result).not.toMatch(/123|456/);
  });

  it('maps a foreign_key_violation SQLSTATE to safe copy', () => {
    const error = { message: 'update or delete on table "departments" violates foreign key constraint', code: '23503' };
    expect(getDbErrorMessage(error, 'fallback')).toBe("This action can't be completed because it's linked to other records.");
  });

  it('falls back to the provided message for an unrecognized Postgres error', () => {
    const error = { message: 'some obscure internal detail', code: '55000' };
    expect(getDbErrorMessage(error, 'Failed to save record.')).toBe('Failed to save record.');
  });

  it('never leaks the raw message of an unrecognized Postgres error', () => {
    const error = { message: 'column "secret_internal_column" does not exist', code: '42703' };
    const result = getDbErrorMessage(error, 'Failed to save record.');
    expect(result).not.toMatch(/secret_internal_column/);
  });

  it('returns a plain Error message unchanged (non-database errors, e.g. network failures)', () => {
    expect(getDbErrorMessage(new Error('Failed to fetch'), 'fallback')).toBe('Failed to fetch');
  });

  it('falls back for a non-Error, non-Postgrest thrown value', () => {
    expect(getDbErrorMessage('a plain string was thrown', 'fallback')).toBe('fallback');
  });
});
