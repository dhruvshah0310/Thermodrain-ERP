import { KpiCard } from '../../components/ui';

const KPIS = [
  { label: 'New leads (7d)', value: '18', tag: '+4 vs last wk', tagColor: 'var(--td-green)' },
  { label: 'Quotations pending', value: '6', tag: '2 awaiting client', tagColor: 'var(--td-amber)' },
  { label: 'Active work orders', value: '11', tag: '3 in QC', tagColor: 'var(--td-blue)' },
  { label: 'Low stock alerts', value: '2', tag: 'Ferro Silicon, Sand', tagColor: 'var(--td-red)' },
  { label: 'QC rejection rate', value: '9%', tag: 'last 30 days', tagColor: 'var(--td-gray)' },
  { label: 'Dispatches today', value: '3', tag: '1 in transit', tagColor: 'var(--td-blue)' },
];

const FLOW_STEPS = ['Lead', 'Quotation', 'Client PO', 'Work Order', 'Indent', 'Procurement', 'Production', 'QC', 'Dispatch'];

const NOTIFICATIONS = [
  { text: 'New lead LD-241 assigned to A. Kumar', meta: 'Mobile push · Production Director + Ops Mgr', dot: 'var(--td-accent)' },
  { text: 'Quotation QT-118 sent to client for review', meta: 'Email · All configured recipients', dot: 'var(--td-blue)' },
  { text: 'WO-882 moved to Production', meta: 'Dashboard widget · live update', dot: 'var(--td-green)' },
  { text: 'Inventory shortfall: Ferro Silicon', meta: 'Dashboard widget · Inventory team', dot: 'var(--td-red)' },
];

export function Overview() {
  return (
    <div>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(6,1fr)', gap: 14, marginBottom: 22 }}>
        {KPIS.map((k) => <KpiCard key={k.label} {...k} />)}
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: '1.4fr 1fr', gap: 16 }}>
        <div style={{ background: 'var(--td-surface)', border: '1px solid var(--td-border)', borderRadius: 6, padding: 20 }}>
          <div style={{ fontSize: 13, fontWeight: 700, marginBottom: 12 }}>Workflow at a glance</div>
          <div style={{ display: 'flex', alignItems: 'center' }}>
            {FLOW_STEPS.map((label, i) => (
              <div key={label} style={{ display: 'flex', alignItems: 'center' }}>
                <div style={{ textAlign: 'center' }}>
                  <div style={{ width: 34, height: 34, borderRadius: '50%', background: 'var(--td-bg)', border: '2px solid var(--td-accent)', color: 'var(--td-text)', fontWeight: 800, fontSize: 12, display: 'flex', alignItems: 'center', justifyContent: 'center', margin: '0 auto' }}>
                    {i + 1}
                  </div>
                  <div style={{ fontSize: 9.5, color: 'var(--td-text-secondary)', marginTop: 6, width: 64, fontWeight: 600 }}>{label}</div>
                </div>
                {i < FLOW_STEPS.length - 1 && <div style={{ width: 16, height: 2, background: 'var(--td-border)', marginBottom: 22 }} />}
              </div>
            ))}
          </div>
        </div>
        <div style={{ background: 'var(--td-surface)', border: '1px solid var(--td-border)', borderRadius: 6, padding: 20 }}>
          <div style={{ fontSize: 13, fontWeight: 700, marginBottom: 12 }}>Live notifications</div>
          {NOTIFICATIONS.map((n) => (
            <div key={n.text} style={{ display: 'flex', gap: 10, padding: '9px 0', borderBottom: '1px solid var(--td-divider)' }}>
              <div style={{ width: 6, height: 6, borderRadius: '50%', background: n.dot, marginTop: 5, flexShrink: 0 }} />
              <div>
                <div style={{ fontSize: 12, fontWeight: 600 }}>{n.text}</div>
                <div style={{ fontSize: 10.5, color: '#9a9fa8', marginTop: 1 }}>{n.meta}</div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
