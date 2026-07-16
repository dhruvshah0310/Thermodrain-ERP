import { Router } from 'express';
import { db, withTransaction } from '../db/index.js';
import { nextDocNumber } from '../lib/docNumber.js';

export const quotationsRouter = Router();

interface QuotationItemInput {
  material_id: number;
  description?: string;
  unit?: string;
  qty: number;
  rate: number;
}
interface QuotationInput {
  doc_date: string;
  vendor_id: number;
  rfq_id?: number | null;
  rfq_no?: string;
  rfq_date?: string;
  department_id?: number | null;
  narration?: string;
  delivery_terms?: string;
  default_printing?: string;
  items: QuotationItemInput[];
}

function loadQuotation(id: number | bigint) {
  const header = db.prepare(`
    SELECT pq.*, a.name AS vendor_name, d.name AS department_name
    FROM purchase_quotations pq
    LEFT JOIN accounts a ON a.id = pq.vendor_id
    LEFT JOIN departments d ON d.id = pq.department_id
    WHERE pq.id = ?
  `).get(id);
  if (!header) return null;
  const items = db.prepare(`
    SELECT qi.*, m.code AS material_code, m.name AS material_name
    FROM purchase_quotation_items qi LEFT JOIN materials m ON m.id = qi.material_id
    WHERE qi.quotation_id = ? ORDER BY qi.sr_no
  `).all(id);
  return { ...(header as object), items };
}

quotationsRouter.get('/', (req, res) => {
  const rfqId = req.query.rfq_id as string | undefined;
  const rows = rfqId
    ? db.prepare(`
        SELECT pq.*, a.name AS vendor_name FROM purchase_quotations pq
        LEFT JOIN accounts a ON a.id = pq.vendor_id WHERE pq.rfq_id = ? ORDER BY pq.total_amt ASC
      `).all(rfqId)
    : db.prepare(`
        SELECT pq.*, a.name AS vendor_name FROM purchase_quotations pq
        LEFT JOIN accounts a ON a.id = pq.vendor_id ORDER BY pq.id DESC
      `).all();
  res.json(rows);
});

quotationsRouter.get('/next-number', (_req, res) => {
  res.json({ doc_no: nextDocNumber('purchase_quotations', 'doc_no', 'PQ') });
});

quotationsRouter.get('/:id', (req, res) => {
  const row = loadQuotation(Number(req.params.id));
  if (!row) {
    res.status(404).json({ error: 'Quotation not found' });
    return;
  }
  res.json(row);
});

function computeTotals(items: QuotationItemInput[]) {
  const totalQty = items.reduce((s, i) => s + Number(i.qty ?? 0), 0);
  const totalAmt = items.reduce((s, i) => s + Number(i.qty ?? 0) * Number(i.rate ?? 0), 0);
  return { totalQty, totalAmt };
}

quotationsRouter.post('/', (req, res) => {
  const body = req.body as QuotationInput;
  const { totalQty, totalAmt } = computeTotals(body.items ?? []);
  const result = withTransaction(() => {
    const docNo = nextDocNumber('purchase_quotations', 'doc_no', 'PQ');
    const info = db.prepare(`
      INSERT INTO purchase_quotations
        (doc_no, doc_date, vendor_id, rfq_id, rfq_no, rfq_date, department_id, narration, delivery_terms, default_printing, total_qty, total_amt)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      docNo, body.doc_date, body.vendor_id, body.rfq_id ?? null, body.rfq_no ?? null, body.rfq_date ?? null,
      body.department_id ?? null, body.narration ?? null, body.delivery_terms ?? null, body.default_printing ?? null,
      totalQty, totalAmt,
    );
    const quotationId = info.lastInsertRowid;
    const insertItem = db.prepare(`
      INSERT INTO purchase_quotation_items (quotation_id, sr_no, material_id, description, unit, qty, rate, amount)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `);
    (body.items ?? []).forEach((item, i) => {
      insertItem.run(
        quotationId, i + 1, item.material_id, item.description ?? null, item.unit ?? null,
        item.qty, item.rate, Number(item.qty) * Number(item.rate),
      );
    });
    return quotationId;
  });
  res.status(201).json(loadQuotation(result));
});

quotationsRouter.delete('/:id', (req, res) => {
  const info = db.prepare('DELETE FROM purchase_quotations WHERE id = ?').run(req.params.id);
  if (info.changes === 0) {
    res.status(404).json({ error: 'Quotation not found' });
    return;
  }
  res.status(204).end();
});

/** Side-by-side rate comparison across all quotations received for an RFQ, by material. */
quotationsRouter.get('/compare/:rfqId', (req, res) => {
  const rows = db.prepare(`
    SELECT pq.id AS quotation_id, pq.vendor_id, a.name AS vendor_name, pq.doc_no, pq.total_amt,
      qi.material_id, m.name AS material_name, qi.qty, qi.rate, qi.amount
    FROM purchase_quotations pq
    JOIN accounts a ON a.id = pq.vendor_id
    JOIN purchase_quotation_items qi ON qi.quotation_id = pq.id
    LEFT JOIN materials m ON m.id = qi.material_id
    WHERE pq.rfq_id = ?
    ORDER BY qi.material_id, qi.rate ASC
  `).all(req.params.rfqId);
  res.json(rows);
});
