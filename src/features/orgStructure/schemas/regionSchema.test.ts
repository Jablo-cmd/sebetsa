import { describe, it, expect } from 'vitest';
import { regionSchema } from './regionSchema';

describe('regionSchema', () => {
  it('accepts a valid region', () => {
    expect(regionSchema.safeParse({ name: 'Gauteng', code: 'GP' }).success).toBe(true);
  });

  it('accepts an omitted/empty code', () => {
    expect(regionSchema.safeParse({ name: 'Gauteng' }).success).toBe(true);
    expect(regionSchema.safeParse({ name: 'Gauteng', code: '' }).success).toBe(true);
  });

  it('rejects an empty name', () => {
    const result = regionSchema.safeParse({ name: '' });
    expect(result.success).toBe(false);
  });

  it('rejects a whitespace-only name', () => {
    const result = regionSchema.safeParse({ name: '   ' });
    expect(result.success).toBe(false);
  });

  it('rejects a missing name', () => {
    expect(regionSchema.safeParse({}).success).toBe(false);
  });
});
