import { DataTable, type Column } from '../../components/ui';

const DISPATCHES = [
  { id: 'WO-870', wo: 'WO-870', transporter: 'Balaji Logistics', vehicle: 'KA-05-AB-1234', driver: 'M. Reddy', status: 'Delivered', statusColor: 'var(--td-green)' },
  { id: 'WO-864', wo: 'WO-864', transporter: 'Shakti Transport', vehicle: 'MH-12-CD-5678', driver: 'S. Patil', status: 'In Transit', statusColor: 'var(--td-amber)' },
  { id: 'WO-860', wo: 'WO-860', transporter: 'Balaji Logistics', vehicle: 'KA-05-AB-1234', driver: 'M. Reddy', status: 'Delivered', statusColor: 'var(--td-green)' },
  { id: 'WO-855', wo: 'WO-855', transporter: 'Ganesh Carriers', vehicle: 'TN-22-EF-9012', driver: 'V. Kumar', status: 'Scheduled', statusColor: 'var(--td-blue)' },
];

const TRANSPORTERS = [
  { name: 'Balaji Logistics', region: 'Karnataka', contact: '+91 98450 11223' },
  { name: 'Shakti Transport', region: 'Maharashtra', contact: '+91 98220 33445' },
  { name: 'Ganesh Carriers', region: 'Tamil Nadu', contact: '+91 90030 55667' },
];

export function Logistics() {
  const columns: Column<(typeof DISPATCHES)[number]>[] = [
    { key: 'wo', label: 'WO' },
    { key: 'transporter', label: 'Transporter' },
    { key: 'vehicle', label: 'Vehicle' },
    { key: 'driver', label: 'Driver' },
    { key: 'status', label: 'Status', render: (r) => <span style={{ fontWeight: 700, color: r.statusColor }}>{r.status}</span> },
  ];
  return (
    <div style={{ display: 'grid', gridTemplateColumns: '1.5fr 1fr', gap: 16 }}>
      <div style={{ background: '#fff', border: '1px solid var(--td-border)', borderRadius: 6, overflow: 'hidden' }}>
        <DataTable columns={columns} rows={DISPATCHES} />
      </div>
      <div style={{ background: '#fff', border: '1px solid var(--td-border)', borderRadius: 6, padding: 18 }}>
        <div style={{ fontSize: 13, fontWeight: 700, marginBottom: 10 }}>Transporter master</div>
        {TRANSPORTERS.map((t) => (
          <div key={t.name} style={{ padding: '8px 0', borderBottom: '1px solid var(--td-bg)' }}>
            <div style={{ fontSize: 12, fontWeight: 700 }}>{t.name}</div>
            <div style={{ fontSize: 11, color: '#9a9fa8' }}>{t.region} · {t.contact}</div>
          </div>
        ))}
      </div>
    </div>
  );
}
