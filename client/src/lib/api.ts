const BASE = '/api';

// Preview build (npm run build:preview) runs entirely client-side against an
// embedded data snapshot — no server. See client/src/preview/staticApi.ts.
// The dynamic import is guarded by a build-time-constant env var so Vite
// drops it (and the ~1MB embedded snapshot) entirely from the normal build.
const isPreview = import.meta.env.VITE_PREVIEW === 'true';

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  if (isPreview) {
    const { staticRequest } = await import('../preview/staticApi');
    const method = init?.method ?? 'GET';
    const body = init?.body ? JSON.parse(init.body as string) : undefined;
    return staticRequest<T>(method, path, body);
  }

  const res = await fetch(`${BASE}${path}`, {
    ...init,
    headers: { 'Content-Type': 'application/json', ...(init?.headers ?? {}) },
  });
  if (!res.ok) {
    let message = `${res.status} ${res.statusText}`;
    try {
      const body = await res.json();
      if (body?.error) message = body.error;
    } catch {
      // ignore — no JSON body
    }
    throw new Error(message);
  }
  if (res.status === 204) return undefined as T;
  return res.json() as Promise<T>;
}

export const api = {
  get: <T>(path: string) => request<T>(path),
  post: <T>(path: string, body: unknown) => request<T>(path, { method: 'POST', body: JSON.stringify(body) }),
  put: <T>(path: string, body: unknown) => request<T>(path, { method: 'PUT', body: JSON.stringify(body) }),
  del: (path: string) => request<void>(path, { method: 'DELETE' }),
};
