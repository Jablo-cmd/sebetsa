import { describe, it, expect } from 'vitest';
import { teamSchema } from './teamSchema';

describe('teamSchema', () => {
  it('accepts a valid team', () => {
    expect(teamSchema.safeParse({ name: 'Team A', siteId: 's1', leadEmployeeId: 'e1' }).success).toBe(true);
  });

  it('accepts optional fields omitted', () => {
    expect(teamSchema.safeParse({ name: 'Team A' }).success).toBe(true);
  });

  it('rejects an empty name', () => {
    expect(teamSchema.safeParse({ name: '' }).success).toBe(false);
  });

  it('rejects a missing name', () => {
    expect(teamSchema.safeParse({}).success).toBe(false);
  });
});
