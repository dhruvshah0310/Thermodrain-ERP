import { useState } from 'react';
import { useApiData } from '../../../lib/hooks';
import { Card, DataTable, money, qty, type Column } from '../../../components/ui';

interface IndentVsPoRow {
  sanction_doc_no: string; sanction_date: string; po_doc_no?: string; po_date?: string;
  supplier_name?: string; material_code?: string; material_name?: string; group_name?: string;
  indent_qty: number; po_received_qty: number; rate: number; amount: number; balance_qty: number;
}
interface RateTrendRow {
  month: string; material_type: string; material_id: number; material_name: string;
  total_qty: number; total_value: number; avg_rate: number;
}
interface VendorPerfRow {
  vendor_id: number; vendor_name: string; po_count: number; total_spend: number; received_count: number;
}

const TABS = ['Indent vs PO', 'Material Rate Trend', 'Vendor Performance'] as const;

export function Reports() {
  const [tab, setTab] = useState<(typeof TABS)[number]>('Indent vs PO');
  return (
    <div>
      <div style={{ display: 'flex', gap: 8, marginBottom: 16 }}>
        {TABS.map((t) => (
          <button
            key={t}
            onClick={() => setTab(t)}
            style={{
              padding: '8px 14px', borderRadius: 20, fontSize: 12.5, fontWeight: 700, cursor: 'pointer',
              border: '1px solid var(--td-border)',
              background: tab === t ? 'var(--td-accent)' : '#fff',
              color: tab === t ? '#fff' : 'var(--td-text)',
            }}
          >
            {t}
          </button>
        ))}
      </div>
      {tab === 'Indent vs PO' && <IndentVsPo />}
      {tab === 'Material Rate Trend' && <RateTrend />}
      {tab === 'Vendor Performance' && <VendorPerformance />}
    </div>
  );
}

function IndentVsPo() {
  const [onlyPending, setOnlyPending] = useState(false);
  const { data, loading } = useApiData<IndentVsPoRow[]>(`/reports/indent-vs-po${onlyPending ? '?only_pending=true' : ''}`, [onlyPending]);

  const columns: Column<IndentVsPoRow & { id: number }>[] = [
    { key: 'sanction_doc_no', label: 'Sanction Indent' },
    { key: 'po_doc_no', label: 'PO No.' },
    { key: 'supplier_name', label: 'Supplier' },
    { key: 'material_name', label: 'Material' },
    { key: 'group_name', label: 'Group' },
    { key: 'indent_qty', label: 'Indent Qty', align: 'right', render: (r) => qty(r.indent_qty) },
    { key: 'po_received_qty', label: 'PO Received Qty', align: 'right', render: (r) => qty(r.po_received_qty) },
    { key: 'rate', label: 'Rate', align: 'right', render: (r) => money(r.rate) },
    { key: 'balance_qty', label: 'Balance Qty', align: 'right', render: (r) => (
      <span style={{ fontWeight: 700, color: r.balance_qty > 0 ? 'var(--td-red)' : 'var(--td-green)' }}>{qty(r.balance_qty)}</span>
    ) },
  ];

  return (
    <Card title="Sanction Indent vs Purchase Order" actions={
      <label style={{ fontSize: 12, display: 'flex', alignItems: 'center', gap: 6 }}>
        <input type="checkbox" checked={onlyPending} onChange={(e) => setOnlyPending(e.target.checked)} /> Only pending
      </label>
    }>
      {loading ? <div style={{ padding: 18, fontSize: 12.5, color: 'var(--td-text-muted)' }}>Loading…</div> :
        <DataTable columns={columns} rows={(data ?? []).map((r, i) => ({ ...r, id: i }))} />}
    </Card>
  );
}

function RateTrend() {
  const { data, loading } = useApiData<RateTrendRow[]>('/reports/material-rate-trend');
  const columns: Column<RateTrendRow & { id: number }>[] = [
    { key: 'month', label: 'Month' },
    { key: 'material_type', label: 'Type' },
    { key: 'material_name', label: 'Material' },
    { key: 'total_qty', label: 'Qty', align: 'right', render: (r) => qty(r.total_qty) },
    { key: 'total_value', label: 'Value', align: 'right', render: (r) => money(r.total_value) },
    { key: 'avg_rate', label: 'Avg Landed Rate', align: 'right', render: (r) => money(r.avg_rate) },
  ];
  return (
    <Card title="Monthly average landed rate per material (from GRNs)">
      {loading ? <div style={{ padding: 18, fontSize: 12.5, color: 'var(--td-text-muted)' }}>Loading…</div> :
        <DataTable columns={columns} rows={(data ?? []).map((r, i) => ({ ...r, id: i }))} emptyMessage="No GRNs recorded yet." />}
    </Card>
  );
}

function VendorPerformance() {
  const { data, loading } = useApiData<VendorPerfRow[]>('/reports/vendor-performance');
  const columns: Column<VendorPerfRow>[] = [
    { key: 'vendor_name', label: 'Vendor' },
    { key: 'po_count', label: 'PO Count', align: 'right' },
    { key: 'received_count', label: 'Fully Received', align: 'right' },
    { key: 'total_spend', label: 'Total Spend', align: 'right', render: (r) => money(r.total_spend) },
  ];
  return (
    <Card title="Vendor spend & fulfillment">
      {loading ? <div style={{ padding: 18, fontSize: 12.5, color: 'var(--td-text-muted)' }}>Loading…</div> :
        <DataTable columns={columns} rows={(data ?? []).map((r) => ({ ...r, id: r.vendor_id }))} />}
    </Card>
  );
}
