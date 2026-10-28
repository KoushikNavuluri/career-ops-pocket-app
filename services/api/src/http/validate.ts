import { z } from 'zod';
import { badRequest, notFound } from './errors.ts';

export function parseWith<S extends z.ZodTypeAny>(schema: S, data: unknown): z.infer<S> {
  const r = schema.safeParse(data ?? {});
  if (!r.success) {
    const fields: Record<string, string> = {};
    for (const issue of r.error.issues) {
      const key = issue.path.join('.') || '_';
      if (!fields[key]) fields[key] = issue.message;
    }
    throw badRequest('Some fields need attention.', fields);
  }
  return r.data;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function uuidParam(params: unknown, key = 'id', what = 'Item'): string {
  const value = (params as Record<string, unknown> | null)?.[key];
  if (typeof value !== 'string' || !UUID.test(value)) throw notFound(what);
  return value;
}

export const trimmed = (max: number) => z.string().trim().max(max);
export const optionalText = (max: number) =>
  z
    .string()
    .trim()
    .max(max)
    .nullable()
    .optional()
    .transform((v) => (v === '' ? null : v));
