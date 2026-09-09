// Entrypoint: open the Postgres-backed DB and listen.
import { openDb } from './db.js';
import { createServer, API_VERSION } from './server.js';

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) {
  console.error('DATABASE_URL is not set. See backend/.env (gitignored) for local development.');
  process.exit(1);
}

const port = Number(process.env.PORT ?? 8080);
const host = process.env.HOST ?? '0.0.0.0'; // 0.0.0.0 so 10.0.2.2 works from the Android emulator

const db = await openDb(databaseUrl);
const server = createServer(db);

server.listen(port, host, () => {
  const { port: actual } = server.address();
  console.log(`PW API v${API_VERSION} listening on http://${host}:${actual}`);
  console.log(`  db            Postgres (${new URL(databaseUrl).host})`);
  console.log(`  push provider ${server.provider.name}`);
  console.log(`  emulator      http://10.0.2.2:${actual}`);
});

function shutdown(signal) {
  console.log(`\n${signal} received, shutting down.`);
  server.close(async () => {
    try {
      await db.close();
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
