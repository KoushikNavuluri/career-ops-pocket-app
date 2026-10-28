/**
 * A tiny JSON-Schema subset used for (1) OpenAI structured outputs in strict mode and
 * (2) validating model output before anything is persisted. Dependency-free on purpose.
 */
export type Schema =
  | { type: 'string'; enum?: readonly string[]; description?: string }
  | { type: 'number'; description?: string }
  | { type: 'integer'; description?: string }
  | { type: 'boolean'; description?: string }
  | { type: 'array'; items: Schema; description?: string }
  | {
      type: 'object';
      properties: Record<string, Schema>;
      required: string[];
      additionalProperties: false;
      description?: string;
    };

export const str = (description?: string): Schema => ({ type: 'string', ...(description ? { description } : {}) });
export const num = (description?: string): Schema => ({ type: 'number', ...(description ? { description } : {}) });
export const oneOf = (values: readonly string[], description?: string): Schema => ({
  type: 'string',
  enum: values,
  ...(description ? { description } : {}),
});
export const list = (items: Schema, description?: string): Schema => ({
  type: 'array',
  items,
  ...(description ? { description } : {}),
});
/** Strict-mode object: every property required, no extras. */
export const obj = (properties: Record<string, Schema>, description?: string): Schema => ({
  type: 'object',
  properties,
  required: Object.keys(properties),
  additionalProperties: false,
  ...(description ? { description } : {}),
});

export type ValidationResult = { ok: true } | { ok: false; errors: string[] };

export function validate(schema: Schema, value: unknown, path = '$', errors: string[] = []): ValidationResult {
  switch (schema.type) {
    case 'string':
      if (typeof value !== 'string') errors.push(`${path}: expected string`);
      else if (schema.enum && !schema.enum.includes(value)) errors.push(`${path}: "${value}" not in [${schema.enum.join(', ')}]`);
      break;
    case 'number':
      if (typeof value !== 'number' || !Number.isFinite(value)) errors.push(`${path}: expected number`);
      break;
    case 'integer':
      if (typeof value !== 'number' || !Number.isInteger(value)) errors.push(`${path}: expected integer`);
      break;
    case 'boolean':
      if (typeof value !== 'boolean') errors.push(`${path}: expected boolean`);
      break;
    case 'array':
      if (!Array.isArray(value)) errors.push(`${path}: expected array`);
      else value.forEach((item, i) => validate(schema.items, item, `${path}[${i}]`, errors));
      break;
    case 'object': {
      if (typeof value !== 'object' || value === null || Array.isArray(value)) {
        errors.push(`${path}: expected object`);
        break;
      }
      const record = value as Record<string, unknown>;
      for (const key of schema.required) {
        if (!(key in record)) errors.push(`${path}.${key}: missing`);
      }
      for (const key of Object.keys(record)) {
        const child = schema.properties[key];
        if (!child) errors.push(`${path}.${key}: unexpected property`);
        else validate(child, record[key], `${path}.${key}`, errors);
      }
      break;
    }
  }
  return errors.length === 0 ? { ok: true } : { ok: false, errors };
}

/** Strip optional markdown fences and parse JSON. Returns undefined on failure. */
export function parseJsonLoose(text: string): unknown {
  const trimmed = text.trim().replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/, '');
  try {
    return JSON.parse(trimmed);
  } catch {
    return undefined;
  }
}
