import { describe, expect, it } from 'vitest';
import { availabilityWindowSchema, availabilityExceptionSchema } from '@/features/availability/schemas/availabilitySchema';

describe('availabilityWindowSchema', () => {
  it('accepts a valid window', () => {
    expect(availabilityWindowSchema.safeParse({ dayOfWeek: 1, startTime: '08:00', endTime: '17:00' }).success).toBe(true);
  });

  it('rejects end time before start time', () => {
    expect(availabilityWindowSchema.safeParse({ dayOfWeek: 1, startTime: '17:00', endTime: '08:00' }).success).toBe(false);
  });

  it('rejects a day of week outside 0-6', () => {
    expect(availabilityWindowSchema.safeParse({ dayOfWeek: 7, startTime: '08:00', endTime: '17:00' }).success).toBe(false);
  });
});

describe('availabilityExceptionSchema', () => {
  it('accepts an all-day unavailable exception with no times', () => {
    const result = availabilityExceptionSchema.safeParse({
      exceptionDate: '2026-09-20',
      isAvailable: false,
      startTime: '',
      endTime: '',
      reason: 'personal',
    });
    expect(result.success).toBe(true);
  });

  it('accepts a narrowed-availability exception with a valid time window', () => {
    const result = availabilityExceptionSchema.safeParse({
      exceptionDate: '2026-09-20',
      isAvailable: true,
      startTime: '09:00',
      endTime: '12:00',
      reason: '',
    });
    expect(result.success).toBe(true);
  });

  it('rejects a missing date', () => {
    const result = availabilityExceptionSchema.safeParse({
      exceptionDate: '',
      isAvailable: false,
      startTime: '',
      endTime: '',
      reason: '',
    });
    expect(result.success).toBe(false);
  });

  it('rejects end time before start time', () => {
    const result = availabilityExceptionSchema.safeParse({
      exceptionDate: '2026-09-20',
      isAvailable: true,
      startTime: '12:00',
      endTime: '09:00',
      reason: '',
    });
    expect(result.success).toBe(false);
  });
});
