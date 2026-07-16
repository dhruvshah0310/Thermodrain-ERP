import { DatabaseSync } from 'node:sqlite';
import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { mkdirSync } from 'node:fs';

const __dirname = dirname(fileURLToPath(import.meta.url));

const dataDir = join(__dirname, '..', '..', 'data');
mkdirSync(dataDir, { recursive: true });

const dbPath = process.env.DB_PATH ?? join(dataDir, 'erp.db');

export const db = new DatabaseSync(dbPath);
db.exec('PRAGMA foreign_keys = ON;');
db.exec('PRAGMA journal_mode = WAL;');

const schema = readFileSync(join(__dirname, 'schema.sql'), 'utf-8');
db.exec(schema);

// On a fresh/ephemeral filesystem (e.g. a new deploy on a host without a
// persistent volume), auto-load the bundled seed dump so the app isn't
// empty on first request. seed-historical.sql is a plain data-only SQL
// dump (departments/units/vendors/materials + the imported Purchase Excel
// history) generated once via `sqlite3 erp.db .dump` and committed —
// regenerate it after re-running scripts/import_excel.py if the source
// data changes.
const seedDumpPath = join(dataDir, 'seed-historical.sql');
const departmentCount = (db.prepare('SELECT COUNT(*) AS n FROM departments').get() as { n: number }).n;
if (departmentCount === 0 && existsSync(seedDumpPath)) {
  try {
    // The dump's INSERT order (from Python's sqlite3.iterdump()) doesn't
    // respect FK dependency order, so relax enforcement for the bulk load.
    db.exec('PRAGMA foreign_keys = OFF;');
    db.exec(readFileSync(seedDumpPath, 'utf-8'));
    db.exec('PRAGMA foreign_keys = ON;');
    // eslint-disable-next-line no-console
    console.log('Loaded bundled seed data (departments/units/vendors/materials + Purchase history).');
  } catch (err) {
    db.exec('PRAGMA foreign_keys = ON;');
    // eslint-disable-next-line no-console
    console.error('Failed to load seed-historical.sql — starting with an empty database.', err);
  }
}

/** Runs `fn` in a transaction, rolling back if it throws. */
export function withTransaction<T>(fn: () => T): T {
  db.exec('BEGIN');
  try {
    const result = fn();
    db.exec('COMMIT');
    return result;
  } catch (err) {
    db.exec('ROLLBACK');
    throw err;
  }
}
