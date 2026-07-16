import { Link, useNavigate } from 'react-router-dom';
import { useApiData } from '../../../lib/hooks';
import { Badge, Button, Card, DataTable, type Column } from '../../../components/ui';
import type { Indent } from '../../../lib/types';

export function IndentList() {
  const { data, loading } = useApiData<Indent[]>('/purchase-indents');
  const navigate = useNavigate();

  const columns: Column<Indent>[] = [
    { key: 'indent_no', label: 'Indent No.', render: (r) => <Link to={`/purchase/indents/${r.id}`}>{r.indent_no}</Link> },
    { key: 'indent_date', label: 'Date' },
    { key: 'department_name', label: 'Department' },
    { key: 'item_count', label: 'Lines', align: 'right' },
    { key: 'narration', label: 'Narration' },
    { key: 'status', label: 'Status', render: (r) => <Badge status={r.status}>{r.status}</Badge> },
  ];

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 14 }}>
        <div style={{ fontSize: 15, fontWeight: 700 }}>Purchase Indents</div>
        <Button variant="primary" onClick={() => navigate('/purchase/indents/new')}>+ New Indent</Button>
      </div>
      <Card>
        {loading ? <div style={{ padding: 18, fontSize: 12.5, color: 'var(--td-text-muted)' }}>Loading…</div> : <DataTable columns={columns} rows={data ?? []} />}
      </Card>
    </div>
  );
}
