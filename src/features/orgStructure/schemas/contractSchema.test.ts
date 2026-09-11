import { describe, it, expect } from 'vitest';
import { contractSchema } from './contractSchema';

describe('contractSchema', () => {
  it('accepts a valid contract with no end date', () => {
    expect(
      contractSchema.safeParse({
        clientId: 'c1',
        contractNumber: 'SRV-2026-001',
        startDate: '2026-01-01',
        siteIds: [],
      }).success,
    ).toBe(true);
  });

  it('accepts an end date on or after the start date', () => {
    expect(
      contractSchema.safeParse({
        clientId: 'c1',
        contractNumber: 'SRV-2026-001',
        startDate: '2026-01-01',
        endDate: '2026-12-31',
        siteIds: [],
      }).success,
    ).toBe(true);
    expect(
      contractSchema.safeParse({
        clientId: 'c1',
        contractNumber: 'SRV-2026-001',
        startDate: '2026-01-01',
        endDate: '2026-01-01',
        siteIds: [],
      }).success,
    ).toBe(true);
  });

  it('rejects an end date before the start date', () => {
    const result = contractSchema.safeParse({
      clientId: 'c1',
      contractNumber: 'SRV-2026-001',
      startDate: '2026-06-01',
      endDate: '2026-01-01',
      siteIds: [],
    });
    expect(result.success).toBe(false);
  });

  it('rejects a missing client', () => {
    const result = contractSchema.safeParse({
      clientId: '',
      contractNumber: 'SRV-2026-001',
      startDate: '2026-01-01',
      siteIds: [],
    });
    expect(result.success).toBe(false);
  });

  it('rejects a missing contract number', () => {
    const result = contractSchema.safeParse({
      clientId: 'c1',
      contractNumber: '',
      startDate: '2026-01-01',
      siteIds: [],
    });
    expect(result.success).toBe(false);
  });

  it('rejects a missing start date', () => {
    const result = contractSchema.safeParse({
      clientId: 'c1',
      contractNumber: 'SRV-2026-001',
      startDate: '',
      siteIds: [],
    });
    expect(result.success).toBe(false);
  });
});
