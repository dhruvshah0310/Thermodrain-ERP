import { Router } from 'express';
import { db, withTransaction } from '../db/index.js';
import { nextDocNumber } from '../lib/docNumber.js';

export const indentsRouter = Router();

interface IndentItemInput {
  material_id: number;
  unit?: string;
  req_qty: number;
  remark?: string;
}
interface IndentInput {
  indent_date: string;
  department_id: number;
  narration?: string;
  status?: string;
  items: IndentItemInput[];
}

function loadIndent(id: number | bigint) {
  const header = db.prepare(`
    SELECT pi.*, d.name AS department_name
    FROM purchase_indents pi
    LEFT JOIN departments d ON d.id = pi.department_id
    WHERE pi.id = ?
  `).get(id);
  if (!header) return null;
  const items = db.prepare(`
    SELECT ii.*, m.code AS material_code, m.name AS material_name
    FROM purchase_indent_items ii
    LEFT JOIN materials m ON m.id = ii.material_id
    WHERE ii.indent_id = ?
    ORDER BY ii.sr_no
  `).all(id);
  return { ...(header as object), items };
}

indentsRouter.get('/', (req, res) => {
  const status = req.query.status as string | undefined;
  const rows = status
    ? db.prepare(`
        SELECT pi.*, d.name AS department_name,
          (SELECT COUNT(*) FROM purchase_indent_items WHERE indent_id = pi.id) AS item_count
        FROM purchase_indents pi LEFT JOIN departments d ON d.id = pi.department_id
        WHERE pi.status = ? ORDER BY pi.id DESC
      `).all(status)
    : db.prepare(`
        SELECT pi.*, d.name AS department_name,
          (SELECT COUNT(*) FROM purchase_indent_items WHERE indent_id = pi.id) AS item_count
        FROM purchase_indents pi LEFT JOIN departments d ON d.id = pi.department_id
        ORDER BY pi.id DESC
      `).all();
  res.json(rows);
});

indentsRouter.get('/next-number', (_req, res) => {
  res.json({ indent_no: nextDocNumber('purchase_indents', 'indent_no', 'IND') });
});

indentsRouter.get('/:id', (req, res) => {
  const indent = loadIndent(Number(req.params.id));
  if (!indent) {
    res.status(404).json({ error: 'Indent not found' });
    return;
  }
  res.json(indent);
});

indentsRouter.post('/', (req, res) => {
  const body = req.body as IndentInput;
  const result = withTransaction(() => {
    const indentNo = nextDocNumber('purchase_indents', 'indent_no', 'IND');
    const info = db.prepare(`
      INSERT INTO purchase_indents (indent_no, indent_date, department_id, narration, status)
      VALUES (?, ?, ?, ?, ?)
    `).run(indentNo, body.indent_date, body.department_id, body.narration ?? null, body.status ?? 'open');
    const indentId = info.lastInsertRowid;
    const insertItem = db.prepare(`
      INSERT INTO purchase_indent_items (indent_id, sr_no, material_id, unit, req_qty, remark)
      VALUES (?, ?, ?, ?, ?, ?)
    `);
    (body.items ?? []).forEach((item, i) => {
      insertItem.run(indentId, i + 1, item.material_id, item.unit ?? null, item.req_qty, item.remark ?? null);
    });
    return indentId;
  });
  res.status(201).json(loadIndent(result));
});

indentsRouter.put('/:id', (req, res) => {
  const id = Number(req.params.id);
  const body = req.body as IndentInput;
  withTransaction(() => {
    db.prepare(`
      UPDATE purchase_indents SET indent_date = ?, department_id = ?, narration = ?, status = ?
      WHERE id = ?
    `).run(body.indent_date, body.department_id, body.narration ?? null, body.status ?? 'open', id);
    db.prepare('DELETE FROM purchase_indent_items WHERE indent_id = ?').run(id);
    const insertItem = db.prepare(`
      INSERT INTO purchase_indent_items (indent_id, sr_no, material_id, unit, req_qty, remark)
      VALUES (?, ?, ?, ?, ?, ?)
    `);
    (body.items ?? []).forEach((item, i) => {
      insertItem.run(id, i + 1, item.material_id, item.unit ?? null, item.req_qty, item.remark ?? null);
    });
  });
  res.json(loadIndent(id));
});

indentsRouter.delete('/:id', (req, res) => {
  const info = db.prepare('DELETE FROM purchase_indents WHERE id = ?').run(req.params.id);
  if (info.changes === 0) {
    res.status(404).json({ error: 'Indent not found' });
    return;
  }
  res.status(204).end();
});
