import { Router } from 'express';
import { db, withTransaction } from '../db/index.js';
import { nextDocNumber } from '../lib/docNumber.js';

export const rfqsRouter = Router();

interface RfqItemInput {
  material_id: number;
  unit?: string;
  qty: number;
}
interface RfqInput {
  doc_date: string;
  department_id: number;
  sanction_id?: number | null;
  narration?: string;
  vendor_ids: number[];
  items: RfqItemInput[];
}

function loadRfq(id: number | bigint) {
  const header = db.prepare(`
    SELECT r.*, d.name AS department_name, si.doc_no AS sanction_doc_no
    FROM rfqs r
    LEFT JOIN departments d ON d.id = r.department_id
    LEFT JOIN sanction_indents si ON si.id = r.sanction_id
    WHERE r.id = ?
  `).get(id);
  if (!header) return null;
  const items = db.prepare(`
    SELECT ri.*, m.code AS material_code, m.name AS material_name
    FROM rfq_items ri LEFT JOIN materials m ON m.id = ri.material_id
    WHERE ri.rfq_id = ? ORDER BY ri.sr_no
  `).all(id);
  const vendors = db.prepare(`
    SELECT a.id, a.name FROM rfq_vendors rv JOIN accounts a ON a.id = rv.account_id WHERE rv.rfq_id = ?
  `).all(id);
  const quotationsReceived = db.prepare(`
    SELECT COUNT(*) AS n FROM purchase_quotations WHERE rfq_id = ?
  `).get(id) as { n: number };
  return { ...(header as object), items, vendors, quotations_received: quotationsReceived.n };
}

rfqsRouter.get('/', (_req, res) => {
  const rows = db.prepare(`
    SELECT r.*, d.name AS department_name,
      (SELECT COUNT(*) FROM rfq_vendors WHERE rfq_id = r.id) AS vendor_count,
      (SELECT COUNT(*) FROM purchase_quotations WHERE rfq_id = r.id) AS quotations_received
    FROM rfqs r LEFT JOIN departments d ON d.id = r.department_id
    ORDER BY r.id DESC
  `).all();
  res.json(rows);
});

rfqsRouter.get('/next-number', (_req, res) => {
  res.json({ doc_no: nextDocNumber('rfqs', 'doc_no', 'RFQ') });
});

rfqsRouter.get('/:id', (req, res) => {
  const row = loadRfq(Number(req.params.id));
  if (!row) {
    res.status(404).json({ error: 'RFQ not found' });
    return;
  }
  res.json(row);
});

rfqsRouter.post('/', (req, res) => {
  const body = req.body as RfqInput;
  const result = withTransaction(() => {
    const docNo = nextDocNumber('rfqs', 'doc_no', 'RFQ');
    const info = db.prepare(`
      INSERT INTO rfqs (doc_no, doc_date, department_id, sanction_id, narration)
      VALUES (?, ?, ?, ?, ?)
    `).run(docNo, body.doc_date, body.department_id, body.sanction_id ?? null, body.narration ?? null);
    const rfqId = info.lastInsertRowid;
    const insertItem = db.prepare(`
      INSERT INTO rfq_items (rfq_id, sr_no, material_id, unit, qty) VALUES (?, ?, ?, ?, ?)
    `);
    (body.items ?? []).forEach((item, i) => insertItem.run(rfqId, i + 1, item.material_id, item.unit ?? null, item.qty));
    const insertVendor = db.prepare('INSERT INTO rfq_vendors (rfq_id, account_id) VALUES (?, ?)');
    (body.vendor_ids ?? []).forEach((vid) => insertVendor.run(rfqId, vid));
    return rfqId;
  });
  res.status(201).json(loadRfq(result));
});

rfqsRouter.delete('/:id', (req, res) => {
  const info = db.prepare('DELETE FROM rfqs WHERE id = ?').run(req.params.id);
  if (info.changes === 0) {
    res.status(404).json({ error: 'RFQ not found' });
    return;
  }
  res.status(204).end();
});
