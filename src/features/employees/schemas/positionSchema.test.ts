import { describe, it, expect } from 'vitest';
import { positionSchema } from './positionSchema';

describe('positionSchema', () => {
  it('accepts a valid position', () => {
    expect(positionSchema.safeParse({ title: 'Site Supervisor', departmentId: 'd1' }).success).toBe(true);
  });

  it('accepts an omitted department', () => {
    expect(positionSchema.safeParse({ title: 'Cleaner' }).success).toBe(true);
  });

  it('rejects an empty title', () => {
    expect(positionSchema.safeParse({ title: '' }).success).toBe(false);
  });

  it('rejects a whitespace-only title', () => {
    expect(positionSchema.safeParse({ title: '   ' }).success).toBe(false);
  });

  it('rejects a missing title', () => {
    expect(positionSchema.safeParse({}).success).toBe(false);
  });
});
