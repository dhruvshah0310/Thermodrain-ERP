export interface Department {
  id: number;
  name: string;
  alias?: string | null;
  code?: string | null;
  inactive: number;
}

export interface Unit {
  id: number;
  name: string;
  conversion_factor: number;
  notes?: string | null;
}

export interface Account {
  id: number;
  kind: 'vendor' | 'transporter' | 'freight_forwarder' | 'customer' | 'other';
  name: string;
  alias?: string | null;
  code?: string | null;
  group_name?: string | null;
  office_address1?: string | null;
  office_address2?: string | null;
  office_address3?: string | null;
  city?: string | null;
  state?: string | null;
  country?: string | null;
  pincode?: string | null;
  telephone?: string | null;
  mobile_no?: string | null;
  email?: string | null;
  website?: string | null;
  gst_no?: string | null;
  pan_no?: string | null;
  currency?: string | null;
  cr_days?: number | null;
  credit_limit?: number | null;
  inactive: number;
}

export interface Material {
  id: number;
  code: string;
  name: string;
  hsn_no?: string | null;
  unit_id?: number | null;
  material_type?: string | null;
  group_head?: string | null;
  sub_group?: string | null;
  gst_percent: number;
  reorder_level: number;
  inactive: number;
}

export interface IndentItem {
  id?: number;
  material_id: number;
  material_code?: string;
  material_name?: string;
  unit?: string;
  req_qty: number;
  remark?: string;
}
export interface Indent {
  id: number;
  indent_no: string;
  indent_date: string;
  department_id: number;
  department_name?: string;
  narration?: string | null;
  status: 'open' | 'sanctioned' | 'closed' | 'cancelled';
  item_count?: number;
  items?: IndentItem[];
}

export interface SanctionItem {
  id?: number;
  material_id: number;
  material_code?: string;
  material_name?: string;
  hsn_no?: string;
  unit?: string;
  qty: number;
  remark?: string;
}
export interface SanctionIndent {
  id: number;
  doc_no: string;
  doc_date: string;
  department_id: number;
  department_name?: string;
  indent_id?: number | null;
  indent_no?: string;
  narration?: string | null;
  purchase_order_linked: number;
  default_printing?: string | null;
  item_count?: number;
  items?: SanctionItem[];
  total_qty?: number;
}

export interface Rfq {
  id: number;
  doc_no: string;
  doc_date: string;
  department_id: number;
  department_name?: string;
  sanction_id?: number | null;
  sanction_doc_no?: string;
  narration?: string | null;
  vendor_count?: number;
  quotations_received?: number;
  vendors?: { id: number; name: string }[];
  items?: { material_id: number; material_name?: string; unit?: string; qty: number }[];
}

export interface QuotationItem {
  id?: number;
  material_id: number;
  material_code?: string;
  material_name?: string;
  description?: string;
  unit?: string;
  qty: number;
  rate: number;
  amount?: number;
}
export interface Quotation {
  id: number;
  doc_no: string;
  doc_date: string;
  vendor_id: number;
  vendor_name?: string;
  rfq_id?: number | null;
  rfq_no?: string | null;
  rfq_date?: string | null;
  department_id?: number | null;
  narration?: string | null;
  delivery_terms?: string | null;
  total_qty: number;
  total_amt: number;
  items?: QuotationItem[];
}

export interface PoItem {
  id?: number;
  material_id: number;
  material_code?: string;
  material_name?: string;
  tax_name?: string;
  hsn_no?: string;
  description?: string;
  delivery_date?: string;
  unit?: string;
  qty: number;
  rate: number;
  amount?: number;
  received_qty?: number;
}
export interface PurchaseOrder {
  id: number;
  doc_no: string;
  doc_date: string;
  vendor_id: number;
  vendor_name?: string;
  department_id?: number | null;
  department_name?: string;
  delivery_terms?: string | null;
  del_days?: number | null;
  del_date?: string | null;
  sanction_id?: number | null;
  sanction_doc_no?: string;
  si_date?: string | null;
  transport?: string | null;
  payment_terms?: string | null;
  narration?: string | null;
  quotation_id?: number | null;
  quotation_doc_no?: string;
  pq_date?: string | null;
  consignee?: string | null;
  cgst: number;
  sgst: number;
  igst: number;
  freight: number;
  other_charge: number;
  discount_amt: number;
  round_off: number;
  tax_amt: number;
  total_qty: number;
  total_amt: number;
  gross_amt: number;
  assessable_amt: number;
  status: 'draft' | 'issued' | 'partially_received' | 'received' | 'closed' | 'cancelled';
  ordered_qty?: number;
  received_qty?: number;
  items?: PoItem[];
  grns?: { id: number; grn_no: string; grn_date: string; receive_status: string }[];
}

export interface GrnItem {
  id?: number;
  po_item_id: number;
  material_id: number;
  material_code?: string;
  material_name?: string;
  receive_qty: number;
  rate: number;
  basic_receive_amount?: number;
  freight_gst_recd_basic_amount?: number;
  landed_rate?: number;
}
export interface Grn {
  id: number;
  grn_no: string;
  grn_date: string;
  po_id: number;
  po_doc_no?: string;
  vendor_name?: string;
  bill_no?: string | null;
  bill_date?: string | null;
  challan_no?: string | null;
  challan_date?: string | null;
  receive_status: 'RECEIVED' | 'HOLD' | 'CANCEL' | 'NOT';
  receive_date?: string | null;
  items?: GrnItem[];
}

export interface DashboardKpis {
  openIndents: number;
  pendingSanction: number;
  openPOs: number;
  grnsThisMonth: number;
  activeVendors: number;
  poValueThisMonth: number;
}
