import { describe, expect, it, vi } from 'vitest';
import { retryOnNetworkError } from '@/lib/retry';

describe('retryOnNetworkError', () => {
  it('returns the result on first success without retrying', async () => {
    const action = vi.fn().mockResolvedValue('ok');
    const result = await retryOnNetworkError(action, 3, 1);
    expect(result).toBe('ok');
    expect(action).toHaveBeenCalledTimes(1);
  });

  it('retries a transient network error and eventually succeeds', async () => {
    const action = vi
      .fn()
      .mockRejectedValueOnce(new TypeError('Failed to fetch'))
      .mockResolvedValueOnce('ok');
    const result = await retryOnNetworkError(action, 3, 1);
    expect(result).toBe('ok');
    expect(action).toHaveBeenCalledTimes(2);
  });

  it('gives up after the configured number of attempts', async () => {
    const action = vi.fn().mockRejectedValue(new TypeError('Failed to fetch'));
    await expect(retryOnNetworkError(action, 2, 1)).rejects.toThrow('Failed to fetch');
    expect(action).toHaveBeenCalledTimes(2);
  });

  it('never retries a real server/business error', async () => {
    const serverError = { message: 'insufficient_privilege: cannot clock in this employee', code: 'P0001' };
    const action = vi.fn().mockRejectedValue(serverError);
    await expect(retryOnNetworkError(action, 3, 1)).rejects.toBe(serverError);
    expect(action).toHaveBeenCalledTimes(1);
  });
});
