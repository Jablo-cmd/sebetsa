import { describe, expect, it } from 'vitest';
import { shiftDefinitionSchema } from '@/features/scheduling/schemas/shiftDefinitionSchema';

const valid = { name: 'Day Shift', startTime: '08:00', endTime: '17:00', isOvernight: false, breakMinutes: 30 };

describe('shiftDefinitionSchema', () => {
  it('accepts a valid definition', () => {
    expect(shiftDefinitionSchema.safeParse(valid).success).toBe(true);
  });

  it('rejects an empty name', () => {
    const result = shiftDefinitionSchema.safeParse({ ...valid, name: '  ' });
    expect(result.success).toBe(false);
  });

  it('rejects a malformed start time', () => {
    const result = shiftDefinitionSchema.safeParse({ ...valid, startTime: '25:99' });
    expect(result.success).toBe(false);
  });

  it('accepts an overnight definition where end < start', () => {
    const result = shiftDefinitionSchema.safeParse({ ...valid, startTime: '22:00', endTime: '06:00', isOvernight: true });
    expect(result.success).toBe(true);
  });

  it('rejects a negative break', () => {
    const result = shiftDefinitionSchema.safeParse({ ...valid, breakMinutes: -5 });
    expect(result.success).toBe(false);
  });

  it('rejects a non-integer break', () => {
    const result = shiftDefinitionSchema.safeParse({ ...valid, breakMinutes: 12.5 });
    expect(result.success).toBe(false);
  });
});
