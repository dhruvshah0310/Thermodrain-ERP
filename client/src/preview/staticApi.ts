/**
 * In-browser stand-in for the real Express API, used only by the preview
 * build (`npm run build:preview`). Mirrors every route in server/src/routes
 * against an in-memory copy of a real database snapshot (client/src/preview/
 * snapshot.json — regenerate by dumping the live erp.db to JSON). Mutations
 * (POST/PUT) apply to the in-memory copy only and are lost on reload — there
 * is no backend here, this all runs in your browser tab.
 *
 * Keep this in sync with server/src/routes/*.ts by hand when those change;
 * it intentionally duplicates their logic rather than importing them, since
 * this bundle ships to the browser and the server code assumes node:sqlite.
 */
import snapshot from './snapshot.json';

// eslint-disable-next-line @typescript-eslint/no-explicit-any
interface Row { id: number; [key: string]: any }

function clone<T>(v: T): T {
  return JSON.parse(JSON.stringify(v));
}

const db = clone(snapshot) as Record<string, Row[]>;

function nextId(table: string): number {
  const rows = db[table] ?? [];
  return rows.reduce((max, r) => Math.max(max, r.id), 0) + 1;
}

function fiscalYearLabel(date = new Date()): string {
  const y = date.getFullYear();
  const startYear = date.getMonth() >= 3 ? y : y - 1;
  return `${String(startYear).slice(-2)}-${String(startYear + 1).slice(-2)}`;
}

function nextDocNumber(table: string, field: string, prefix: string): string {
  const fy = fiscalYearLabel();
  const like = `${prefix}/${fy}/`;
  const matches = (db[table] ?? [])
    .map((r) => String(r[field] ?? ''))
    .filter((v) => v.startsWith(like));
  let seq = 1;
  if (matches.length > 0) {
    const seqs = matches.map((v) => Number(v.split('/').pop())).filter((n) => !Number.isNaN(n));
    if (seqs.length > 0) seq = Math.max(...seqs) + 1;
  }
  return `${prefix}/${fy}/${String(seq).padStart(4, '0')}`;
}

const byId = (table: string, id: number) => (db[table] ?? []).find((r) => r.id === id);
const dept = (id: unknown) => byId('departments', Number(id)) as Row | undefined;
const account = (id: unknown) => byId('accounts', Number(id)) as Row | undefined;
const material = (id: unknown) => byId('materials', Number(id)) as Row | undefined;

function todayIso() {
  return new Date().toISOString().slice(0, 10);
}

// ---------- Indents ----------

function loadIndent(id: number) {
  const header = byId('purchase_indents', id);
  if (!header) return null;
  const items = (db.purchase_indent_items ?? [])
    .filter((r) => r.indent_id === id)
    .sort((a, b) => Number(a.sr_no) - Number(b.sr_no))
    .map((it) => {
      const m = material(it.material_id);
      return { ...it, material_code: m?.code, material_name: m?.name } as Row;
    });
  return { ...header, department_name: dept(header.department_id)?.name, items };
}

function listIndents(status?: string) {
  return (db.purchase_indents ?? [])
    .filter((r) => !status || r.status === status)
    .map((r) => ({
      ...r,
      department_name: dept(r.department_id)?.name,
      item_count: (db.purchase_indent_items ?? []).filter((it) => it.indent_id === r.id).length,
    }))
    .sort((a, b) => b.id - a.id);
}

function createIndent(body: any) {
  const id = nextId('purchase_indents');
  const indent_no = nextDocNumber('purchase_indents', 'indent_no', 'IND');
  const header: Row = {
    id, indent_no, indent_date: body.indent_date, department_id: body.department_id,
    narration: body.narration ?? null, status: body.status ?? 'open',
  };
  db.purchase_indents.push(header);
  (body.items ?? []).forEach((item: any, i: number) => {
    db.purchase_indent_items.push({
      id: nextId('purchase_indent_items') + i, indent_id: id, sr_no: i + 1,
      material_id: item.material_id, unit: item.unit ?? null, req_qty: item.req_qty, remark: item.remark ?? null,
    });
  });
  return loadIndent(id);
}

function updateIndent(id: number, body: any) {
  const header = byId('purchase_indents', id);
  if (!header) return null;
  Object.assign(header, {
    indent_date: body.indent_date, department_id: body.department_id,
    narration: body.narration ?? null, status: body.status ?? 'open',
  });
  db.purchase_indent_items = (db.purchase_indent_items ?? []).filter((it) => it.indent_id !== id);
  (body.items ?? []).forEach((item: any, i: number) => {
    db.purchase_indent_items.push({
      id: nextId('purchase_indent_items') + i, indent_id: id, sr_no: i + 1,
      material_id: item.material_id, unit: item.unit ?? null, req_qty: item.req_qty, remark: item.remark ?? null,
    });
  });
  return loadIndent(id);
}

// ---------- Sanction Indents ----------

function loadSanction(id: number) {
  const header = byId('sanction_indents', id);
  if (!header) return null;
  const items = (db.sanction_indent_items ?? [])
    .filter((r) => r.sanction_id === id)
    .sort((a, b) => Number(a.sr_no) - Number(b.sr_no))
    .map((it) => {
      const m = material(it.material_id);
      return { ...it, material_code: m?.code, material_name: m?.name } as Row;
    });
  const totalQty = items.reduce((s, it) => s + Number(it.qty ?? 0), 0);
  const indent = header.indent_id ? byId('purchase_indents', Number(header.indent_id)) : undefined;
  return { ...header, department_name: dept(header.department_id)?.name, indent_no: indent?.indent_no, items, total_qty: totalQty };
}

function listSanctions() {
  return (db.sanction_indents ?? [])
    .map((r) => ({
      ...r,
      department_name: dept(r.department_id)?.name,
      item_count: (db.sanction_indent_items ?? []).filter((it) => it.sanction_id === r.id).length,
    }))
    .sort((a, b) => b.id - a.id);
}

function createSanction(body: any) {
  const id = nextId('sanction_indents');
  const doc_no = nextDocNumber('sanction_indents', 'doc_no', 'SI');
  const header: Row = {
    id, doc_no, doc_date: body.doc_date, department_id: body.department_id, indent_id: body.indent_id ?? null,
    narration: body.narration ?? null, purchase_order_linked: 0, default_printing: body.default_printing ?? 'Sanction Indent',
  };
  db.sanction_indents.push(header);
  (body.items ?? []).forEach((item: any, i: number) => {
    db.sanction_indent_items.push({
      id: nextId('sanction_indent_items') + i, sanction_id: id, sr_no: i + 1,
      material_id: item.material_id, hsn_no: item.hsn_no ?? null, unit: item.unit ?? null, qty: item.qty, remark: item.remark ?? null,
    });
  });
  if (body.indent_id) {
    const indent = byId('purchase_indents', Number(body.indent_id));
    if (indent) indent.status = 'sanctioned';
  }
  return loadSanction(id);
}

function updateSanction(id: number, body: any) {
  const header = byId('sanction_indents', id);
  if (!header) return null;
  Object.assign(header, {
    doc_date: body.doc_date, department_id: body.department_id, indent_id: body.indent_id ?? null,
    narration: body.narration ?? null, default_printing: body.default_printing ?? 'Sanction Indent',
  });
  db.sanction_indent_items = (db.sanction_indent_items ?? []).filter((it) => it.sanction_id !== id);
  (body.items ?? []).forEach((item: any, i: number) => {
    db.sanction_indent_items.push({
      id: nextId('sanction_indent_items') + i, sanction_id: id, sr_no: i + 1,
      material_id: item.material_id, hsn_no: item.hsn_no ?? null, unit: item.unit ?? null, qty: item.qty, remark: item.remark ?? null,
    });
  });
  return loadSanction(id);
}

// ---------- RFQs ----------

function loadRfq(id: number) {
  const header = byId('rfqs', id);
  if (!header) return null;
  const items = (db.rfq_items ?? []).filter((r) => r.rfq_id === id).map((it) => {
    const m = material(it.material_id);
    return { ...it, material_code: m?.code, material_name: m?.name } as Row;
  });
  const vendors = (db.rfq_vendors ?? [])
    .filter((r) => r.rfq_id === id)
    .map((rv) => account(rv.account_id))
    .filter(Boolean)
    .map((a) => ({ id: a!.id, name: a!.name }));
  const sanction = header.sanction_id ? byId('sanction_indents', Number(header.sanction_id)) : undefined;
  const quotations_received = (db.purchase_quotations ?? []).filter((q) => q.rfq_id === id).length;
  return { ...header, department_name: dept(header.department_id)?.name, sanction_doc_no: sanction?.doc_no, items, vendors, quotations_received };
}

function listRfqs() {
  return (db.rfqs ?? [])
    .map((r) => ({
      ...r,
      department_name: dept(r.department_id)?.name,
      vendor_count: (db.rfq_vendors ?? []).filter((rv) => rv.rfq_id === r.id).length,
      quotations_received: (db.purchase_quotations ?? []).filter((q) => q.rfq_id === r.id).length,
    }))
    .sort((a, b) => b.id - a.id);
}

function createRfq(body: any) {
  const id = nextId('rfqs');
  const doc_no = nextDocNumber('rfqs', 'doc_no', 'RFQ');
  db.rfqs.push({ id, doc_no, doc_date: body.doc_date, department_id: body.department_id, sanction_id: body.sanction_id ?? null, narration: body.narration ?? null });
  (body.items ?? []).forEach((item: any, i: number) => {
    db.rfq_items.push({ id: nextId('rfq_items') + i, rfq_id: id, sr_no: i + 1, material_id: item.material_id, unit: item.unit ?? null, qty: item.qty });
  });
  (body.vendor_ids ?? []).forEach((vid: number) => {
    db.rfq_vendors.push({ id: 0, rfq_id: id, account_id: vid });
  });
  return loadRfq(id);
}

// ---------- Purchase Quotations ----------

function loadQuotation(id: number) {
  const header = byId('purchase_quotations', id);
  if (!header) return null;
  const items = (db.purchase_quotation_items ?? []).filter((r) => r.quotation_id === id).map((it) => {
    const m = material(it.material_id);
    return { ...it, material_code: m?.code, material_name: m?.name } as Row;
  });
  return { ...header, vendor_name: account(header.vendor_id)?.name, department_name: dept(header.department_id)?.name, items };
}

function listQuotations(rfqId?: string) {
  let rows = db.purchase_quotations ?? [];
  if (rfqId) rows = rows.filter((r) => String(r.rfq_id) === rfqId);
  return rows
    .map((r) => ({ ...r, vendor_name: account(r.vendor_id)?.name }) as Row)
    .sort((a, b) => (rfqId ? Number(a.total_amt) - Number(b.total_amt) : b.id - a.id));
}

function createQuotation(body: any) {
  const id = nextId('purchase_quotations');
  const doc_no = nextDocNumber('purchase_quotations', 'doc_no', 'PQ');
  const items = (body.items ?? []).map((item: any) => ({ ...item, amount: Number(item.qty) * Number(item.rate) }));
  const total_qty = items.reduce((s: number, i: any) => s + Number(i.qty ?? 0), 0);
  const total_amt = items.reduce((s: number, i: any) => s + Number(i.amount ?? 0), 0);
  db.purchase_quotations.push({
    id, doc_no, doc_date: body.doc_date, vendor_id: body.vendor_id, rfq_id: body.rfq_id ?? null,
    rfq_no: body.rfq_no ?? null, rfq_date: body.rfq_date ?? null, department_id: body.department_id ?? null,
    narration: body.narration ?? null, delivery_terms: body.delivery_terms ?? null, default_printing: body.default_printing ?? null,
    total_qty, total_amt,
  });
  items.forEach((item: any, i: number) => {
    db.purchase_quotation_items.push({
      id: nextId('purchase_quotation_items') + i, quotation_id: id, sr_no: i + 1, material_id: item.material_id,
      description: item.description ?? null, unit: item.unit ?? null, qty: item.qty, rate: item.rate, amount: item.amount,
    });
  });
  return loadQuotation(id);
}

function compareQuotations(rfqId: number) {
  const quotations = (db.purchase_quotations ?? []).filter((q) => q.rfq_id === rfqId);
  const rows: any[] = [];
  quotations.forEach((q) => {
    const vendor = account(q.vendor_id);
    (db.purchase_quotation_items ?? []).filter((it) => it.quotation_id === q.id).forEach((it) => {
      const m = material(it.material_id);
      rows.push({
        quotation_id: q.id, vendor_id: q.vendor_id, vendor_name: vendor?.name, doc_no: q.doc_no, total_amt: q.total_amt,
        material_id: it.material_id, material_name: m?.name, qty: it.qty, rate: it.rate, amount: it.amount,
      });
    });
  });
  return rows.sort((a, b) => a.material_id - b.material_id || Number(a.rate) - Number(b.rate));
}

// ---------- Purchase Orders ----------

function computeTaxSplit(items: any[], vendorState: string | null | undefined) {
  const assessableAmt = items.reduce((s, i) => s + Number(i.qty) * Number(i.rate), 0);
  const isInterState = !!vendorState && vendorState.trim().toLowerCase() !== 'maharashtra';
  let taxAmt = 0;
  for (const item of items) {
    const lineAmt = Number(item.qty) * Number(item.rate);
    const gstRate = Number(material(item.material_id)?.gst_percent ?? 18);
    taxAmt += (lineAmt * gstRate) / 100;
  }
  const cgst = isInterState ? 0 : taxAmt / 2;
  const sgst = isInterState ? 0 : taxAmt / 2;
  const igst = isInterState ? taxAmt : 0;
  return { assessableAmt, taxAmt, cgst, sgst, igst };
}

function loadPo(id: number) {
  const header = byId('purchase_orders', id);
  if (!header) return null;
  const items = (db.purchase_order_items ?? [])
    .filter((r) => r.po_id === id)
    .sort((a, b) => Number(a.sr_no) - Number(b.sr_no))
    .map((it) => {
      const m = material(it.material_id);
      return { ...it, material_code: m?.code, material_name: m?.name } as Row;
    });
  const grns = (db.grns ?? []).filter((g) => g.po_id === id).map((g) => ({ id: g.id, grn_no: g.grn_no, grn_date: g.grn_date, receive_status: g.receive_status }));
  const sanction = header.sanction_id ? byId('sanction_indents', Number(header.sanction_id)) : undefined;
  const quotation = header.quotation_id ? byId('purchase_quotations', Number(header.quotation_id)) : undefined;
  const vendor = account(header.vendor_id);
  return {
    ...header, vendor_name: vendor?.name, vendor_gst_no: vendor?.gst_no, department_name: dept(header.department_id)?.name,
    sanction_doc_no: sanction?.doc_no, quotation_doc_no: quotation?.doc_no, items, grns,
  };
}

function listPos(status?: string, vendorId?: string) {
  let rows = db.purchase_orders ?? [];
  if (status) rows = rows.filter((r) => r.status === status);
  if (vendorId) rows = rows.filter((r) => String(r.vendor_id) === vendorId);
  return rows
    .map((r) => {
      const items = (db.purchase_order_items ?? []).filter((it) => it.po_id === r.id);
      return {
        ...r,
        vendor_name: account(r.vendor_id)?.name,
        department_name: dept(r.department_id)?.name,
        ordered_qty: items.reduce((s, it) => s + Number(it.qty ?? 0), 0),
        received_qty: items.reduce((s, it) => s + Number(it.received_qty ?? 0), 0),
      };
    })
    .sort((a, b) => b.id - a.id);
}

function createPo(body: any) {
  const id = nextId('purchase_orders');
  const doc_no = nextDocNumber('purchase_orders', 'doc_no', 'PO');
  const vendor = account(body.vendor_id);
  const items = (body.items ?? []).map((item: any) => ({ ...item, amount: Number(item.qty) * Number(item.rate) }));
  const { assessableAmt, taxAmt, cgst, sgst, igst } = computeTaxSplit(items, vendor?.state as string | undefined);
  const freight = Number(body.freight ?? 0);
  const otherCharge = Number(body.other_charge ?? 0);
  const discountAmt = Number(body.discount_amt ?? 0);
  const roundOff = Number(body.round_off ?? 0);
  const grossAmt = assessableAmt + taxAmt + freight + otherCharge - discountAmt;
  const totalQty = items.reduce((s: number, i: any) => s + Number(i.qty), 0);
  const totalAmt = grossAmt + roundOff;

  db.purchase_orders.push({
    id, doc_no, doc_date: body.doc_date, vendor_id: body.vendor_id, department_id: body.department_id ?? null,
    delivery_terms: body.delivery_terms ?? null, del_days: body.del_days ?? null, del_date: body.del_date ?? null,
    sanction_id: body.sanction_id ?? null, si_date: body.si_date ?? null, transport: body.transport ?? null,
    payment_terms: body.payment_terms ?? null, narration: body.narration ?? null, quotation_id: body.quotation_id ?? null,
    pq_date: body.pq_date ?? null, consignee: body.consignee ?? null, default_printing: body.default_printing ?? null,
    cgst, sgst, igst, freight, other_charge: otherCharge, discount_amt: discountAmt, round_off: roundOff, tax_amt: taxAmt,
    total_qty: totalQty, total_amt: totalAmt, gross_amt: grossAmt, assessable_amt: assessableAmt,
    status: body.status ?? 'issued', bill_no: null, bill_date: null,
  });
  items.forEach((item: any, i: number) => {
    db.purchase_order_items.push({
      id: nextId('purchase_order_items') + i, po_id: id, sr_no: i + 1, material_id: item.material_id,
      tax_name: item.tax_name ?? null, hsn_no: item.hsn_no ?? null, description: item.description ?? null,
      delivery_date: item.delivery_date ?? null, unit: item.unit ?? null, qty: item.qty, rate: item.rate,
      amount: item.amount, received_qty: 0,
    });
  });
  if (body.sanction_id) {
    const sanction = byId('sanction_indents', Number(body.sanction_id));
    if (sanction) sanction.purchase_order_linked = 1;
  }
  return loadPo(id);
}

// ---------- GRNs ----------

function loadGrn(id: number) {
  const header = byId('grns', id);
  if (!header) return null;
  const po = header.po_id ? byId('purchase_orders', Number(header.po_id)) : undefined;
  const items = (db.grn_items ?? []).filter((r) => r.grn_id === id).map((it) => {
    const m = material(it.material_id);
    return { ...it, material_code: m?.code, material_name: m?.name } as Row;
  });
  return { ...header, po_doc_no: po?.doc_no, vendor_name: po ? account(po.vendor_id)?.name : undefined, items };
}

function listGrns(poId?: string) {
  let rows = db.grns ?? [];
  if (poId) rows = rows.filter((r) => String(r.po_id) === poId);
  return rows
    .map((r) => {
      const po = r.po_id ? byId('purchase_orders', Number(r.po_id)) : undefined;
      return { ...r, po_doc_no: po?.doc_no, vendor_name: po ? account(po.vendor_id)?.name : undefined };
    })
    .sort((a, b) => b.id - a.id);
}

function recalcPoStatus(poId: number) {
  const items = (db.purchase_order_items ?? []).filter((it) => it.po_id === poId);
  const totalQty = items.reduce((s, r) => s + Number(r.qty), 0);
  const totalReceived = items.reduce((s, r) => s + Number(r.received_qty ?? 0), 0);
  const po = byId('purchase_orders', poId);
  if (po) po.status = totalReceived <= 0 ? 'issued' : totalReceived >= totalQty ? 'received' : 'partially_received';
}

function createGrn(body: any) {
  const id = nextId('grns');
  const grn_no = nextDocNumber('grns', 'grn_no', 'GRN');
  db.grns.push({
    id, grn_no, grn_date: body.grn_date, po_id: body.po_id, bill_no: body.bill_no ?? null, bill_date: body.bill_date ?? null,
    challan_no: body.challan_no ?? null, challan_date: body.challan_date ?? null, receive_status: body.receive_status ?? 'RECEIVED',
    receive_date: body.receive_date ?? body.grn_date,
  });
  (body.items ?? []).forEach((item: any, i: number) => {
    const basicAmount = Number(item.receive_qty) * Number(item.rate);
    const freightGstAmount = Number(item.freight_gst_recd_basic_amount ?? basicAmount);
    const landedRate = Number(item.receive_qty) > 0 ? freightGstAmount / Number(item.receive_qty) : 0;
    db.grn_items.push({
      id: nextId('grn_items') + i, grn_id: id, po_item_id: item.po_item_id, material_id: item.material_id,
      receive_qty: item.receive_qty, rate: item.rate, basic_receive_amount: basicAmount,
      freight_gst_recd_basic_amount: freightGstAmount, landed_rate: landedRate,
    });
    if (body.receive_status !== 'CANCEL') {
      const poItem = byId('purchase_order_items', Number(item.po_item_id));
      if (poItem) poItem.received_qty = Number(poItem.received_qty ?? 0) + Number(item.receive_qty);
    }
  });
  if (body.receive_status !== 'CANCEL') recalcPoStatus(Number(body.po_id));
  return loadGrn(id);
}

// ---------- Reports ----------

function reportIndentVsPo(from: string, to: string, onlyPending: boolean) {
  const rows: any[] = [];
  (db.sanction_indent_items ?? []).forEach((sii) => {
    const si = byId('sanction_indents', Number(sii.sanction_id));
    if (!si || si.doc_date < from || si.doc_date > to) return;
    const m = material(sii.material_id);
    const po = (db.purchase_orders ?? []).find((p) => p.sanction_id === si.id);
    const poi = po ? (db.purchase_order_items ?? []).find((it) => it.po_id === po.id && it.material_id === sii.material_id) : undefined;
    const balance = Number(sii.qty) - Number(poi?.received_qty ?? 0);
    if (onlyPending && balance <= 0.001) return;
    rows.push({
      sanction_doc_no: si.doc_no, sanction_date: si.doc_date, po_doc_no: po?.doc_no, po_date: po?.doc_date,
      supplier_name: po ? account(po.vendor_id)?.name : undefined, material_code: m?.code, material_name: m?.name,
      group_name: m?.group_head ?? m?.material_type, indent_qty: sii.qty, po_received_qty: poi?.received_qty ?? 0,
      rate: poi?.rate ?? 0, amount: poi?.amount ?? 0, balance_qty: balance,
    });
  });
  return rows.sort((a, b) => (a.sanction_date < b.sanction_date ? 1 : -1));
}

function reportRateTrend(materialType?: string) {
  const buckets = new Map<string, any>();
  (db.grn_items ?? []).forEach((gi) => {
    const grn = byId('grns', Number(gi.grn_id));
    if (!grn || grn.receive_status !== 'RECEIVED') return;
    const m = material(gi.material_id);
    if (materialType && m?.material_type !== materialType) return;
    const month = String(grn.grn_date).slice(0, 7);
    const key = `${month}::${gi.material_id}`;
    if (!buckets.has(key)) {
      buckets.set(key, { month, material_type: m?.material_type ?? 'UNSPECIFIED', material_id: gi.material_id, material_name: m?.name, total_qty: 0, total_value: 0 });
    }
    const b = buckets.get(key);
    b.total_qty += Number(gi.receive_qty ?? 0);
    b.total_value += Number(gi.freight_gst_recd_basic_amount ?? 0);
  });
  return [...buckets.values()]
    .map((b) => ({ ...b, avg_rate: b.total_qty > 0 ? b.total_value / b.total_qty : 0 }))
    .sort((a, b) => (a.month < b.month ? 1 : a.month > b.month ? -1 : b.total_value - a.total_value));
}

function reportVendorPerformance() {
  return (db.accounts ?? [])
    .filter((a) => a.kind === 'vendor')
    .map((a) => {
      const pos = (db.purchase_orders ?? []).filter((p) => p.vendor_id === a.id);
      return {
        vendor_id: a.id, vendor_name: a.name, po_count: pos.length,
        total_spend: pos.reduce((s, p) => s + Number(p.total_amt ?? 0), 0),
        received_count: pos.filter((p) => p.status === 'received').length,
      };
    })
    .filter((v) => v.po_count > 0)
    .sort((a, b) => b.total_spend - a.total_spend);
}

function reportDashboard() {
  const openIndents = (db.purchase_indents ?? []).filter((i) => i.status === 'open').length;
  const pendingSanction = (db.purchase_indents ?? []).filter(
    (i) => i.status === 'open' && !(db.sanction_indents ?? []).some((s) => s.indent_id === i.id),
  ).length;
  const openPOs = (db.purchase_orders ?? []).filter((p) => p.status === 'issued' || p.status === 'partially_received').length;
  const thisMonth = todayIso().slice(0, 7);
  const grnsThisMonth = (db.grns ?? []).filter((g) => String(g.grn_date).slice(0, 7) === thisMonth).length;
  const activeVendors = (db.accounts ?? []).filter((a) => a.kind === 'vendor' && !a.inactive).length;
  const poValueThisMonth = (db.purchase_orders ?? [])
    .filter((p) => String(p.doc_date).slice(0, 7) === thisMonth)
    .reduce((s, p) => s + Number(p.total_amt ?? 0), 0);
  return { openIndents, pendingSanction, openPOs, grnsThisMonth, activeVendors, poValueThisMonth };
}

// ---------- Router ----------

export async function staticRequest<T>(method: string, fullPath: string, body?: unknown): Promise<T> {
  const [path, queryString] = fullPath.split('?');
  const query = new URLSearchParams(queryString ?? '');
  const parts = path.split('/').filter(Boolean);

  const match = (pattern: string[]): Record<string, string> | null => {
    if (pattern.length !== parts.length) return null;
    const params: Record<string, string> = {};
    for (let i = 0; i < pattern.length; i++) {
      if (pattern[i].startsWith(':')) params[pattern[i].slice(1)] = parts[i];
      else if (pattern[i] !== parts[i]) return null;
    }
    return params;
  };

  let p: Record<string, string> | null;

  if (method === 'GET' && (p = match(['departments']))) return db.departments.slice().sort((a, b) => String(a.name).localeCompare(String(b.name))) as T;
  if (method === 'GET' && (p = match(['units']))) return db.units.slice().sort((a, b) => String(a.name).localeCompare(String(b.name))) as T;
  if (method === 'GET' && (p = match(['accounts']))) {
    const kind = query.get('kind');
    return db.accounts.filter((a) => !kind || a.kind === kind).sort((a, b) => String(a.name).localeCompare(String(b.name))) as T;
  }
  if (method === 'POST' && (p = match(['accounts']))) {
    const id = nextId('accounts');
    const row = { id, kind: 'vendor', inactive: 0, currency: 'INR', ...(body as object) };
    db.accounts.push(row);
    return row as T;
  }
  if (method === 'GET' && (p = match(['materials']))) return db.materials.slice().sort((a, b) => String(a.name).localeCompare(String(b.name))) as T;
  if (method === 'POST' && (p = match(['materials']))) {
    const id = nextId('materials');
    const row = { id, inactive: 0, gst_percent: 18, reorder_level: 0, ...(body as object) };
    db.materials.push(row);
    return row as T;
  }

  if (method === 'GET' && (p = match(['purchase-indents', 'next-number']))) return { indent_no: nextDocNumber('purchase_indents', 'indent_no', 'IND') } as T;
  if (method === 'GET' && (p = match(['purchase-indents']))) return listIndents(query.get('status') ?? undefined) as T;
  if (method === 'GET' && (p = match(['purchase-indents', ':id']))) return loadIndent(Number(p.id)) as T;
  if (method === 'POST' && (p = match(['purchase-indents']))) return createIndent(body) as T;
  if (method === 'PUT' && (p = match(['purchase-indents', ':id']))) return updateIndent(Number(p.id), body) as T;

  if (method === 'GET' && (p = match(['sanction-indents', 'next-number']))) return { doc_no: nextDocNumber('sanction_indents', 'doc_no', 'SI') } as T;
  if (method === 'GET' && (p = match(['sanction-indents']))) return listSanctions() as T;
  if (method === 'GET' && (p = match(['sanction-indents', ':id']))) return loadSanction(Number(p.id)) as T;
  if (method === 'POST' && (p = match(['sanction-indents']))) return createSanction(body) as T;
  if (method === 'PUT' && (p = match(['sanction-indents', ':id']))) return updateSanction(Number(p.id), body) as T;

  if (method === 'GET' && (p = match(['rfqs']))) return listRfqs() as T;
  if (method === 'GET' && (p = match(['rfqs', ':id']))) return loadRfq(Number(p.id)) as T;
  if (method === 'POST' && (p = match(['rfqs']))) return createRfq(body) as T;

  if (method === 'GET' && (p = match(['purchase-quotations', 'next-number']))) return { doc_no: nextDocNumber('purchase_quotations', 'doc_no', 'PQ') } as T;
  if (method === 'GET' && (p = match(['purchase-quotations', 'compare', ':rfqId']))) return compareQuotations(Number(p.rfqId)) as T;
  if (method === 'GET' && (p = match(['purchase-quotations']))) return listQuotations(query.get('rfq_id') ?? undefined) as T;
  if (method === 'POST' && (p = match(['purchase-quotations']))) return createQuotation(body) as T;

  if (method === 'GET' && (p = match(['purchase-orders', 'next-number']))) return { doc_no: nextDocNumber('purchase_orders', 'doc_no', 'PO') } as T;
  if (method === 'GET' && (p = match(['purchase-orders']))) return listPos(query.get('status') ?? undefined, query.get('vendor_id') ?? undefined) as T;
  if (method === 'GET' && (p = match(['purchase-orders', ':id']))) return loadPo(Number(p.id)) as T;
  if (method === 'POST' && (p = match(['purchase-orders']))) return createPo(body) as T;

  if (method === 'GET' && (p = match(['grns', 'next-number']))) return { grn_no: nextDocNumber('grns', 'grn_no', 'GRN') } as T;
  if (method === 'GET' && (p = match(['grns']))) return listGrns(query.get('po_id') ?? undefined) as T;
  if (method === 'GET' && (p = match(['grns', ':id']))) return loadGrn(Number(p.id)) as T;
  if (method === 'POST' && (p = match(['grns']))) return createGrn(body) as T;

  if (method === 'GET' && (p = match(['reports', 'dashboard']))) return reportDashboard() as T;
  if (method === 'GET' && (p = match(['reports', 'indent-vs-po']))) {
    return reportIndentVsPo(query.get('from') ?? '2000-01-01', query.get('to') ?? '2100-01-01', query.get('only_pending') === 'true') as T;
  }
  if (method === 'GET' && (p = match(['reports', 'material-rate-trend']))) return reportRateTrend(query.get('material_type') ?? undefined) as T;
  if (method === 'GET' && (p = match(['reports', 'vendor-performance']))) return reportVendorPerformance() as T;

  throw new Error(`Preview mode: no static handler for ${method} ${fullPath}`);
}
