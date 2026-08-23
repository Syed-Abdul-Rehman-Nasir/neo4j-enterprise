import { z } from 'zod';

const errorSchema = z.object({
  detail: z.union([z.string(), z.record(z.string(), z.unknown()), z.array(z.unknown())]).optional(),
  message: z.string().optional()
});

export class ApiClientError extends Error {
  constructor(public status: number, message: string, public details?: unknown) {
    super(message);
    this.name = 'ApiClientError';
  }
}

const baseUrl = (import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:8000/api/v1').replace(/\/$/, '');

async function parseError(response: Response): Promise<ApiClientError> {
  const text = await response.text();
  if (!text) return new ApiClientError(response.status, response.statusText || 'Request failed');
  try {
    const parsed = errorSchema.safeParse(JSON.parse(text));
    if (parsed.success) {
      const detail = parsed.data.detail;
      return new ApiClientError(response.status, parsed.data.message ?? (typeof detail === 'string' ? detail : response.statusText), detail);
    }
  } catch {
    return new ApiClientError(response.status, text);
  }
  return new ApiClientError(response.status, response.statusText || 'Request failed');
}

export async function apiFetch<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${baseUrl}${path}`, {
    headers: { 'Content-Type': 'application/json', ...(init?.headers ?? {}) },
    ...init
  });
  if (!response.ok) throw await parseError(response);
  if (response.status === 204) return undefined as T;
  return (await response.json()) as T;
}

export function withQuery(path: string, params: Record<string, string | number | undefined | null>) {
  // Keep the result relative to baseUrl: apiFetch() adds the API prefix.
  // Building from baseUrl here returned `/api/v1/...` and duplicated the
  // prefix for every endpoint that had query parameters.
  const url = new URL(path, 'http://operations-console.local');
  Object.entries(params).forEach(([key, value]) => {
    if (value !== undefined && value !== null && value !== '') url.searchParams.set(key, String(value));
  });
  return `${url.pathname}${url.search}`;
}
