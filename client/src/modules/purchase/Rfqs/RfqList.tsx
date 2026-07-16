import { Link, useNavigate } from 'react-router-dom';
import { useApiData } from '../../../lib/hooks';
import { Button, Card, DataTable, type Column } from '../../../components/ui';
import type { Rfq } from '../../../lib/types';

export function RfqList() {
  const { data, loading } = useApiData<Rfq[]>('/rfqs');
  const navigate = useNavigate();

  const columns: Column<Rfq>[] = [
    { key: 'doc_no', label: 'RFQ No.', render: (r) => <Link to={`/purchase/rfqs/${r.id}`}>{r.doc_no}</Link> },
    { key: 'doc_date', label: 'Date' },
    { key: 'department_name', label: 'Department' },
    { key: 'sanction_doc_no', label: 'Sanction Indent' },
    { key: 'vendor_count', label: 'Vendors Sent', align: 'right' },
    { key: 'quotations_received', label: 'Quotes Received', align: 'right' },
  ];

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 14 }}>
        <div style={{ fontSize: 15, fontWeight: 700 }}>Request for Quote</div>
        <Button variant="primary" onClick={() => navigate('/purchase/rfqs/new')}>+ New RFQ</Button>
      </div>
      <Card>
        {loading ? <div style={{ padding: 18, fontSize: 12.5, color: 'var(--td-text-muted)' }}>Loading…</div> : <DataTable columns={columns} rows={data ?? []} />}
      </Card>
    </div>
  );
}
