import { Link, useNavigate } from 'react-router-dom';
import { useApiData } from '../../../lib/hooks';
import { Button, Card, DataTable, money, type Column } from '../../../components/ui';
import type { Quotation } from '../../../lib/types';

export function QuotationList() {
  const { data, loading } = useApiData<Quotation[]>('/purchase-quotations');
  const navigate = useNavigate();

  const columns: Column<Quotation>[] = [
    { key: 'doc_no', label: 'Doc No.', render: (r) => <Link to={`/purchase/purchase-orders/new?quotation_id=${r.id}`}>{r.doc_no}</Link> },
    { key: 'doc_date', label: 'Date' },
    { key: 'vendor_name', label: 'Vendor' },
    { key: 'rfq_no', label: 'RFQ No.' },
    { key: 'total_qty', label: 'Total Qty', align: 'right' },
    { key: 'total_amt', label: 'Total Amt', align: 'right', render: (r) => money(r.total_amt) },
  ];

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 14 }}>
        <div style={{ fontSize: 15, fontWeight: 700 }}>Purchase Quotations</div>
        <Button variant="primary" onClick={() => navigate('/purchase/quotations/new')}>+ New Quotation</Button>
      </div>
      <Card>
        {loading ? <div style={{ padding: 18, fontSize: 12.5, color: 'var(--td-text-muted)' }}>Loading…</div> : <DataTable columns={columns} rows={data ?? []} emptyMessage="No quotations yet. Click a doc no. to create a PO from it once you have one." />}
      </Card>
    </div>
  );
}
