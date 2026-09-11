import { describe, it, expect } from 'vitest';
import { clientSchema } from './clientSchema';

describe('clientSchema', () => {
  it('accepts a minimal valid client (name only)', () => {
    expect(clientSchema.safeParse({ name: 'ACME Property Group' }).success).toBe(true);
  });

  it('accepts a fully populated client', () => {
    expect(
      clientSchema.safeParse({
        name: 'ACME Property Group',
        regionId: 'r1',
        industry: 'Retail Property',
        primaryContactName: 'Jane Doe',
        primaryContactEmail: 'jane@acme.co.za',
        primaryContactPhone: '0821234567',
      }).success,
    ).toBe(true);
  });

  it('rejects an empty name', () => {
    expect(clientSchema.safeParse({ name: '' }).success).toBe(false);
  });

  it('rejects an invalid contact email', () => {
    const result = clientSchema.safeParse({ name: 'ACME', primaryContactEmail: 'not-an-email' });
    expect(result.success).toBe(false);
  });

  it('accepts an omitted contact email', () => {
    expect(clientSchema.safeParse({ name: 'ACME' }).success).toBe(true);
  });
});
