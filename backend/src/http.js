// HTTP primitives: the error envelope, body parsing with a size cap, send helpers.
import crypto from 'node:crypto';

export const MAX_BODY_BYTES = 256 * 1024; // 256 KiB is plenty for this API.

/** Every non-2xx response in the API is produced from one of these. */
export class ApiError extends Error {
  constructor(status, code, message, extra = {}) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
    this.code = code;
    this.extra = extra;
  }

  toEnvelope() {
    return { error: { code: this.code, message: this.message, ...this.extra } };
  }

  static validation(message, field) {
    return new ApiError(400, 'validation_error', message, field ? { field } : {});
  }
  static unauthorized(message = 'Missing or invalid token') {
    return new ApiError(401, 'unauthorized', message);
  }
  static forbidden(message = 'You are not allowed to do that') {
    return new ApiError(403, 'forbidden', message);
  }
  static notFound(message = 'Not found') {
    return new ApiError(404, 'not_found', message);
  }
  static conflict(message = 'Conflict') {
    return new ApiError(409, 'conflict', message);
  }
  static rateLimited(message, retryAfterSeconds) {
    return new ApiError(429, 'rate_limited', message, { retryAfterSeconds });
  }
  static internal(message = 'Internal server error') {
    return new ApiError(500, 'internal', message);
  }
}

export const CORS_HEADERS = {
  // Dev-only: permissive so a Flutter web/desktop build can hit the API directly.
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PATCH, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Authorization, Content-Type, Accept, Last-Event-ID',
  'Access-Control-Expose-Headers': 'Content-Type',
  'Access-Control-Max-Age': '86400',
};

export function applyCors(res) {
  for (const [k, v] of Object.entries(CORS_HEADERS)) res.setHeader(k, v);
}

export function sendJson(res, status, body, headers = {}) {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(payload),
    'Cache-Control': 'no-store',
    ...headers,
  });
  res.end(payload);
}

export function sendNoContent(res) {
  res.writeHead(204, { 'Cache-Control': 'no-store' });
  res.end();
}

export function sendError(res, err) {
  const status = err.status ?? 500;
  const headers = {};
  if (status === 429 && typeof err.extra?.retryAfterSeconds === 'number') {
    headers['Retry-After'] = String(err.extra.retryAfterSeconds);
  }
  sendJson(res, status, err.toEnvelope(), headers);
}

/** Read + parse a JSON body. Empty body -> {}. Oversized -> 400. Malformed -> 400. */
export function readJson(req, cap = MAX_BODY_BYTES) {
  return new Promise((resolve, reject) => {
    if (req.method === 'GET' || req.method === 'HEAD') return resolve({});
    const chunks = [];
    let size = 0;
    let settled = false;
    const fail = (err) => {
      if (settled) return;
      settled = true;
      req.removeAllListeners('data');
      reject(err);
    };
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > cap) {
        fail(ApiError.validation(`Request body too large (max ${cap} bytes)`));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on('error', () => fail(ApiError.validation('Could not read request body')));
    req.on('end', () => {
      if (settled) return;
      settled = true;
      const raw = Buffer.concat(chunks).toString('utf8').trim();
      if (!raw) return resolve({});
      try {
        const parsed = JSON.parse(raw);
        if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
          return reject(ApiError.validation('Request body must be a JSON object'));
        }
        resolve(parsed);
      } catch {
        reject(ApiError.validation('Request body must be valid JSON'));
      }
    });
  });
}

// ---------------------------------------------------------------- validation

export function requireString(obj, field, { min = 1, max = 500, trim = true } = {}) {
  let v = obj?.[field];
  if (typeof v !== 'string') throw ApiError.validation(`${field} is required`, field);
  if (trim) v = v.trim();
  if (v.length < min) throw ApiError.validation(`${field} must be at least ${min} characters`, field);
  if (v.length > max) throw ApiError.validation(`${field} must be at most ${max} characters`, field);
  return v;
}

export function optionalString(obj, field, { max = 500, trim = true } = {}) {
  const v = obj?.[field];
  if (v === undefined || v === null) return null;
  if (typeof v !== 'string') throw ApiError.validation(`${field} must be a string`, field);
  const out = trim ? v.trim() : v;
  if (out.length > max) throw ApiError.validation(`${field} must be at most ${max} characters`, field);
  return out;
}

export function requireInt(obj, field, { min = -Infinity, max = Infinity } = {}) {
  const v = obj?.[field];
  if (typeof v !== 'number' || !Number.isInteger(v)) {
    throw ApiError.validation(`${field} must be an integer`, field);
  }
  if (v < min) throw ApiError.validation(`${field} must be >= ${min}`, field);
  if (v > max) throw ApiError.validation(`${field} must be <= ${max}`, field);
  return v;
}

const HEX_COLOR = /^#[0-9a-fA-F]{6}$/;
export function normalizeColor(value, field = 'color') {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'string' || !HEX_COLOR.test(value.trim())) {
    throw ApiError.validation(`${field} must be a #RRGGBB hex string`, field);
  }
  return value.trim().toUpperCase();
}

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
export function parseDate(value, field = 'date') {
  if (value === undefined || value === null || value === '') return null;
  if (typeof value !== 'string' || !DATE_RE.test(value)) {
    throw ApiError.validation(`${field} must be YYYY-MM-DD`, field);
  }
  const d = new Date(`${value}T00:00:00.000Z`);
  if (Number.isNaN(d.getTime()) || d.toISOString().slice(0, 10) !== value) {
    throw ApiError.validation(`${field} is not a real date`, field);
  }
  return value;
}

/** limit query param: clamps into [1, max], falls back to `def`. */
export function parseLimit(raw, def, max) {
  if (raw === undefined || raw === null || raw === '') return def;
  const n = Number(raw);
  if (!Number.isFinite(n)) return def;
  return Math.max(1, Math.min(max, Math.floor(n)));
}

export function parseBool(raw) {
  if (raw === undefined || raw === null || raw === '') return false;
  return raw === 'true' || raw === '1' || raw === 'yes';
}

// ---------------------------------------------------------------- misc utils

export function newId(prefix) {
  return `${prefix}_${crypto.randomBytes(8).toString('hex')}`;
}

export function nowISO() {
  return new Date().toISOString();
}
