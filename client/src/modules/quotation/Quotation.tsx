const QUOTATIONS = [
  { id: 'QT-118', client: 'Bengaluru Municipal Corp', version: 'v2', updated: 'today', amount: '₹18,40,000', stage: 'Client Review', stageColor: 'var(--td-blue)', stageBg: 'var(--td-blue-bg)' },
  { id: 'QT-117', client: 'Pune Smart City', version: 'v1', updated: '2d ago', amount: '₹6,20,000', stage: 'Internal Review', stageColor: 'var(--td-amber)', stageBg: 'var(--td-amber-bg)' },
  { id: 'QT-116', client: 'Chennai Metro Water', version: 'v3', updated: '3d ago', amount: '₹11,90,000', stage: 'Approved', stageColor: 'var(--td-green)', stageBg: 'var(--td-green-bg)' },
  { id: 'QT-115', client: 'Nagpur Municipal', version: 'v1', updated: '5d ago', amount: '₹22,10,000', stage: 'Sent to Client', stageColor: 'var(--td-blue)', stageBg: 'var(--td-blue-bg)' },
  { id: 'QT-114', client: 'Surat Urban Dev.', version: 'v2', updated: '1w ago', amount: '₹9,00,000', stage: 'Client Modifying', stageColor: 'var(--td-amber)', stageBg: 'var(--td-amber-bg)' },
];

const RULES = [
  'Each revision is version-tracked (v1, v2, v3…)',
  'All quotation versions retained for audit',
  'Client & internal comments logged per version',
  'Loop repeats until client gives final acceptance',
  'Confirmed quotation is prerequisite for PO',
];

export function Quotation() {
  return (
    <div style={{ display: 'grid', gridTemplateColumns: '1.6fr 1fr', gap: 16 }}>
      <div style={{ background: '#fff', border: '1px solid var(--td-border)', borderRadius: 6, overflow: 'hidden' }}>
        <div style={{ padding: '14px 18px', borderBottom: '1px solid var(--td-divider)', fontSize: 13, fontWeight: 700 }}>Quotation pipeline</div>
        {QUOTATIONS.map((q) => (
          <div key={q.id} style={{ padding: '13px 18px', borderBottom: '1px solid var(--td-divider)', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <div>
              <div style={{ fontSize: 12.5, fontWeight: 700 }}>{q.id} · {q.client}</div>
              <div style={{ fontSize: 11, color: '#9a9fa8', marginTop: 2 }}>Version {q.version} · updated {q.updated}</div>
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
              <div style={{ fontSize: 12.5, fontWeight: 700 }}>{q.amount}</div>
              <div style={{ fontSize: 11, fontWeight: 700, color: q.stageColor, background: q.stageBg, padding: '4px 10px', borderRadius: 20 }}>{q.stage}</div>
            </div>
          </div>
        ))}
      </div>
      <div style={{ background: '#fff', border: '1px solid var(--td-border)', borderRadius: 6, padding: 18 }}>
        <div style={{ fontSize: 13, fontWeight: 700, marginBottom: 10 }}>Key rules</div>
        {RULES.map((r) => (
          <div key={r} style={{ fontSize: 12, color: 'var(--td-text-secondary)', padding: '6px 0', borderBottom: '1px solid var(--td-bg)' }}>{r}</div>
        ))}
      </div>
    </div>
  );
}
