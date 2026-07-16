import { Link } from 'react-router-dom';
import { useApiData } from '../../lib/hooks';
import { KpiCard, money } from '../../components/ui';
import type { DashboardKpis } from '../../lib/types';

export function Dashboard() {
  const { data, loading, error } = useApiData<DashboardKpis>('/reports/dashboard');

  if (loading) return <div style={{ color: 'var(--td-text-muted)', fontSize: 13 }}>Loading dashboard…</div>;
  if (error) return <div style={{ color: 'var(--td-red)', fontSize: 13 }}>Failed to load dashboard: {error}</div>;
  if (!data) return null;

  return (
    <div>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(6,1fr)', gap: 14, marginBottom: 22 }}>
        <KpiCard label="Open Indents" value={data.openIndents} tag={`${data.pendingSanction} awaiting sanction`} tagColor="var(--td-amber)" />
        <KpiCard label="Open Purchase Orders" value={data.openPOs} tag="issued / partially received" tagColor="var(--td-blue)" />
        <KpiCard label="GRNs this month" value={data.grnsThisMonth} />
        <KpiCard label="Active vendors" value={data.activeVendors} />
        <KpiCard label="PO value this month" value={money(data.poValueThisMonth)} tagColor="var(--td-green)" />
        <KpiCard label="Pending Sanction" value={data.pendingSanction} tag="indents not yet sanctioned" tagColor="var(--td-amber)" />
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3,1fr)', gap: 16 }}>
        <QuickLink to="/purchase/indents/new" title="Raise Purchase Indent" desc="Request material for a department" />
        <QuickLink to="/purchase/sanction-indents/new" title="Sanction an Indent" desc="Approve quantities before purchasing" />
        <QuickLink to="/purchase/purchase-orders/new" title="Create Purchase Order" desc="Issue a PO to a vendor" />
        <QuickLink to="/purchase/grns/new" title="Record GRN" desc="Log goods received against a PO" />
        <QuickLink to="/purchase/reports" title="Indent vs PO Report" desc="See what's sanctioned but not yet received" />
        <QuickLink to="/purchase/reports" title="Material Rate Trend" desc="Monthly average landed rate per material" />
      </div>
    </div>
  );
}

function QuickLink({ to, title, desc }: { to: string; title: string; desc: string }) {
  return (
    <Link
      to={to}
      style={{ display: 'block', background: '#fff', border: '1px solid var(--td-border)', borderRadius: 6, padding: 16, color: 'var(--td-text)' }}
    >
      <div style={{ fontSize: 13, fontWeight: 700 }}>{title}</div>
      <div style={{ fontSize: 11.5, color: 'var(--td-text-muted)', marginTop: 4 }}>{desc}</div>
    </Link>
  );
}
