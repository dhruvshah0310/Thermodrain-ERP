import { Router } from 'express';
import { db } from '../db/index.js';

export const reportsRouter = Router();

/** Mirrors the legacy "Sanction Indent Vs Purchase Order" screen: indent qty vs PO-received qty, with balance. */
reportsRouter.get('/indent-vs-po', (req, res) => {
  const from = (req.query.from as string) ?? '2000-01-01';
  const to = (req.query.to as string) ?? '2100-01-01';
  const onlyPending = req.query.only_pending === 'true';

  let sql = `
    SELECT
      si.doc_no AS sanction_doc_no,
      si.doc_date AS sanction_date,
      po.doc_no AS po_doc_no,
      po.doc_date AS po_date,
      a.name AS supplier_name,
      m.code AS material_code,
      m.name AS material_name,
      COALESCE(m.group_head, m.material_type) AS group_name,
      sii.qty AS indent_qty,
      COALESCE(poi.received_qty, 0) AS po_received_qty,
      COALESCE(poi.rate, 0) AS rate,
      COALESCE(poi.amount, 0) AS amount,
      sii.qty - COALESCE(poi.received_qty, 0) AS balance_qty
    FROM sanction_indent_items sii
    JOIN sanction_indents si ON si.id = sii.sanction_id
    LEFT JOIN materials m ON m.id = sii.material_id
    LEFT JOIN purchase_orders po ON po.sanction_id = si.id
    LEFT JOIN accounts a ON a.id = po.vendor_id
    LEFT JOIN purchase_order_items poi ON poi.po_id = po.id AND poi.material_id = sii.material_id
    WHERE si.doc_date BETWEEN ? AND ?
  `;
  if (onlyPending) sql += ' AND (sii.qty - COALESCE(poi.received_qty, 0)) > 0.001';
  sql += ' ORDER BY si.doc_date DESC, si.id DESC';

  res.json(db.prepare(sql).all(from, to));
});

/** Per-material monthly qty/value/avg-rate, computed from GRNs (landed cost) — replaces the "TOTAL MONTH AVG RATE" sheet. */
reportsRouter.get('/material-rate-trend', (req, res) => {
  const materialType = req.query.material_type as string | undefined;
  let sql = `
    SELECT
      strftime('%Y-%m', g.grn_date) AS month,
      COALESCE(m.material_type, 'UNSPECIFIED') AS material_type,
      m.id AS material_id,
      m.name AS material_name,
      SUM(gi.receive_qty) AS total_qty,
      SUM(gi.freight_gst_recd_basic_amount) AS total_value,
      CASE WHEN SUM(gi.receive_qty) > 0 THEN SUM(gi.freight_gst_recd_basic_amount) / SUM(gi.receive_qty) ELSE 0 END AS avg_rate
    FROM grn_items gi
    JOIN grns g ON g.id = gi.grn_id
    LEFT JOIN materials m ON m.id = gi.material_id
    WHERE g.receive_status = 'RECEIVED'
  `;
  const params: string[] = [];
  if (materialType) { sql += ' AND m.material_type = ?'; params.push(materialType); }
  sql += ' GROUP BY month, m.id ORDER BY month DESC, total_value DESC';
  res.json(db.prepare(sql).all(...params));
});

/** Annual material summary — total qty/value/avg rate per material type, across all time. */
reportsRouter.get('/material-annual-summary', (_req, res) => {
  const sql = `
    SELECT
      COALESCE(m.material_type, 'UNSPECIFIED') AS material_type,
      SUM(gi.receive_qty) AS total_qty,
      SUM(gi.freight_gst_recd_basic_amount) AS total_value,
      CASE WHEN SUM(gi.receive_qty) > 0 THEN SUM(gi.freight_gst_recd_basic_amount) / SUM(gi.receive_qty) ELSE 0 END AS avg_rate
    FROM grn_items gi
    JOIN grns g ON g.id = gi.grn_id
    LEFT JOIN materials m ON m.id = gi.material_id
    WHERE g.receive_status = 'RECEIVED'
    GROUP BY material_type
    ORDER BY total_value DESC
  `;
  res.json(db.prepare(sql).all());
});

/** Vendor-wise spend & on-time delivery, used by the Purchase dashboard and a vendor-performance view. */
reportsRouter.get('/vendor-performance', (_req, res) => {
  const sql = `
    SELECT
      a.id AS vendor_id, a.name AS vendor_name,
      COUNT(DISTINCT po.id) AS po_count,
      COALESCE(SUM(po.total_amt), 0) AS total_spend,
      SUM(CASE WHEN po.status = 'received' THEN 1 ELSE 0 END) AS received_count
    FROM accounts a
    LEFT JOIN purchase_orders po ON po.vendor_id = a.id
    WHERE a.kind = 'vendor'
    GROUP BY a.id
    HAVING po_count > 0
    ORDER BY total_spend DESC
  `;
  res.json(db.prepare(sql).all());
});

/** KPI summary for the Purchase dashboard landing view. */
reportsRouter.get('/dashboard', (_req, res) => {
  const openIndents = (db.prepare("SELECT COUNT(*) AS n FROM purchase_indents WHERE status = 'open'").get() as { n: number }).n;
  const pendingSanction = (db.prepare(`
    SELECT COUNT(*) AS n FROM purchase_indents pi
    WHERE pi.status = 'open' AND NOT EXISTS (SELECT 1 FROM sanction_indents si WHERE si.indent_id = pi.id)
  `).get() as { n: number }).n;
  const openPOs = (db.prepare("SELECT COUNT(*) AS n FROM purchase_orders WHERE status IN ('issued','partially_received')").get() as { n: number }).n;
  const grnsThisMonth = (db.prepare("SELECT COUNT(*) AS n FROM grns WHERE strftime('%Y-%m', grn_date) = strftime('%Y-%m','now')").get() as { n: number }).n;
  const activeVendors = (db.prepare("SELECT COUNT(*) AS n FROM accounts WHERE kind = 'vendor' AND inactive = 0").get() as { n: number }).n;
  const poValueThisMonth = (db.prepare("SELECT COALESCE(SUM(total_amt),0) AS v FROM purchase_orders WHERE strftime('%Y-%m', doc_date) = strftime('%Y-%m','now')").get() as { v: number }).v;
  res.json({ openIndents, pendingSanction, openPOs, grnsThisMonth, activeVendors, poValueThisMonth });
});

// ---------- Inbound logistics logs (Transport / Export sheets) ----------

reportsRouter.get('/transport-entries', (_req, res) => {
  res.json(db.prepare(`
    SELECT te.*, a.name AS transporter_name FROM transport_entries te
    LEFT JOIN accounts a ON a.id = te.transporter_id
    ORDER BY te.id DESC
  `).all());
});

reportsRouter.post('/transport-entries', (req, res) => {
  const b = req.body;
  const info = db.prepare(`
    INSERT INTO transport_entries
      (service, entry_month, transporter_id, bill_no, lr_no, lr_date, client_destination, total_point, client_name,
       invoice_no, material_type, material_qty_box, weight_kg, rate_per_kg, terminal_charges, basic_amount, gst_percent, gst_amount, total_amount)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(
    b.service ?? null, b.entry_month ?? null, b.transporter_id ?? null, b.bill_no ?? null, b.lr_no ?? null, b.lr_date ?? null,
    b.client_destination ?? null, b.total_point ?? 1, b.client_name ?? null, b.invoice_no ?? null, b.material_type ?? null,
    b.material_qty_box ?? 0, b.weight_kg ?? 0, b.rate_per_kg ?? 0, b.terminal_charges ?? 0, b.basic_amount ?? 0,
    b.gst_percent ?? 0, b.gst_amount ?? 0, b.total_amount ?? 0,
  );
  res.status(201).json({ id: info.lastInsertRowid });
});

reportsRouter.get('/export-entries', (_req, res) => {
  res.json(db.prepare(`
    SELECT ee.*, a.name AS freight_forwarder_name FROM export_entries ee
    LEFT JOIN accounts a ON a.id = ee.freight_forwarder_id
    ORDER BY ee.id DESC
  `).all());
});

reportsRouter.post('/export-entries', (req, res) => {
  const b = req.body;
  const info = db.prepare(`
    INSERT INTO export_entries
      (cargo_type_service, fiscal_year, entry_month, freight_forwarder_id, po_no, po_date, client_name, port_country,
       cargo_type, packing_no, invoice_no, bill_no, bill_date, work_order_no, pallet_count, weight_kg, cbm, basic_amount, amount_with_gst)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(
    b.cargo_type_service ?? null, b.fiscal_year ?? null, b.entry_month ?? null, b.freight_forwarder_id ?? null,
    b.po_no ?? null, b.po_date ?? null, b.client_name ?? null, b.port_country ?? null, b.cargo_type ?? null,
    b.packing_no ?? null, b.invoice_no ?? null, b.bill_no ?? null, b.bill_date ?? null, b.work_order_no ?? null,
    b.pallet_count ?? 0, b.weight_kg ?? 0, b.cbm ?? 0, b.basic_amount ?? 0, b.amount_with_gst ?? 0,
  );
  res.status(201).json({ id: info.lastInsertRowid });
});
