import { describe, it, expect } from 'vitest';
import { siteSchema } from './siteSchema';

describe('siteSchema', () => {
  it('accepts a valid site', () => {
    expect(siteSchema.safeParse({ name: 'Sandton Mall', clientId: 'c1' }).success).toBe(true);
  });

  it('rejects a missing client', () => {
    const result = siteSchema.safeParse({ name: 'Sandton Mall', clientId: '' });
    expect(result.success).toBe(false);
  });

  it('rejects a missing name', () => {
    const result = siteSchema.safeParse({ name: '', clientId: 'c1' });
    expect(result.success).toBe(false);
  });

  it('accepts optional fields omitted', () => {
    expect(siteSchema.safeParse({ name: 'Rosebank Office Park', clientId: 'c1' }).success).toBe(true);
  });
});
