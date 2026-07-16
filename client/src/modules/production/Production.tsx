import { DataTable, type Column } from '../../components/ui';

const PRODUCTION = [
  { id: 'WO-882', product: 'MHC-HD-450', qty: 300, supervisor: 'R. Singh', pct: '64%', stage: 'Moulding' },
  { id: 'WO-880', product: 'MHC-HD-600', qty: 170, supervisor: 'K. Menon', pct: '40%', stage: 'Casting' },
  { id: 'WO-885', product: 'MHC-STD-300', qty: 220, supervisor: 'R. Singh', pct: '15%', stage: 'RM Prep' },
  { id: 'WO-878', product: 'MHC-LD-250', qty: 150, supervisor: 'K. Menon', pct: '90%', stage: 'Finishing' },
];

export function Production() {
  const columns: Column<(typeof PRODUCTION)[number]>[] = [
    { key: 'id', label: 'WO' },
    { key: 'product', label: 'Product' },
    { key: 'qty', label: 'Qty' },
    { key: 'supervisor', label: 'Supervisor' },
    { key: 'pct', label: 'Progress', render: (r) => (
      <div style={{ width: 120, height: 6, background: '#eee', borderRadius: 3, overflow: 'hidden' }}>
        <div style={{ width: r.pct, height: '100%', background: 'var(--td-accent)' }} />
      </div>
    ) },
    { key: 'stage', label: 'Stage', render: (r) => <span style={{ fontWeight: 700, color: 'var(--td-blue)' }}>{r.stage}</span> },
  ];
  return (
    <div style={{ background: '#fff', border: '1px solid var(--td-border)', borderRadius: 6, overflow: 'hidden' }}>
      <DataTable columns={columns} rows={PRODUCTION} />
    </div>
  );
}
