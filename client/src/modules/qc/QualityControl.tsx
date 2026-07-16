const QC_QUEUE = [
  { wo: 'WO-878', product: 'MHC-LD-250', result: 'Pending', resultColor: 'var(--td-amber)', hasCategory: false },
  { wo: 'WO-875', product: 'MHC-HD-450', result: 'Rejected', resultColor: 'var(--td-red)', hasCategory: true, category: 'Colour Issue', vendor: 'Shree Castings', supervisor: 'R. Singh', transporter: '—' },
  { wo: 'WO-870', product: 'MHC-LD-250', result: 'Approved', resultColor: 'var(--td-green)', hasCategory: false },
  { wo: 'WO-866', product: 'MHC-HD-600', result: 'Rejected', resultColor: 'var(--td-red)', hasCategory: true, category: 'Strength / Quality', vendor: 'Balaji Foundry', supervisor: 'K. Menon', transporter: 'Balaji Logistics' },
];

const CATEGORIES = [
  { name: 'Design Issue', desc: 'Incorrect design / specs not met' },
  { name: 'Colour Issue', desc: 'Wrong colour or colour mismatch' },
  { name: 'Strength / Quality', desc: 'Substandard RM or process error' },
];

export function QualityControl() {
  return (
    <div style={{ display: 'grid', gridTemplateColumns: '1.5fr 1fr', gap: 16 }}>
      <div style={{ background: '#fff', border: '1px solid var(--td-border)', borderRadius: 6, overflow: 'hidden' }}>
        <div style={{ padding: '14px 18px', borderBottom: '1px solid var(--td-divider)', fontSize: 13, fontWeight: 700 }}>QC queue</div>
        {QC_QUEUE.map((q) => (
          <div key={q.wo} style={{ padding: '13px 18px', borderBottom: '1px solid var(--td-divider)' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <div style={{ fontSize: 12.5, fontWeight: 700 }}>{q.wo} · {q.product}</div>
              <div style={{ fontSize: 11, fontWeight: 700, color: q.resultColor }}>{q.result}</div>
            </div>
            {q.hasCategory && (
              <div style={{ fontSize: 11, color: '#9a9fa8', marginTop: 4 }}>
                {q.category} · Vendor: {q.vendor} · Sup: {q.supervisor} · Transporter: {q.transporter}
              </div>
            )}
          </div>
        ))}
      </div>
      <div style={{ background: '#fff', border: '1px solid var(--td-border)', borderRadius: 6, padding: 18 }}>
        <div style={{ fontSize: 13, fontWeight: 700, marginBottom: 10 }}>Rejection categories</div>
        {CATEGORIES.map((c) => (
          <div key={c.name} style={{ fontSize: 12, color: 'var(--td-text-secondary)', padding: '6px 0', borderBottom: '1px solid var(--td-bg)' }}>
            <span style={{ fontWeight: 700, color: 'var(--td-text)' }}>{c.name}</span> — {c.desc}
          </div>
        ))}
      </div>
    </div>
  );
}
