import { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useApiData } from '../../../lib/hooks';
import { Badge, Button, Card, DataTable, money, qty, type Column } from '../../../components/ui';
import type { PurchaseOrder } from '../../../lib/types';

export function PoList() {
  const [status, setStatus] = useState('');
  const { data, loading } = useApiData<PurchaseOrder[]>(`/purchase-orders${status ? `?status=${status}` : ''}`, [status]);
  const navigate = useNavigate();

  const columns: Column<PurchaseOrder>[] = [
    { key: 'doc_no', label: 'PO No.', render: (r) => <Link to={`/purchase/purchase-orders/${r.id}`}>{r.doc_no}</Link> },
    { key: 'doc_date', label: 'Date' },
    { key: 'vendor_name', label: 'Supplier' },
    { key: 'department_name', label: 'Department' },
    { key: 'ordered_qty', label: 'Ordered / Received', render: (r) => `${qty(r.ordered_qty)} / ${qty(r.received_qty)}` },
    { key: 'total_amt', label: 'Total Amt', align: 'right', render: (r) => money(r.total_amt) },
    { key: 'status', label: 'Status', render: (r) => <Badge status={r.status}>{r.status.replace('_', ' ')}</Badge> },
  ];

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 14 }}>
        <div style={{ fontSize: 15, fontWeight: 700 }}>Purchase Orders</div>
        <div style={{ display: 'flex', gap: 8 }}>
          <select value={status} onChange={(e) => setStatus(e.target.value)}>
            <option value="">All statuses</option>
            <option value="issued">Issued</option>
            <option value="partially_received">Partially received</option>
            <option value="received">Received</option>
            <option value="closed">Closed</option>
          </select>
          <Button variant="primary" onClick={() => navigate('/purchase/purchase-orders/new')}>+ New Purchase Order</Button>
        </div>
      </div>
      <Card>
        {loading ? <div style={{ padding: 18, fontSize: 12.5, color: 'var(--td-text-muted)' }}>Loading…</div> : <DataTable columns={columns} rows={data ?? []} />}
      </Card>
    </div>
  );
}
