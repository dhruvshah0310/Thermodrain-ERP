import { Router } from 'express';
import { db } from '../db/index.js';

export interface CrudOptions {
  table: string;
  /** Columns accepted on create/update, in addition to `id`. */
  columns: string[];
  /** Default ORDER BY clause (without the "ORDER BY" keywords). */
  orderBy?: string;
  /** Optional column to search against with `?q=` (simple LIKE). */
  searchColumn?: string;
}

/** Minimal REST CRUD router for a single-table master (departments, units, accounts, materials). */
export function crudRouter(opts: CrudOptions): Router {
  const router = Router();
  const order = opts.orderBy ?? 'id DESC';

  router.get('/', (req, res) => {
    const q = req.query.q as string | undefined;
    if (q && opts.searchColumn) {
      const rows = db
        .prepare(`SELECT * FROM ${opts.table} WHERE ${opts.searchColumn} LIKE ? ORDER BY ${order}`)
        .all(`%${q}%`);
      res.json(rows);
      return;
    }
    const rows = db.prepare(`SELECT * FROM ${opts.table} ORDER BY ${order}`).all();
    res.json(rows);
  });

  router.get('/:id', (req, res) => {
    const row = db.prepare(`SELECT * FROM ${opts.table} WHERE id = ?`).get(req.params.id);
    if (!row) {
      res.status(404).json({ error: `${opts.table} ${req.params.id} not found` });
      return;
    }
    res.json(row);
  });

  router.post('/', (req, res) => {
    const cols = opts.columns.filter((c) => c in req.body);
    const placeholders = cols.map(() => '?').join(', ');
    const values = cols.map((c) => req.body[c]);
    const info = db
      .prepare(`INSERT INTO ${opts.table} (${cols.join(', ')}) VALUES (${placeholders})`)
      .run(...values);
    const row = db.prepare(`SELECT * FROM ${opts.table} WHERE id = ?`).get(info.lastInsertRowid);
    res.status(201).json(row);
  });

  router.put('/:id', (req, res) => {
    const cols = opts.columns.filter((c) => c in req.body);
    if (cols.length === 0) {
      res.status(400).json({ error: 'No updatable fields provided' });
      return;
    }
    const setClause = cols.map((c) => `${c} = ?`).join(', ');
    const values = cols.map((c) => req.body[c]);
    db.prepare(`UPDATE ${opts.table} SET ${setClause} WHERE id = ?`).run(...values, req.params.id);
    const row = db.prepare(`SELECT * FROM ${opts.table} WHERE id = ?`).get(req.params.id);
    if (!row) {
      res.status(404).json({ error: `${opts.table} ${req.params.id} not found` });
      return;
    }
    res.json(row);
  });

  router.delete('/:id', (req, res) => {
    const info = db.prepare(`DELETE FROM ${opts.table} WHERE id = ?`).run(req.params.id);
    if (info.changes === 0) {
      res.status(404).json({ error: `${opts.table} ${req.params.id} not found` });
      return;
    }
    res.status(204).end();
  });

  return router;
}
