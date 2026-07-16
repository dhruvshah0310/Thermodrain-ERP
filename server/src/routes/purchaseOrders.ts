import { Router } from 'express';
import { db, withTransaction } from '../db/index.js';
import { nextDocNumber } from '../lib/docNumber.js';

export const purchaseOrdersRouter = Router();

interface PoItemInput {
  material_id: number;
  tax_name?: string;
  hsn_no?: string;
  description?: string;
  delivery_date?: string;
  unit?: string;
  qty: number;
  rate: number;
}
interface PoInput {
  doc_date: string;
  vendor_id: number;
  department_id?: number | null;
  delivery_terms?: string;
  del_days?: number;
  del_date?: string;
  sanction_id?: number | null;
  si_date?: string;
  transport?: string;
  payment_terms?: string;
  narration?: string;
  quotation_id?: number | null;
  pq_date?: string;
  consignee?: string;
  default_printing?: string;
  freight?: number;
  other_charge?: number;
  discount_amt?: number;
  round_off?: number;
  status?: string;
  items: PoItemInput[];
}

function loadPo(id: number | bigint) {
  const header = db.prepare(`
    SELECT po.*, a.name AS vendor_name, a.gst_no AS vendor_gst_no, d.name AS department_name,
      si.doc_no AS sanction_doc_no, pq.doc_no AS quotation_doc_no
    FROM purchase_orders po
    LEFT JOIN accounts a ON a.id = po.vendor_id
    LEFT JOIN departments d ON d.id = po.department_id
    LEFT JOIN sanction_indents si ON si.id = po.sanction_id
    LEFT JOIN purchase_quotations pq ON pq.id = po.quotation_id
    WHERE po.id = ?
  `).get(id);
  if (!header) return null;
  const items = db.prepare(`
    SELECT poi.*, m.code AS material_code, m.name AS material_name
    FROM purchase_order_items poi LEFT JOIN materials m ON m.id = poi.material_id
    WHERE poi.po_id = ? ORDER BY poi.sr_no
  `).all(id);
  const grns = db.prepare(`SELECT id, grn_no, grn_date, receive_status FROM grns WHERE po_id = ? ORDER BY id DESC`).all(id);
  return { ...(header as object), items, grns };
}

purchaseOrdersRouter.get('/', (req, res) => {
  const status = req.query.status as string | undefined;
  const vendorId = req.query.vendor_id as string | undefined;
  let sql = `
    SELECT po.*, a.name AS vendor_name, d.name AS department_name,
      (SELECT COALESCE(SUM(received_qty),0) FROM purchase_order_items WHERE po_id = po.id) AS received_qty,
      (SELECT COALESCE(SUM(qty),0) FROM purchase_order_items WHERE po_id = po.id) AS ordered_qty
    FROM purchase_orders po
    LEFT JOIN accounts a ON a.id = po.vendor_id
    LEFT JOIN departments d ON d.id = po.department_id
    WHERE 1=1
  `;
  const params: (string | number)[] = [];
  if (status) { sql += ' AND po.status = ?'; params.push(status); }
  if (vendorId) { sql += ' AND po.vendor_id = ?'; params.push(vendorId); }
  sql += ' ORDER BY po.id DESC';
  res.json(db.prepare(sql).all(...params));
});

purchaseOrdersRouter.get('/next-number', (_req, res) => {
  res.json({ doc_no: nextDocNumber('purchase_orders', 'doc_no', 'PO') });
});

purchaseOrdersRouter.get('/:id', (req, res) => {
  const row = loadPo(Number(req.params.id));
  if (!row) {
    res.status(404).json({ error: 'Purchase order not found' });
    return;
  }
  res.json(row);
});

/** GST split mirrors the legacy form: intra-state -> CGST+SGST, inter-state -> IGST, driven by vendor state vs company state (Maharashtra). */
function computeTaxSplit(items: PoItemInput[], vendorState: string | null | undefined, materialGstRates: Map<number, number>) {
  const assessableAmt = items.reduce((s, i) => s + Number(i.qty) * Number(i.rate), 0);
  const isInterState = !!vendorState && vendorState.trim().toLowerCase() !== 'maharashtra';
  let taxAmt = 0;
  for (const item of items) {
    const lineAmt = Number(item.qty) * Number(item.rate);
    const gstRate = materialGstRates.get(item.material_id) ?? 18;
    taxAmt += (lineAmt * gstRate) / 100;
  }
  const cgst = isInterState ? 0 : taxAmt / 2;
  const sgst = isInterState ? 0 : taxAmt / 2;
  const igst = isInterState ? taxAmt : 0;
  return { assessableAmt, taxAmt, cgst, sgst, igst };
}

function saveItemsAndTotals(poId: number | bigint, body: PoInput) {
  db.prepare('DELETE FROM purchase_order_items WHERE po_id = ?').run(poId);
  const insertItem = db.prepare(`
    INSERT INTO purchase_order_items (po_id, sr_no, material_id, tax_name, hsn_no, description, delivery_date, unit, qty, rate, amount)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);
  (body.items ?? []).forEach((item, i) => {
    insertItem.run(
      poId, i + 1, item.material_id, item.tax_name ?? null, item.hsn_no ?? null, item.description ?? null,
      item.delivery_date ?? null, item.unit ?? null, item.qty, item.rate, Number(item.qty) * Number(item.rate),
    );
  });

  const vendor = db.prepare('SELECT state FROM accounts WHERE id = ?').get(body.vendor_id) as { state: string | null } | undefined;
  const materialIds = (body.items ?? []).map((i) => i.material_id);
  const gstRates = new Map<number, number>();
  if (materialIds.length > 0) {
    const placeholders = materialIds.map(() => '?').join(',');
    const rows = db.prepare(`SELECT id, gst_percent FROM materials WHERE id IN (${placeholders})`).all(...materialIds) as { id: number; gst_percent: number }[];
    rows.forEach((r) => gstRates.set(r.id, r.gst_percent));
  }
  const { assessableAmt, taxAmt, cgst, sgst, igst } = computeTaxSplit(body.items ?? [], vendor?.state, gstRates);
  const freight = Number(body.freight ?? 0);
  const otherCharge = Number(body.other_charge ?? 0);
  const discountAmt = Number(body.discount_amt ?? 0);
  const roundOffRaw = Number(body.round_off ?? 0);
  const grossAmt = assessableAmt + taxAmt + freight + otherCharge - discountAmt;
  const totalQty = (body.items ?? []).reduce((s, i) => s + Number(i.qty), 0);
  const totalAmt = grossAmt + roundOffRaw;

  db.prepare(`
    UPDATE purchase_orders SET
      cgst = ?, sgst = ?, igst = ?, freight = ?, other_charge = ?, discount_amt = ?, round_off = ?, tax_amt = ?,
      total_qty = ?, total_amt = ?, gross_amt = ?, assessable_amt = ?
    WHERE id = ?
  `).run(cgst, sgst, igst, freight, otherCharge, discountAmt, roundOffRaw, taxAmt, totalQty, totalAmt, grossAmt, assessableAmt, poId);
}

purchaseOrdersRouter.post('/', (req, res) => {
  const body = req.body as PoInput;
  const result = withTransaction(() => {
    const docNo = nextDocNumber('purchase_orders', 'doc_no', 'PO');
    const info = db.prepare(`
      INSERT INTO purchase_orders
        (doc_no, doc_date, vendor_id, department_id, delivery_terms, del_days, del_date, sanction_id, si_date,
         transport, payment_terms, narration, quotation_id, pq_date, consignee, default_printing, status)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      docNo, body.doc_date, body.vendor_id, body.department_id ?? null, body.delivery_terms ?? null,
      body.del_days ?? null, body.del_date ?? null, body.sanction_id ?? null, body.si_date ?? null,
      body.transport ?? null, body.payment_terms ?? null, body.narration ?? null, body.quotation_id ?? null,
      body.pq_date ?? null, body.consignee ?? null, body.default_printing ?? null, body.status ?? 'issued',
    );
    const poId = info.lastInsertRowid;
    saveItemsAndTotals(poId, body);
    if (body.sanction_id) {
      db.prepare("UPDATE sanction_indents SET purchase_order_linked = 1 WHERE id = ?").run(body.sanction_id);
    }
    return poId;
  });
  res.status(201).json(loadPo(result));
});

purchaseOrdersRouter.put('/:id', (req, res) => {
  const id = Number(req.params.id);
  const body = req.body as PoInput;
  withTransaction(() => {
    db.prepare(`
      UPDATE purchase_orders SET
        doc_date = ?, vendor_id = ?, department_id = ?, delivery_terms = ?, del_days = ?, del_date = ?,
        sanction_id = ?, si_date = ?, transport = ?, payment_terms = ?, narration = ?, quotation_id = ?,
        pq_date = ?, consignee = ?, default_printing = ?, status = ?
      WHERE id = ?
    `).run(
      body.doc_date, body.vendor_id, body.department_id ?? null, body.delivery_terms ?? null,
      body.del_days ?? null, body.del_date ?? null, body.sanction_id ?? null, body.si_date ?? null,
      body.transport ?? null, body.payment_terms ?? null, body.narration ?? null, body.quotation_id ?? null,
      body.pq_date ?? null, body.consignee ?? null, body.default_printing ?? null, body.status ?? 'issued', id,
    );
    saveItemsAndTotals(id, body);
  });
  res.json(loadPo(id));
});

purchaseOrdersRouter.delete('/:id', (req, res) => {
  const info = db.prepare('DELETE FROM purchase_orders WHERE id = ?').run(req.params.id);
  if (info.changes === 0) {
    res.status(404).json({ error: 'Purchase order not found' });
    return;
  }
  res.status(204).end();
});
