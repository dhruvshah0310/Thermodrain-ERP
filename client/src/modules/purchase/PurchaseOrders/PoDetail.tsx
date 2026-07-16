import { Link, useNavigate, useParams } from 'react-router-dom';
import { useApiData } from '../../../lib/hooks';
import { Badge, Button, Card, DataTable, money, qty, type Column } from '../../../components/ui';
import type { PoItem, PurchaseOrder } from '../../../lib/types';

export function PoDetail() {
  const { id } = useParams();
  const navigate = useNavigate();
  const { data: po, loading } = useApiData<PurchaseOrder>(`/purchase-orders/${id}`);

  if (loading) return <div style={{ fontSize: 12.5, color: 'var(--td-text-muted)' }}>Loading…</div>;
  if (!po) return <div style={{ fontSize: 12.5, color: 'var(--td-red)' }}>Purchase order not found.</div>;

  const itemColumns: Column<PoItem & { id: number }>[] = [
    { key: 'material_name', label: 'Material' },
    { key: 'hsn_no', label: 'HSN' },
    { key: 'unit', label: 'Unit' },
    { key: 'qty', label: 'Qty', align: 'right', render: (r) => qty(r.qty) },
    { key: 'received_qty', label: 'Received', align: 'right', render: (r) => qty(r.received_qty) },
    { key: 'rate', label: 'Rate', align: 'right', render: (r) => money(r.rate) },
    { key: 'amount', label: 'Amount', align: 'right', render: (r) => money(r.amount) },
  ];

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 14 }}>
        <div>
          <div style={{ fontSize: 15, fontWeight: 700 }}>Purchase Order {po.doc_no}</div>
          <div style={{ fontSize: 12, color: 'var(--td-text-secondary)', marginTop: 2 }}>
            {po.vendor_name} · {po.doc_date} · <Badge status={po.status}>{po.status.replace('_', ' ')}</Badge>
          </div>
        </div>
        <Link to={`/purchase/grns/new?po_id=${po.id}`}>
          <Button variant="primary">+ Record GRN</Button>
        </Link>
      </div>

      <Card style={{ padding: 18, marginBottom: 16 }}>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4,1fr)', gap: 14, fontSize: 12.5 }}>
          <Info label="Department" value={po.department_name} />
          <Info label="Delivery Terms" value={po.delivery_terms} />
          <Info label="Del Date" value={po.del_date} />
          <Info label="Sanction Indent" value={po.sanction_doc_no} />
          <Info label="Transport" value={po.transport} />
          <Info label="Payment Terms" value={po.payment_terms} />
          <Info label="Consignee" value={po.consignee} />
          <Info label="Narration" value={po.narration} />
        </div>
      </Card>

      <Card style={{ marginBottom: 16 }}>
        <DataTable columns={itemColumns} rows={(po.items ?? []).map((it, i) => ({ ...it, id: it.id ?? i }))} />
      </Card>

      <Card style={{ padding: 18, marginBottom: 16 }}>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4,1fr)', gap: 10, fontSize: 12.5 }}>
          <Info label="CGST" value={money(po.cgst)} />
          <Info label="SGST" value={money(po.sgst)} />
          <Info label="IGST" value={money(po.igst)} />
          <Info label="Tax Amt" value={money(po.tax_amt)} />
          <Info label="Freight" value={money(po.freight)} />
          <Info label="Other Charge" value={money(po.other_charge)} />
          <Info label="Discount" value={money(po.discount_amt)} />
          <Info label="Round Off" value={money(po.round_off)} />
        </div>
        <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 24, marginTop: 16, fontSize: 13 }}>
          <div>Total Qty: <b>{qty(po.total_qty)}</b></div>
          <div>Assessable Amt: <b>{money(po.assessable_amt)}</b></div>
          <div>Gross Amt: <b>{money(po.gross_amt)}</b></div>
          <div>Total Amt: <b>{money(po.total_amt)}</b></div>
        </div>
      </Card>

      {po.grns && po.grns.length > 0 && (
        <Card title="GRNs against this PO">
          <DataTable
            columns={[
              { key: 'grn_no', label: 'GRN No.', render: (r) => <Link to={`/purchase/grns/${r.id}`}>{r.grn_no}</Link> },
              { key: 'grn_date', label: 'Date' },
              { key: 'receive_status', label: 'Status', render: (r) => <Badge status={r.receive_status}>{r.receive_status}</Badge> },
            ]}
            rows={po.grns}
          />
        </Card>
      )}

      <div style={{ marginTop: 16 }}>
        <Button onClick={() => navigate('/purchase/purchase-orders')}>Back to Purchase Orders</Button>
      </div>
    </div>
  );
}

function Info({ label, value }: { label: string; value?: string | number | null }) {
  return (
    <div>
      <div style={{ fontSize: 10.5, color: 'var(--td-text-muted)', textTransform: 'uppercase', fontWeight: 700 }}>{label}</div>
      <div style={{ marginTop: 2 }}>{value || '—'}</div>
    </div>
  );
}
