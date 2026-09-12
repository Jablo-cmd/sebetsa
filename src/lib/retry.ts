/**
 * Retries a network-bound action on transient failures only (fetch-level
 * network errors — no response reached at all), never on a real business
 * error the server returned (permission denied, validation failure,
 * conflict, etc. — retrying those would just repeat the same rejection,
 * or worse, risk a duplicate side effect on a non-idempotent call). Used
 * for the field-critical actions most likely to hit a flaky connection:
 * clock in/out, task completion, leave submission.
 *
 * Not an offline queue — this resolves in seconds against a live network,
 * never persists a pending action, and gives up (rejecting with the last
 * error) once out of attempts. Sebetsa does not claim offline support.
 */
export async function retryOnNetworkError<T>(action: () => Promise<T>, attempts = 3, baseDelayMs = 500): Promise<T> {
  let lastError: unknown;
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    try {
      return await action();
    } catch (error) {
      lastError = error;
      if (!isTransientNetworkError(error) || attempt === attempts - 1) {
        throw error;
      }
      await new Promise((resolve) => setTimeout(resolve, baseDelayMs * 2 ** attempt));
    }
  }
  throw lastError;
}

function isTransientNetworkError(error: unknown): boolean {
  // supabase-js/fetch surfaces a plain TypeError('Failed to fetch') (or
  // similar) when the request never reached the network at all — that's
  // the only case worth retrying. Anything with a Postgres/PostgREST error
  // shape (code/message from the server) already got a real answer.
  if (error instanceof TypeError) return true;
  if (typeof error === 'object' && error !== null && 'message' in error) {
    const message = String((error as { message: unknown }).message).toLowerCase();
    return message.includes('failed to fetch') || message.includes('network') || message.includes('load failed');
  }
  return false;
}
