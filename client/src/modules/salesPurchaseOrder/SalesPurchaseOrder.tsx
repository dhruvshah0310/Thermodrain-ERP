import { DataTable, type Column } from '../../components/ui';

const PURCHASE_ORDERS = [
  { id: 'PO-556', client: 'Nagpur Municipal', quotation: 'QT-115', value: '₹22,10,000', date: '12 Jul', status: 'WO Created' },
  { id: 'PO-554', client: 'Chennai Metro Water', quotation: 'QT-116', value: '₹11,90,000', date: '9 Jul', status: 'In Production' },
  { id: 'PO-551', client: 'Indore Municipal', quotation: 'QT-108', value: '₹14,50,000', date: '2 Jul', status: 'Dispatched' },
  { id: 'PO-549', client: 'Kolkata Water Board', quotation: 'QT-104', value: '₹8,30,000', date: '28 Jun', status: 'QC Approved' },
];

export function SalesPurchaseOrder() {
  const columns: Column<(typeof PURCHASE_ORDERS)[number]>[] = [
    { key: 'id', label: 'PO' },
    { key: 'client', label: 'Client' },
    { key: 'quotation', label: 'Linked Quotation' },
    { key: 'value', label: 'Value' },
    { key: 'date', label: 'Date' },
    { key: 'status', label: 'Status', render: (r) => <span style={{ fontWeight: 700, color: 'var(--td-blue)' }}>{r.status}</span> },
  ];
  return (
    <div style={{ background: '#fff', border: '1px solid var(--td-border)', borderRadius: 6, overflow: 'hidden' }}>
      <DataTable columns={columns} rows={PURCHASE_ORDERS} />
    </div>
  );
}
