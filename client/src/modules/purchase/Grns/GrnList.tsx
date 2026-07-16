import { Link, useNavigate } from 'react-router-dom';
import { useApiData } from '../../../lib/hooks';
import { Badge, Button, Card, DataTable, type Column } from '../../../components/ui';
import type { Grn } from '../../../lib/types';

export function GrnList() {
  const { data, loading } = useApiData<Grn[]>('/grns');
  const navigate = useNavigate();

  const columns: Column<Grn>[] = [
    { key: 'grn_no', label: 'GRN No.', render: (r) => <Link to={`/purchase/grns/${r.id}`}>{r.grn_no}</Link> },
    { key: 'grn_date', label: 'Date' },
    { key: 'po_doc_no', label: 'PO No.' },
    { key: 'vendor_name', label: 'Vendor' },
    { key: 'bill_no', label: 'Bill No.' },
    { key: 'challan_no', label: 'Challan No.' },
    { key: 'receive_status', label: 'Status', render: (r) => <Badge status={r.receive_status}>{r.receive_status}</Badge> },
  ];

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 14 }}>
        <div style={{ fontSize: 15, fontWeight: 700 }}>Goods Receipt Notes (GRN)</div>
        <Button variant="primary" onClick={() => navigate('/purchase/grns/new')}>+ New GRN</Button>
      </div>
      <Card>
        {loading ? <div style={{ padding: 18, fontSize: 12.5, color: 'var(--td-text-muted)' }}>Loading…</div> : <DataTable columns={columns} rows={data ?? []} />}
      </Card>
    </div>
  );
}
