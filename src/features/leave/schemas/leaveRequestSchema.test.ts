import { describe, expect, it } from 'vitest';
import { leaveRequestSchema, leaveRequestDefaultValues } from '@/features/leave/schemas/leaveRequestSchema';

describe('leaveRequestSchema', () => {
  it('accepts a valid full-day request', () => {
    const result = leaveRequestSchema.safeParse({
      ...leaveRequestDefaultValues,
      leaveTypeId: 'lt-1',
      startDate: '2026-09-14',
      endDate: '2026-09-16',
    });
    expect(result.success).toBe(true);
  });

  it('rejects end date before start date', () => {
    const result = leaveRequestSchema.safeParse({
      ...leaveRequestDefaultValues,
      leaveTypeId: 'lt-1',
      startDate: '2026-09-16',
      endDate: '2026-09-14',
    });
    expect(result.success).toBe(false);
  });

  it('rejects a half-day request spanning more than one date', () => {
    const result = leaveRequestSchema.safeParse({
      ...leaveRequestDefaultValues,
      leaveTypeId: 'lt-1',
      startDate: '2026-09-14',
      endDate: '2026-09-15',
      isHalfDay: true,
      halfDayPeriod: 'am',
    });
    expect(result.success).toBe(false);
  });

  it('rejects a half-day request with no period selected', () => {
    const result = leaveRequestSchema.safeParse({
      ...leaveRequestDefaultValues,
      leaveTypeId: 'lt-1',
      startDate: '2026-09-14',
      endDate: '2026-09-14',
      isHalfDay: true,
      halfDayPeriod: '',
    });
    expect(result.success).toBe(false);
  });

  it('accepts a valid half-day request', () => {
    const result = leaveRequestSchema.safeParse({
      ...leaveRequestDefaultValues,
      leaveTypeId: 'lt-1',
      startDate: '2026-09-14',
      endDate: '2026-09-14',
      isHalfDay: true,
      halfDayPeriod: 'am',
    });
    expect(result.success).toBe(true);
  });
});
