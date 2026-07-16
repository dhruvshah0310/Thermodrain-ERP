const COLUMNS = [
  { title: 'Created', items: [{ id: 'WO-885', product: 'MHC-STD-300', qty: 220, batch: 'Batch 1/1', supervisor: 'R. Singh' }] },
  { title: 'Production', items: [
    { id: 'WO-882', product: 'MHC-HD-450', qty: 300, batch: 'Batch 1/2', supervisor: 'R. Singh' },
    { id: 'WO-880', product: 'MHC-HD-600', qty: 170, batch: 'Batch 2/2', supervisor: 'K. Menon' },
  ] },
  { title: 'QC → Dispatched', items: [{ id: 'WO-870', product: 'MHC-LD-250', qty: 150, batch: 'Batch 1/1', supervisor: 'K. Menon' }] },
];

export function WorkOrder() {
  return (
    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3,1fr)', gap: 14 }}>
      {COLUMNS.map((col) => (
        <div key={col.title} style={{ background: '#fff', border: '1px solid var(--td-border)', borderRadius: 6, padding: 14 }}>
          <div style={{ fontSize: 11.5, fontWeight: 800, color: 'var(--td-text-secondary)', textTransform: 'uppercase', letterSpacing: 0.4, marginBottom: 10 }}>{col.title}</div>
          {col.items.map((w) => (
            <div key={w.id} style={{ background: '#f8f8f9', borderRadius: 6, padding: '10px 12px', marginBottom: 8 }}>
              <div style={{ fontSize: 12, fontWeight: 700 }}>{w.id} · {w.product}</div>
              <div style={{ fontSize: 10.5, color: '#9a9fa8', marginTop: 3 }}>Qty {w.qty} · {w.batch} · Sup. {w.supervisor}</div>
            </div>
          ))}
        </div>
      ))}
    </div>
  );
}
