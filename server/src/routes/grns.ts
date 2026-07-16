import { Router } from 'express';
import { db, withTransaction } from '../db/index.js';
import { nextDocNumber } from '../lib/docNumber.js';

export const grnsRouter = Router();

interface GrnItemInput {
  po_item_id: number;
  material_id: number;
  receive_qty: number;
  rate: number;
  freight_gst_recd_basic_amount?: number;
}
interface GrnInput {
  grn_date: string;
  po_id: number;
  bill_no?: string;
  bill_date?: string;
  challan_no?: string;
  challan_date?: string;
  receive_status?: string;
  receive_date?: string;
  items: GrnItemInput[];
}

function loadGrn(id: number | bigint) {
  const header = db.prepare(`
    SELECT g.*, po.doc_no AS po_doc_no, a.name AS vendor_name
    FROM grns g
    LEFT JOIN purchase_orders po ON po.id = g.po_id
    LEFT JOIN accounts a ON a.id = po.vendor_id
    WHERE g.id = ?
  `).get(id);
  if (!header) return null;
  const items = db.prepare(`
    SELECT gi.*, m.code AS material_code, m.name AS material_name
    FROM grn_items gi LEFT JOIN materials m ON m.id = gi.material_id
    WHERE gi.grn_id = ?
  `).all(id);
  return { ...(header as object), items };
}

grnsRouter.get('/', (req, res) => {
  const poId = req.query.po_id as string | undefined;
  const rows = poId
    ? db.prepare('SELECT * FROM grns WHERE po_id = ? ORDER BY id DESC').all(poId)
    : db.prepare(`
        SELECT g.*, po.doc_no AS po_doc_no, a.name AS vendor_name
        FROM grns g LEFT JOIN purchase_orders po ON po.id = g.po_id LEFT JOIN accounts a ON a.id = po.vendor_id
        ORDER BY g.id DESC
      `).all();
  res.json(rows);
});

grnsRouter.get('/next-number', (_req, res) => {
  res.json({ grn_no: nextDocNumber('grns', 'grn_no', 'GRN') });
});

grnsRouter.get('/:id', (req, res) => {
  const row = loadGrn(Number(req.params.id));
  if (!row) {
    res.status(404).json({ error: 'GRN not found' });
    return;
  }
  res.json(row);
});

function recalcPoStatus(poId: number) {
  const rows = db.prepare('SELECT qty, received_qty FROM purchase_order_items WHERE po_id = ?').all(poId) as
    { qty: number; received_qty: number }[];
  const totalQty = rows.reduce((s, r) => s + r.qty, 0);
  const totalReceived = rows.reduce((s, r) => s + r.received_qty, 0);
  const status = totalReceived <= 0 ? 'issued' : totalReceived >= totalQty ? 'received' : 'partially_received';
  db.prepare('UPDATE purchase_orders SET status = ? WHERE id = ?').run(status, poId);
}

grnsRouter.post('/', (req, res) => {
  const body = req.body as GrnInput;
  const result = withTransaction(() => {
    const grnNo = nextDocNumber('grns', 'grn_no', 'GRN');
    const info = db.prepare(`
      INSERT INTO grns (grn_no, grn_date, po_id, bill_no, bill_date, challan_no, challan_date, receive_status, receive_date)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      grnNo, body.grn_date, body.po_id, body.bill_no ?? null, body.bill_date ?? null,
      body.challan_no ?? null, body.challan_date ?? null, body.receive_status ?? 'RECEIVED', body.receive_date ?? body.grn_date,
    );
    const grnId = info.lastInsertRowid;
    const insertItem = db.prepare(`
      INSERT INTO grn_items (grn_id, po_item_id, material_id, receive_qty, rate, basic_receive_amount, freight_gst_recd_basic_amount, landed_rate)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `);
    const updateReceived = db.prepare('UPDATE purchase_order_items SET received_qty = received_qty + ? WHERE id = ?');
    (body.items ?? []).forEach((item) => {
      const basicAmount = Number(item.receive_qty) * Number(item.rate);
      const freightGstAmount = Number(item.freight_gst_recd_basic_amount ?? basicAmount);
      const landedRate = Number(item.receive_qty) > 0 ? freightGstAmount / Number(item.receive_qty) : 0;
      insertItem.run(grnId, item.po_item_id, item.material_id, item.receive_qty, item.rate, basicAmount, freightGstAmount, landedRate);
      if (body.receive_status !== 'CANCEL') {
        updateReceived.run(item.receive_qty, item.po_item_id);
      }
    });
    if (body.receive_status !== 'CANCEL') {
      recalcPoStatus(body.po_id);
    }
    return grnId;
  });
  res.status(201).json(loadGrn(result));
});

grnsRouter.delete('/:id', (req, res) => {
  const id = Number(req.params.id);
  const grn = db.prepare('SELECT po_id FROM grns WHERE id = ?').get(id) as { po_id: number } | undefined;
  if (!grn) {
    res.status(404).json({ error: 'GRN not found' });
    return;
  }
  withTransaction(() => {
    const items = db.prepare('SELECT po_item_id, receive_qty FROM grn_items WHERE grn_id = ?').all(id) as
      { po_item_id: number; receive_qty: number }[];
    const undoReceived = db.prepare('UPDATE purchase_order_items SET received_qty = received_qty - ? WHERE id = ?');
    items.forEach((it) => undoReceived.run(it.receive_qty, it.po_item_id));
    db.prepare('DELETE FROM grns WHERE id = ?').run(id);
    recalcPoStatus(grn.po_id);
  });
  res.status(204).end();
});
