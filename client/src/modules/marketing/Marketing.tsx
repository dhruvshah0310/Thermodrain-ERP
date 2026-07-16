import { useAuth } from '../../state/AuthContext';
import { DataTable, type Column } from '../../components/ui';

const LEADS = [
  { id: 'LD-241', product: 'Heavy Duty MH Cover · MHC-HD-450', client: 'Bengaluru Municipal Corp', region: 'Bengaluru', qty: 500, rep: 'A. Kumar', status: 'New', statusColor: 'var(--td-blue)' },
  { id: 'LD-240', product: 'Standard MH Cover · MHC-STD-300', client: 'Pune Smart City', region: 'Pune', qty: 220, rep: 'S. Rao', status: 'Assigned', statusColor: 'var(--td-amber)' },
  { id: 'LD-239', product: 'Heavy Duty MH Cover · MHC-HD-600', client: 'Chennai Metro Water', region: 'Chennai', qty: 340, rep: 'A. Kumar', status: 'Contacted', statusColor: 'var(--td-green)' },
  { id: 'LD-238', product: 'Light Duty MH Cover · MHC-LD-250', client: 'Hyderabad Municipal', region: 'Hyderabad', qty: 150, rep: 'N. Iyer', status: 'Quoted', statusColor: 'var(--td-gray)' },
];

const LEAD_FORM_FIELDS = [
  { label: 'Product', value: 'Heavy Duty MH Cover' },
  { label: 'Product code', value: 'MHC-HD-450' },
  { label: 'Strength · Colour · Dimension', value: 'C250 · Grey · 600mm' },
  { label: 'Client name', value: 'Bengaluru Municipal Corp' },
  { label: 'Region', value: 'Bengaluru' },
  { label: 'Quantity', value: '500' },
];

const NOTIFICATIONS = [
  { text: 'New lead LD-241 assigned to A. Kumar', meta: 'Mobile push · Production Director + Ops Mgr' },
  { text: 'Quotation QT-118 sent to client for review', meta: 'Email · All configured recipients' },
  { text: 'WO-882 moved to Production', meta: 'Dashboard widget · live update' },
  { text: 'Inventory shortfall: Ferro Silicon', meta: 'Dashboard widget · Inventory team' },
];

function MobileMarketing() {
  return (
    <div style={{ display: 'flex', gap: 24, justifyContent: 'center' }}>
      <div style={{ width: 320, background: 'var(--td-dark)', borderRadius: 32, padding: 12, boxShadow: '0 20px 40px rgba(0,0,0,0.25)' }}>
        <div style={{ background: 'var(--td-bg)', borderRadius: 22, overflow: 'hidden' }}>
          <div style={{ background: 'var(--td-dark)', color: '#fff', padding: '10px 16px 14px', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <div style={{ fontSize: 12, fontWeight: 700 }}>Thermodrain Field</div>
          </div>
          <div style={{ background: 'var(--td-accent)', color: 'var(--td-dark)', padding: '10px 16px', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <div style={{ fontSize: 11, fontWeight: 700 }}>● GPS active — Bengaluru</div>
            <div style={{ fontSize: 10, fontWeight: 700 }}>Checked in 09:14</div>
          </div>
          <div style={{ padding: '14px 16px' }}>
            <div style={{ fontSize: 11.5, fontWeight: 800, textTransform: 'uppercase', letterSpacing: 0.4, marginBottom: 8 }}>New Lead</div>
            <div style={{ background: '#fff', border: '1px solid var(--td-border)', borderRadius: 8, padding: 12, display: 'flex', flexDirection: 'column', gap: 8 }}>
              {LEAD_FORM_FIELDS.map((f) => (
                <div key={f.label}>
                  <div style={{ fontSize: 9.5, color: '#9a9fa8', textTransform: 'uppercase', fontWeight: 700 }}>{f.label}</div>
                  <div style={{ fontSize: 12, fontWeight: 600, borderBottom: '1px solid #eee', paddingBottom: 4 }}>{f.value}</div>
                </div>
              ))}
              <div style={{ background: 'var(--td-accent)', color: 'var(--td-dark)', textAlign: 'center', padding: 9, borderRadius: 6, fontSize: 12, fontWeight: 800, marginTop: 4 }}>
                Submit Lead
              </div>
            </div>
            <div style={{ fontSize: 11.5, fontWeight: 800, textTransform: 'uppercase', letterSpacing: 0.4, margin: '16px 0 8px' }}>My Leads Today</div>
            {LEADS.map((l) => (
              <div key={l.id} style={{ background: '#fff', border: '1px solid var(--td-border)', borderRadius: 8, padding: '10px 12px', marginBottom: 8 }}>
                <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                  <div style={{ fontSize: 11.5, fontWeight: 700 }}>{l.client}</div>
                  <div style={{ fontSize: 9.5, fontWeight: 700, color: l.statusColor }}>{l.status}</div>
                </div>
                <div style={{ fontSize: 10.5, color: '#9a9fa8', marginTop: 2 }}>{l.product} · Qty {l.qty}</div>
              </div>
            ))}
          </div>
        </div>
      </div>
      <div style={{ width: 280 }}>
        <div style={{ fontSize: 13, fontWeight: 700, marginBottom: 10 }}>Auto-notifications on lead creation</div>
        {NOTIFICATIONS.map((n) => (
          <div key={n.text} style={{ background: '#fff', border: '1px solid var(--td-border)', borderRadius: 6, padding: 12, marginBottom: 8 }}>
            <div style={{ fontSize: 12, fontWeight: 600 }}>{n.text}</div>
            <div style={{ fontSize: 10.5, color: '#9a9fa8', marginTop: 3 }}>{n.meta}</div>
          </div>
        ))}
      </div>
    </div>
  );
}

function DesktopMarketing() {
  const columns: Column<(typeof LEADS)[number]>[] = [
    { key: 'id', label: 'Lead' },
    { key: 'product', label: 'Product' },
    { key: 'client', label: 'Client · Region', render: (r) => `${r.client} · ${r.region}` },
    { key: 'qty', label: 'Qty' },
    { key: 'rep', label: 'Rep' },
    { key: 'status', label: 'Status', render: (r) => <span style={{ fontWeight: 700, color: r.statusColor }}>{r.status}</span> },
  ];
  return (
    <div style={{ background: '#fff', border: '1px solid var(--td-border)', borderRadius: 6, overflow: 'hidden' }}>
      <DataTable columns={columns} rows={LEADS} />
    </div>
  );
}

export function Marketing() {
  const { role } = useAuth();
  return role === 'admin' ? <DesktopMarketing /> : <MobileMarketing />;
}
