import { Link, useNavigate } from 'react-router-dom';
import { useApiData } from '../../../lib/hooks';
import { Button, Card, DataTable, type Column } from '../../../components/ui';
import type { SanctionIndent } from '../../../lib/types';

export function SanctionList() {
  const { data, loading } = useApiData<SanctionIndent[]>('/sanction-indents');
  const navigate = useNavigate();

  const columns: Column<SanctionIndent>[] = [
    { key: 'doc_no', label: 'Doc No.', render: (r) => <Link to={`/purchase/sanction-indents/${r.id}`}>{r.doc_no}</Link> },
    { key: 'doc_date', label: 'Date' },
    { key: 'department_name', label: 'Department' },
    { key: 'indent_no', label: 'Linked Indent' },
    { key: 'item_count', label: 'Lines', align: 'right' },
    { key: 'purchase_order_linked', label: 'PO Linked', render: (r) => (r.purchase_order_linked ? 'Yes' : 'No') },
  ];

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 14 }}>
        <div style={{ fontSize: 15, fontWeight: 700 }}>Sanction Indents</div>
        <Button variant="primary" onClick={() => navigate('/purchase/sanction-indents/new')}>+ New Sanction Indent</Button>
      </div>
      <Card>
        {loading ? <div style={{ padding: 18, fontSize: 12.5, color: 'var(--td-text-muted)' }}>Loading…</div> : <DataTable columns={columns} rows={data ?? []} />}
      </Card>
    </div>
  );
}
