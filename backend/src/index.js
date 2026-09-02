// Entrypoint: open the file-backed DB and listen.
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { openDb } from './db.js';
import { createServer, API_VERSION } from './server.js';

const here = path.dirname(fileURLToPath(import.meta.url));
export const DEFAULT_DB_PATH = path.resolve(here, '..', 'data', 'pw.db');

const dbPath = process.env.PW_DB_PATH ? path.resolve(process.env.PW_DB_PATH) : DEFAULT_DB_PATH;
const port = Number(process.env.PORT ?? 8080);
const host = process.env.HOST ?? '0.0.0.0'; // 0.0.0.0 so 10.0.2.2 works from the Android emulator

const db = openDb(dbPath);
const server = createServer(db);

server.listen(port, host, () => {
  const { port: actual } = server.address();
  console.log(`PW API v${API_VERSION} listening on http://${host}:${actual}`);
  console.log(`  db            ${dbPath}`);
  console.log(`  push provider ${server.provider.name}`);
  console.log(`  emulator      http://10.0.2.2:${actual}`);
});

function shutdown(signal) {
  console.log(`\n${signal} received, shutting down.`);
  server.close(() => {
    try {
      db.close();
    } catch {
      /* already closed */
    }
    process.exit(0);
  });
  // Do not wait forever on held-open SSE sockets.
  const t = setTimeout(() => process.exit(0), 3000);
  if (typeof t.unref === 'function') t.unref();
}

process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
