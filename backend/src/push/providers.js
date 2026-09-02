// Push providers. Every provider implements the same interface:
//
//   name: string
//   async send(payload) -> { status, error? }
//     status: 'sent' | 'skipped' | 'failed' | 'invalid_token'
//
// A provider never throws for an expected delivery failure - it returns a
// status. (The dispatcher also defends against providers that DO throw.)

/** Default. Records the attempt without sending, so the whole path stays testable. */
export class NoneProvider {
  constructor() {
    this.name = 'none';
  }
  async send() {
    return { status: 'skipped' };
  }
}

/** Prints the fully rendered payload. Used by local dev + `PUSH_PROVIDER=log`. */
export class LogProvider {
  constructor(logger = console) {
    this.name = 'log';
    this.logger = logger;
  }
  async send(payload) {
    this.logger.log(`[push:log] ${JSON.stringify(payload)}`);
    return { status: 'sent' };
  }
}

/**
 * In-process capture for node:test.
 *   provider.sent            - every payload handed to send()
 *   provider.failTimes = 2   - fail the next 2 calls, then succeed
 *   provider.nextStatus      - force one specific result
 *   provider.throwTimes = 1  - throw (not return) on the next call
 */
export class MemoryProvider {
  constructor() {
    this.name = 'memory';
    this.sent = [];
    this.calls = 0;
    this.failTimes = 0;
    this.throwTimes = 0;
    this.nextStatus = null;
    this.tokenStatus = new Map(); // deviceToken -> forced status
  }

  reset() {
    this.sent = [];
    this.calls = 0;
    this.failTimes = 0;
    this.throwTimes = 0;
    this.nextStatus = null;
    this.tokenStatus.clear();
  }

  async send(payload) {
    this.calls += 1;
    this.sent.push(payload);
    if (this.throwTimes > 0) {
      this.throwTimes -= 1;
      throw new Error('memory provider: simulated crash');
    }
    const forced = this.tokenStatus.get(payload.deviceToken);
    if (forced) return { status: forced, error: forced === 'invalid_token' ? 'UNREGISTERED' : 'forced' };
    if (this.failTimes > 0) {
      this.failTimes -= 1;
      return { status: 'failed', error: 'memory provider: simulated failure' };
    }
    if (this.nextStatus) {
      const s = this.nextStatus;
      this.nextStatus = null;
      return { status: s, error: s === 'sent' ? undefined : s };
    }
    return { status: 'sent' };
  }
}
