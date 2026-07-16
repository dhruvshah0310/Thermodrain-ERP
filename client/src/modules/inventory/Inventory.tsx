import { DataTable, type Column } from '../../components/ui';

const INVENTORY = [
  { id: 'RM-CI-01', item: 'Cast Iron Scrap', sku: 'RM-CI-01', stock: '12.4 T', reorder: '8 T', status: 'OK', statusColor: 'var(--td-green)' },
  { id: 'RM-FS-02', item: 'Ferro Silicon', sku: 'RM-FS-02', stock: '0.6 T', reorder: '2 T', status: 'Shortfall', statusColor: 'var(--td-red)' },
  { id: 'RM-CB-03', item: 'Coke Breeze', sku: 'RM-CB-03', stock: '3.1 T', reorder: '1.5 T', status: 'OK', statusColor: 'var(--td-green)' },
  { id: 'RM-MS-04', item: 'Moulding Sand', sku: 'RM-MS-04', stock: '5.8 T', reorder: '5 T', status: 'Low', statusColor: 'var(--td-amber)' },
  { id: 'RM-PC-05', item: 'Paint Coating', sku: 'RM-PC-05', stock: '210 L', reorder: '150 L', status: 'OK', statusColor: 'var(--td-green)' },
];

const INDENTS = [
  { item: 'Ferro Silicon', wo: 'WO-882', action: 'Shortfall → Purchase request raised', color: 'var(--td-red)' },
  { item: 'Moulding Sand', wo: 'WO-880', action: 'Available → Issued to production', color: 'var(--td-green)' },
  { item: 'Cast Iron Scrap', wo: 'WO-885', action: 'Available → Issued to production', color: 'var(--td-green)' },
];

export function Inventory() {
  const columns: Column<(typeof INVENTORY)[number]>[] = [
    { key: 'item', label: 'Item' },
    { key: 'sku', label: 'SKU' },
    { key: 'stock', label: 'In stock' },
    { key: 'reorder', label: 'Reorder level' },
    { key: 'status', label: 'Status', render: (r) => <span style={{ fontWeight: 700, color: r.statusColor }}>{r.status}</span> },
  ];
  return (
    <div style={{ display: 'grid', gridTemplateColumns: '1.5fr 1fr', gap: 16 }}>
      <div style={{ background: '#fff', border: '1px solid var(--td-border)', borderRadius: 6, overflow: 'hidden' }}>
        <DataTable columns={columns} rows={INVENTORY} />
      </div>
      <div style={{ background: '#fff', border: '1px solid var(--td-border)', borderRadius: 6, padding: 18 }}>
        <div style={{ fontSize: 13, fontWeight: 700, marginBottom: 10 }}>Open indents</div>
        {INDENTS.map((d) => (
          <div key={d.item} style={{ padding: '9px 0', borderBottom: '1px solid var(--td-bg)' }}>
            <div style={{ fontSize: 12, fontWeight: 700 }}>{d.item} → {d.wo}</div>
            <div style={{ fontSize: 11, color: d.color, marginTop: 2, fontWeight: 600 }}>{d.action}</div>
          </div>
        ))}
      </div>
    </div>
  );
}
