-- Thermodrain ERP — core schema.
--
-- Scope for this pass: masters + the Purchase department's full document
-- lifecycle (Indent -> Sanction -> RFQ -> Quotation -> Purchase Order -> GRN),
-- plus the logistics-cost logs that lived in the Purchase Excel sheet.
-- Other departments (Marketing, Quotation, Work Order, Inventory, Production,
-- QC, Logistics, sales Purchase Order) are UI-only in this pass — see
-- server/README.md for how their tables get added here later without
-- disturbing this schema.

PRAGMA foreign_keys = ON;

-- ---------- Masters ----------

CREATE TABLE IF NOT EXISTS departments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE,
  alias TEXT,
  code TEXT,
  inactive INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS units (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE,
  conversion_factor REAL NOT NULL DEFAULT 1,
  notes TEXT
);

-- Unified party master (mirrors the legacy "Account Master" screen, which is
-- one form used for vendors, transporters, freight forwarders and customers
-- alike, distinguished by kind).
CREATE TABLE IF NOT EXISTS accounts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  kind TEXT NOT NULL DEFAULT 'vendor' CHECK (kind IN ('vendor','transporter','freight_forwarder','customer','other')),
  name TEXT NOT NULL,
  alias TEXT,
  code TEXT,
  group_name TEXT,
  office_address1 TEXT,
  office_address2 TEXT,
  office_address3 TEXT,
  city TEXT,
  state TEXT,
  country TEXT,
  pincode TEXT,
  area TEXT,
  telephone TEXT,
  mobile_no TEXT,
  email TEXT,
  website TEXT,
  gst_no TEXT,
  pan_no TEXT,
  drug_licence TEXT,
  currency TEXT DEFAULT 'INR',
  cr_days INTEGER DEFAULT 0,
  credit_limit REAL DEFAULT 0,
  tax_type TEXT,
  tcs_percent REAL DEFAULT 0,
  business_type TEXT,
  opening_balance REAL DEFAULT 0,
  closing_balance REAL DEFAULT 0,
  inactive INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_accounts_kind ON accounts(kind);
CREATE INDEX IF NOT EXISTS idx_accounts_name ON accounts(name);

-- Known (material_type, group_head, sub_group) combinations, seeded from the
-- historical Excel so the Indent/PO forms can offer autocomplete instead of
-- 200+ free-text sub-groups typed from scratch. Not a hard FK from materials
-- — the legacy data has too much drift for that to be honest.
CREATE TABLE IF NOT EXISTS material_taxonomy (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  material_type TEXT NOT NULL,
  group_head TEXT,
  sub_group TEXT,
  UNIQUE (material_type, group_head, sub_group)
);

CREATE TABLE IF NOT EXISTS materials (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  code TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  hsn_no TEXT,
  unit_id INTEGER REFERENCES units(id),
  material_type TEXT,
  group_head TEXT,
  sub_group TEXT,
  gst_percent REAL DEFAULT 18,
  reorder_level REAL DEFAULT 0,
  inactive INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_materials_name ON materials(name);
CREATE INDEX IF NOT EXISTS idx_materials_type ON materials(material_type);

-- ---------- Purchase Indent (department raw request) ----------

CREATE TABLE IF NOT EXISTS purchase_indents (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  indent_no TEXT NOT NULL UNIQUE,
  indent_date TEXT NOT NULL,
  department_id INTEGER REFERENCES departments(id),
  narration TEXT,
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','sanctioned','closed','cancelled')),
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS purchase_indent_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  indent_id INTEGER NOT NULL REFERENCES purchase_indents(id) ON DELETE CASCADE,
  sr_no INTEGER NOT NULL,
  material_id INTEGER REFERENCES materials(id),
  unit TEXT,
  req_qty REAL NOT NULL DEFAULT 0,
  remark TEXT
);
CREATE INDEX IF NOT EXISTS idx_indent_items_indent ON purchase_indent_items(indent_id);

-- ---------- Sanction Indent (approval step, sets accepted qty) ----------

CREATE TABLE IF NOT EXISTS sanction_indents (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  doc_no TEXT NOT NULL UNIQUE,
  doc_date TEXT NOT NULL,
  department_id INTEGER REFERENCES departments(id),
  indent_id INTEGER REFERENCES purchase_indents(id),
  narration TEXT,
  purchase_order_linked INTEGER NOT NULL DEFAULT 0,
  default_printing TEXT DEFAULT 'Sanction Indent',
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS sanction_indent_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  sanction_id INTEGER NOT NULL REFERENCES sanction_indents(id) ON DELETE CASCADE,
  sr_no INTEGER NOT NULL,
  material_id INTEGER REFERENCES materials(id),
  hsn_no TEXT,
  unit TEXT,
  qty REAL NOT NULL DEFAULT 0,
  remark TEXT
);
CREATE INDEX IF NOT EXISTS idx_sanction_items_sanction ON sanction_indent_items(sanction_id);

-- ---------- Request for Quote ----------

CREATE TABLE IF NOT EXISTS rfqs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  doc_no TEXT NOT NULL UNIQUE,
  doc_date TEXT NOT NULL,
  department_id INTEGER REFERENCES departments(id),
  sanction_id INTEGER REFERENCES sanction_indents(id),
  narration TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS rfq_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  rfq_id INTEGER NOT NULL REFERENCES rfqs(id) ON DELETE CASCADE,
  sr_no INTEGER NOT NULL,
  material_id INTEGER REFERENCES materials(id),
  unit TEXT,
  qty REAL NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS rfq_vendors (
  rfq_id INTEGER NOT NULL REFERENCES rfqs(id) ON DELETE CASCADE,
  account_id INTEGER NOT NULL REFERENCES accounts(id),
  PRIMARY KEY (rfq_id, account_id)
);

-- ---------- Purchase Quotation (vendor's response to an RFQ) ----------

CREATE TABLE IF NOT EXISTS purchase_quotations (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  doc_no TEXT NOT NULL UNIQUE,
  doc_date TEXT NOT NULL,
  vendor_id INTEGER REFERENCES accounts(id),
  rfq_id INTEGER REFERENCES rfqs(id),
  rfq_no TEXT,
  rfq_date TEXT,
  department_id INTEGER REFERENCES departments(id),
  narration TEXT,
  delivery_terms TEXT,
  default_printing TEXT,
  total_qty REAL DEFAULT 0,
  total_amt REAL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS purchase_quotation_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  quotation_id INTEGER NOT NULL REFERENCES purchase_quotations(id) ON DELETE CASCADE,
  sr_no INTEGER NOT NULL,
  material_id INTEGER REFERENCES materials(id),
  description TEXT,
  unit TEXT,
  qty REAL NOT NULL DEFAULT 0,
  rate REAL NOT NULL DEFAULT 0,
  amount REAL NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_quotation_items_quotation ON purchase_quotation_items(quotation_id);

-- ---------- Purchase Order ----------

CREATE TABLE IF NOT EXISTS purchase_orders (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  doc_no TEXT NOT NULL UNIQUE,
  doc_date TEXT NOT NULL,
  vendor_id INTEGER REFERENCES accounts(id),
  department_id INTEGER REFERENCES departments(id),
  delivery_terms TEXT,
  del_days INTEGER,
  del_date TEXT,
  sanction_id INTEGER REFERENCES sanction_indents(id),
  si_date TEXT,
  transport TEXT,
  payment_terms TEXT,
  narration TEXT,
  quotation_id INTEGER REFERENCES purchase_quotations(id),
  pq_date TEXT,
  consignee TEXT,
  default_printing TEXT,
  cgst REAL DEFAULT 0,
  sgst REAL DEFAULT 0,
  igst REAL DEFAULT 0,
  freight REAL DEFAULT 0,
  other_charge REAL DEFAULT 0,
  discount_amt REAL DEFAULT 0,
  round_off REAL DEFAULT 0,
  tax_amt REAL DEFAULT 0,
  total_qty REAL DEFAULT 0,
  total_amt REAL DEFAULT 0,
  gross_amt REAL DEFAULT 0,
  assessable_amt REAL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'issued' CHECK (status IN ('draft','issued','partially_received','received','closed','cancelled')),
  bill_no TEXT,
  bill_date TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_po_vendor ON purchase_orders(vendor_id);
CREATE INDEX IF NOT EXISTS idx_po_sanction ON purchase_orders(sanction_id);
CREATE INDEX IF NOT EXISTS idx_po_status ON purchase_orders(status);

CREATE TABLE IF NOT EXISTS purchase_order_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  po_id INTEGER NOT NULL REFERENCES purchase_orders(id) ON DELETE CASCADE,
  sr_no INTEGER NOT NULL,
  material_id INTEGER REFERENCES materials(id),
  tax_name TEXT,
  hsn_no TEXT,
  description TEXT,
  delivery_date TEXT,
  unit TEXT,
  qty REAL NOT NULL DEFAULT 0,
  rate REAL NOT NULL DEFAULT 0,
  amount REAL NOT NULL DEFAULT 0,
  received_qty REAL NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_po_items_po ON purchase_order_items(po_id);
CREATE INDEX IF NOT EXISTS idx_po_items_material ON purchase_order_items(material_id);

-- ---------- GRN (Goods Receipt Note) ----------

CREATE TABLE IF NOT EXISTS grns (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  grn_no TEXT NOT NULL UNIQUE,
  grn_date TEXT NOT NULL,
  po_id INTEGER REFERENCES purchase_orders(id),
  bill_no TEXT,
  bill_date TEXT,
  challan_no TEXT,
  challan_date TEXT,
  receive_status TEXT NOT NULL DEFAULT 'RECEIVED' CHECK (receive_status IN ('RECEIVED','HOLD','CANCEL','NOT')),
  receive_date TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_grns_po ON grns(po_id);

CREATE TABLE IF NOT EXISTS grn_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  grn_id INTEGER NOT NULL REFERENCES grns(id) ON DELETE CASCADE,
  po_item_id INTEGER REFERENCES purchase_order_items(id),
  material_id INTEGER REFERENCES materials(id),
  receive_qty REAL NOT NULL DEFAULT 0,
  rate REAL NOT NULL DEFAULT 0,
  basic_receive_amount REAL NOT NULL DEFAULT 0,
  freight_gst_recd_basic_amount REAL NOT NULL DEFAULT 0,
  landed_rate REAL NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_grn_items_grn ON grn_items(grn_id);

-- ---------- Inbound logistics logs (from the Excel "TRANSPORT" / "EXPORT" sheets) ----------

CREATE TABLE IF NOT EXISTS transport_entries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  service TEXT, -- TRAIN / DIRECT / etc.
  entry_month TEXT,
  transporter_id INTEGER REFERENCES accounts(id),
  bill_no TEXT,
  lr_no TEXT,
  lr_date TEXT,
  client_destination TEXT,
  total_point INTEGER DEFAULT 1,
  client_name TEXT,
  invoice_no TEXT,
  material_type TEXT,
  material_qty_box REAL DEFAULT 0,
  weight_kg REAL DEFAULT 0,
  rate_per_kg REAL DEFAULT 0,
  terminal_charges REAL DEFAULT 0,
  basic_amount REAL DEFAULT 0,
  gst_percent REAL DEFAULT 0,
  gst_amount REAL DEFAULT 0,
  total_amount REAL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS export_entries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  cargo_type_service TEXT, -- SEA / AIR
  fiscal_year TEXT,
  entry_month TEXT,
  freight_forwarder_id INTEGER REFERENCES accounts(id),
  po_no TEXT,
  po_date TEXT,
  client_name TEXT,
  port_country TEXT,
  cargo_type TEXT, -- 20FT/40FT/LCL
  packing_no TEXT,
  invoice_no TEXT,
  bill_no TEXT,
  bill_date TEXT,
  work_order_no TEXT,
  pallet_count REAL DEFAULT 0,
  weight_kg REAL DEFAULT 0,
  cbm REAL DEFAULT 0,
  basic_amount REAL DEFAULT 0,
  amount_with_gst REAL DEFAULT 0
);

-- ---------- Users (simple role login, mirrors the design's click-to-login) ----------

CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  role TEXT NOT NULL
);
