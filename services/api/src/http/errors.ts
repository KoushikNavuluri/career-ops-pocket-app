/** RFC 9457 problem details with stable codes the app maps to friendly copy. */
export type Problem = {
  type: string;
  title: string;
  status: number;
  code: string;
  detail?: string;
  errors?: Record<string, string>;
  [extra: string]: unknown;
};

export class AppError extends Error {
  readonly status: number;
  readonly code: string;
  readonly fields?: Record<string, string>;
  readonly extra?: Record<string, unknown>;
  constructor(status: number, code: string, message: string, opts: { fields?: Record<string, string>; extra?: Record<string, unknown> } = {}) {
    super(message);
    this.status = status;
    this.code = code;
    this.fields = opts.fields;
    this.extra = opts.extra;
  }
}

export const badRequest = (message: string, fields?: Record<string, string>) => new AppError(400, 'validation_failed', message, { fields });
export const unauthorized = (message = 'Sign in to continue.') => new AppError(401, 'unauthorized', message);
export const forbidden = (message = 'You do not have access to this.') => new AppError(403, 'forbidden', message);
export const notFound = (what = 'Item') => new AppError(404, 'not_found', `${what} not found.`);
export const conflict = (code: string, message: string, extra?: Record<string, unknown>) => new AppError(409, code, message, { extra });

const TITLES: Record<number, string> = {
  400: 'Bad request',
  401: 'Unauthorized',
  403: 'Forbidden',
  404: 'Not found',
  409: 'Conflict',
  413: 'Payload too large',
  422: 'Unprocessable',
  429: 'Too many requests',
  500: 'Internal error',
  502: 'Upstream error',
  503: 'Service unavailable',
};

export function toProblem(err: unknown): Problem {
  if (err instanceof AppError) {
    return {
      type: `https://errors.careerpocket.app/${err.code}`,
      title: TITLES[err.status] ?? 'Error',
      status: err.status,
      code: err.code,
      detail: err.message,
      ...(err.fields ? { errors: err.fields } : {}),
      ...(err.extra ?? {}),
    };
  }
  const anyErr = err as { statusCode?: number; code?: string; validation?: unknown } | null;
  if (anyErr && typeof anyErr.statusCode === 'number' && anyErr.statusCode >= 400 && anyErr.statusCode < 500) {
    const status = anyErr.statusCode;
    const code = status === 413 ? 'payload_too_large' : status === 415 ? 'unsupported_media_type' : 'bad_request';
    return { type: `https://errors.careerpocket.app/${code}`, title: TITLES[status] ?? 'Bad request', status, code, detail: 'The request could not be processed.' };
  }
  return {
    type: 'https://errors.careerpocket.app/internal_error',
    title: 'Internal error',
    status: 500,
    code: 'internal_error',
    detail: 'Something went wrong on our side. Please try again.',
  };
}
