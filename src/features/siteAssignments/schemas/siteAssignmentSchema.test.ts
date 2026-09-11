import { describe, it, expect } from 'vitest';
import { siteAssignmentSchema } from './siteAssignmentSchema';

describe('siteAssignmentSchema', () => {
  it('accepts a valid assignment with no end date', () => {
    expect(
      siteAssignmentSchema.safeParse({ siteId: 's1', employeeId: 'e1', startDate: '2026-01-01' }).success,
    ).toBe(true);
  });

  it('accepts an end date on or after the start date', () => {
    expect(
      siteAssignmentSchema.safeParse({
        siteId: 's1',
        employeeId: 'e1',
        startDate: '2026-01-01',
        endDate: '2026-06-01',
      }).success,
    ).toBe(true);
  });

  it('rejects an end date before the start date', () => {
    const result = siteAssignmentSchema.safeParse({
      siteId: 's1',
      employeeId: 'e1',
      startDate: '2026-06-01',
      endDate: '2026-01-01',
    });
    expect(result.success).toBe(false);
  });

  it('rejects a missing site', () => {
    expect(siteAssignmentSchema.safeParse({ siteId: '', employeeId: 'e1', startDate: '2026-01-01' }).success).toBe(false);
  });

  it('rejects a missing employee', () => {
    expect(siteAssignmentSchema.safeParse({ siteId: 's1', employeeId: '', startDate: '2026-01-01' }).success).toBe(false);
  });

  it('rejects a missing start date', () => {
    expect(siteAssignmentSchema.safeParse({ siteId: 's1', employeeId: 'e1', startDate: '' }).success).toBe(false);
  });
});
