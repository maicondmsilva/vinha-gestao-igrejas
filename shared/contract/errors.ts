// One error shape for the panel, the ministry apps and Vinha Equipe.
// `error` is always a sentence a person can act on; `fields` points at the inputs to fix.
import type {z} from 'zod';

export type ApiErrorBody = {error: string; fields?: Record<string, string>; code?: string};

/** Dotted path of a validation issue: `items.0.cpf`, `title`. */
export const issuePath = (path: readonly PropertyKey[]) => path.map(String).join('.');

/** First message per field, in the order the form shows them. */
export function fieldErrors(error: z.ZodError): Record<string, string> {
  const out: Record<string, string> = {};
  for (const i of error.issues) {
    const key = issuePath(i.path) || '_';
    if (!out[key]) out[key] = i.message;
  }
  return out;
}

/** Response body for a refused form: a summary plus the fields to fix. */
export function validationBody(error: z.ZodError, summary = 'Revise os campos destacados.'): ApiErrorBody {
  const fields = fieldErrors(error);
  const first = Object.entries(fields).find(([k]) => k !== '_');
  return {error: first ? first[1] : fields._ || summary, fields, code: 'validation'};
}

/** Reads an API error body defensively (old servers answer only `error`). */
export function readApiError(v: unknown, fallback = 'Não foi possível concluir agora.'): ApiErrorBody {
  if (!v || typeof v !== 'object') return {error: fallback};
  const o = v as Record<string, unknown>;
  const fields =
    o.fields && typeof o.fields === 'object' && !Array.isArray(o.fields)
      ? Object.fromEntries(Object.entries(o.fields as Record<string, unknown>).filter((e): e is [string, string] => typeof e[1] === 'string'))
      : undefined;
  return {
    error: typeof o.error === 'string' && o.error ? o.error : fallback,
    ...(fields && Object.keys(fields).length ? {fields} : {}),
    ...(typeof o.code === 'string' ? {code: o.code} : {}),
  };
}

/** Error thrown by API clients so screens can mark the right input. */
export class ApiError extends Error {
  fields: Record<string, string>;
  status: number;
  code?: string;
  constructor(body: ApiErrorBody, status = 400) {
    super(body.error);
    this.name = 'ApiError';
    this.fields = body.fields || {};
    this.status = status;
    this.code = body.code;
  }
}
