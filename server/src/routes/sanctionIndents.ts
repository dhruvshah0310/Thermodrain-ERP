import { Router } from 'express';
import { db, withTransaction } from '../db/index.js';
import { nextDocNumber } from '../lib/docNumber.js';

export const sanctionIndentsRouter = Router();

interface SanctionItemInput {
  material_id: number;
  hsn_no?: string;
  unit?: string;
  qty: number;
  remark?: string;
}
interface SanctionInput {
  doc_date: string;
  department_id: number;
  indent_id?: number | null;
  narration?: string;
  default_printing?: string;
  items: SanctionItemInput[];
}

function loadSanction(id: number | bigint) {
  const header = db.prepare(`
    SELECT si.*, d.name AS department_name, pi.indent_no
    FROM sanction_indents si
    LEFT JOIN departments d ON d.id = si.department_id
    LEFT JOIN purchase_indents pi ON pi.id = si.indent_id
    WHERE si.id = ?
  `).get(id);
  if (!header) return null;
  const items = db.prepare(`
    SELECT si.*, m.code AS material_code, m.name AS material_name
    FROM sanction_indent_items si
    LEFT JOIN materials m ON m.id = si.material_id
    WHERE si.sanction_id = ?
    ORDER BY si.sr_no
  `).all(id);
  const totalQty = (items as any[]).reduce((sum, it) => sum + Number(it.qty ?? 0), 0);
  return { ...(header as object), items, total_qty: totalQty };
}

sanctionIndentsRouter.get('/', (_req, res) => {
  const rows = db.prepare(`
    SELECT si.*, d.name AS department_name,
      (SELECT COUNT(*) FROM sanction_indent_items WHERE sanction_id = si.id) AS item_count
    FROM sanction_indents si LEFT JOIN departments d ON d.id = si.department_id
    ORDER BY si.id DESC
  `).all();
  res.json(rows);
});

sanctionIndentsRouter.get('/next-number', (_req, res) => {
  res.json({ doc_no: nextDocNumber('sanction_indents', 'doc_no', 'SI') });
});

sanctionIndentsRouter.get('/:id', (req, res) => {
  const row = loadSanction(Number(req.params.id));
  if (!row) {
    res.status(404).json({ error: 'Sanction indent not found' });
    return;
  }
  res.json(row);
});

sanctionIndentsRouter.post('/', (req, res) => {
  const body = req.body as SanctionInput;
  const result = withTransaction(() => {
    const docNo = nextDocNumber('sanction_indents', 'doc_no', 'SI');
    const info = db.prepare(`
      INSERT INTO sanction_indents (doc_no, doc_date, department_id, indent_id, narration, default_printing)
      VALUES (?, ?, ?, ?, ?, ?)
    `).run(docNo, body.doc_date, body.department_id, body.indent_id ?? null, body.narration ?? null, body.default_printing ?? 'Sanction Indent');
    const sanctionId = info.lastInsertRowid;
    const insertItem = db.prepare(`
      INSERT INTO sanction_indent_items (sanction_id, sr_no, material_id, hsn_no, unit, qty, remark)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    `);
    (body.items ?? []).forEach((item, i) => {
      insertItem.run(sanctionId, i + 1, item.material_id, item.hsn_no ?? null, item.unit ?? null, item.qty, item.remark ?? null);
    });
    if (body.indent_id) {
      db.prepare("UPDATE purchase_indents SET status = 'sanctioned' WHERE id = ?").run(body.indent_id);
    }
    return sanctionId;
  });
  res.status(201).json(loadSanction(result));
});

sanctionIndentsRouter.put('/:id', (req, res) => {
  const id = Number(req.params.id);
  const body = req.body as SanctionInput;
  withTransaction(() => {
    db.prepare(`
      UPDATE sanction_indents SET doc_date = ?, department_id = ?, indent_id = ?, narration = ?, default_printing = ?
      WHERE id = ?
    `).run(body.doc_date, body.department_id, body.indent_id ?? null, body.narration ?? null, body.default_printing ?? 'Sanction Indent', id);
    db.prepare('DELETE FROM sanction_indent_items WHERE sanction_id = ?').run(id);
    const insertItem = db.prepare(`
      INSERT INTO sanction_indent_items (sanction_id, sr_no, material_id, hsn_no, unit, qty, remark)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    `);
    (body.items ?? []).forEach((item, i) => {
      insertItem.run(id, i + 1, item.material_id, item.hsn_no ?? null, item.unit ?? null, item.qty, item.remark ?? null);
    });
  });
  res.json(loadSanction(id));
});

sanctionIndentsRouter.delete('/:id', (req, res) => {
  const info = db.prepare('DELETE FROM sanction_indents WHERE id = ?').run(req.params.id);
  if (info.changes === 0) {
    res.status(404).json({ error: 'Sanction indent not found' });
    return;
  }
  res.status(204).end();
});
