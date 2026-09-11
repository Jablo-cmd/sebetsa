import { describe, expect, it } from 'vitest';
import { shiftSchema } from '@/features/scheduling/schemas/shiftSchema';

const valid = {
  siteId: 'site-1',
  employeeId: 'emp-1',
  supervisorId: '',
  shiftDefinitionId: '',
  date: '2026-09-15',
  startTime: '08:00',
  endTime: '17:00',
  endsNextDay: false,
  notes: '',
};

describe('shiftSchema', () => {
  it('accepts a valid same-day shift', () => {
    expect(shiftSchema.safeParse(valid).success).toBe(true);
  });

  it('rejects a missing site', () => {
    expect(shiftSchema.safeParse({ ...valid, siteId: '' }).success).toBe(false);
  });

  it('rejects equal start and end time', () => {
    expect(shiftSchema.safeParse({ ...valid, endTime: valid.startTime }).success).toBe(false);
  });

  it('rejects an overnight-shaped time range without endsNextDay checked', () => {
    const result = shiftSchema.safeParse({ ...valid, startTime: '22:00', endTime: '06:00', endsNextDay: false });
    expect(result.success).toBe(false);
  });

  it('accepts an overnight shift when endsNextDay is checked', () => {
    const result = shiftSchema.safeParse({ ...valid, startTime: '22:00', endTime: '06:00', endsNextDay: true });
    expect(result.success).toBe(true);
  });
});
