import { db, withTransaction } from './index.js';

const DEPARTMENTS = [
  { name: 'STORE', code: 'STOR' },
  { name: 'MAINTAINANCE', code: 'MAIN' },
  { name: 'DESIGN', code: 'DESN' },
  { name: 'CANTEEN', code: 'CANT' },
  { name: 'PRODUCTION', code: 'PROD' },
];

const UNITS: { name: string; conversion_factor?: number; notes?: string }[] = [
  { name: 'NOS' },
  { name: 'KGS' },
  { name: 'MTR' },
  { name: 'LTR' },
  { name: 'PKT' },
  { name: 'SQFT' },
  { name: 'LUMSUM' },
  { name: 'ROLL' },
  { name: 'BOTTLE' },
  { name: 'PAIR' },
  { name: 'BRASS' },
  { name: 'SQMT' },
  { name: 'BAG' },
  { name: 'BOX' },
  { name: 'FEET' },
  { name: 'DOZEN', conversion_factor: 12, notes: '12 for Dozen' },
  { name: 'SHEET' },
  { name: 'SET' },
];

withTransaction(() => {
  const insertDept = db.prepare('INSERT OR IGNORE INTO departments (name, code) VALUES (?, ?)');
  DEPARTMENTS.forEach((d) => insertDept.run(d.name, d.code));

  const insertUnit = db.prepare('INSERT OR IGNORE INTO units (name, conversion_factor, notes) VALUES (?, ?, ?)');
  UNITS.forEach((u) => insertUnit.run(u.name, u.conversion_factor ?? 1, u.notes ?? null));
});

// eslint-disable-next-line no-console
console.log('Seeded base departments and units.');
