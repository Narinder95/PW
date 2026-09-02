// Tiny method + path-pattern router. Patterns use :name for params, e.g.
//   router.get('/api/habits/:id/log', handler)
// Static segments beat param segments, so '/api/notifications/unread-count'
// wins over '/api/notifications/:id' regardless of registration order.

function compile(pattern) {
  const segments = pattern.split('/').filter((s) => s.length > 0);
  const paramCount = segments.filter((s) => s.startsWith(':')).length;
  return { segments, paramCount };
}

export class Router {
  constructor() {
    this.routes = [];
  }

  /**
   * @param {object} [opts]
   * @param {boolean} [opts.auth]   require a valid bearer token (default false)
   * @param {boolean} [opts.raw]    handler manages the response itself (SSE)
   */
  add(method, pattern, handler, opts = {}) {
    const { segments, paramCount } = compile(pattern);
    this.routes.push({
      method: method.toUpperCase(),
      pattern,
      segments,
      paramCount,
      handler,
      auth: opts.auth === true,
      raw: opts.raw === true,
    });
    return this;
  }

  get(p, h, o) { return this.add('GET', p, h, o); }
  post(p, h, o) { return this.add('POST', p, h, o); }
  patch(p, h, o) { return this.add('PATCH', p, h, o); }
  put(p, h, o) { return this.add('PUT', p, h, o); }
  delete(p, h, o) { return this.add('DELETE', p, h, o); }

  /**
   * @returns {{handler: Function, params: Object}|null} best match, or null.
   *          `null` with a non-empty `allowed` set means the path exists under
   *          another method.
   */
  match(method, pathname) {
    const parts = pathname.split('/').filter((s) => s.length > 0);
    let best = null;
    const allowed = new Set();

    for (const route of this.routes) {
      if (route.segments.length !== parts.length) continue;
      const params = {};
      let ok = true;
      for (let i = 0; i < parts.length; i++) {
        const seg = route.segments[i];
        if (seg.startsWith(':')) {
          params[seg.slice(1)] = decodeURIComponent(parts[i]);
        } else if (seg !== parts[i]) {
          ok = false;
          break;
        }
      }
      if (!ok) continue;
      allowed.add(route.method);
      if (route.method !== method.toUpperCase()) continue;
      if (best === null || route.paramCount < best.route.paramCount) {
        best = { route, params };
      }
    }

    if (best) return { route: best.route, handler: best.route.handler, params: best.params, allowed };
    return { route: null, handler: null, params: {}, allowed };
  }
}
