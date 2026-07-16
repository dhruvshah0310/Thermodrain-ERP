import { useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { useApiData } from '../../../lib/hooks';
import { api } from '../../../lib/api';
import { Button, Card, DataTable, Field, FormGrid, money, type Column } from '../../../components/ui';
import { LineItemsEditor, type LineRow } from '../LineItemsEditor';
import type { Account, Department, Material, Rfq, SanctionIndent, Unit } from '../../../lib/types';

interface CompareRow {
  quotation_id: number; vendor_id: number; vendor_name: string; doc_no: string; total_amt: number;
  material_id: number; material_name: string; qty: number; rate: number; amount: number;
}

export function RfqForm() {
  const { id } = useParams();
  const isNew = !id || id === 'new';
  const navigate = useNavigate();

  if (isNew) return <RfqCreate />;
  return <RfqDetail id={Number(id)} navigate={navigate} />;
}

function RfqCreate() {
  const navigate = useNavigate();
  const { data: departments } = useApiData<Department[]>('/departments');
  const { data: materials } = useApiData<Material[]>('/materials');
  const { data: units } = useApiData<Unit[]>('/units');
  const { data: vendors } = useApiData<Account[]>('/accounts?kind=vendor');
  const { data: sanctionIndents } = useApiData<SanctionIndent[]>('/sanction-indents');

  const [docDate, setDocDate] = useState(new Date().toISOString().slice(0, 10));
  const [departmentId, setDepartmentId] = useState<number | undefined>();
  const [sanctionId, setSanctionId] = useState<number | undefined>();
  const [narration, setNarration] = useState('');
  const [rows, setRows] = useState<LineRow[]>([{ qty: 0 }]);
  const [vendorIds, setVendorIds] = useState<number[]>([]);
  const [saving, setSaving] = useState(false);

  async function loadFromSanction(sid: number) {
    setSanctionId(sid);
    if (!sid) return;
    const si = await api.get<SanctionIndent>(`/sanction-indents/${sid}`);
    setDepartmentId(si.department_id);
    setRows((si.items ?? []).map((it) => ({ material_id: it.material_id, unit: it.unit, qty: it.qty })));
  }

  function toggleVendor(vid: number) {
    setVendorIds((prev) => (prev.includes(vid) ? prev.filter((v) => v !== vid) : [...prev, vid]));
  }

  async function save() {
    setSaving(true);
    try {
      const created = await api.post<Rfq>('/rfqs', {
        doc_date: docDate,
        department_id: departmentId,
        sanction_id: sanctionId ?? null,
        narration,
        vendor_ids: vendorIds,
        items: rows.filter((r) => r.material_id).map((r) => ({ material_id: r.material_id, unit: r.unit, qty: r.qty })),
      });
      navigate(`/purchase/rfqs/${created.id}`);
    } finally {
      setSaving(false);
    }
  }

  return (
    <div>
      <div style={{ fontSize: 15, fontWeight: 700, marginBottom: 14 }}>New Request for Quote</div>
      <Card style={{ padding: 18, marginBottom: 16 }}>
        <FormGrid columns={4}>
          <Field label="Date"><input type="date" value={docDate} onChange={(e) => setDocDate(e.target.value)} /></Field>
          <Field label="Sanction Indent Link">
            <select value={sanctionId ?? ''} onChange={(e) => loadFromSanction(Number(e.target.value))}>
              <option value="">None — manual entry</option>
              {sanctionIndents?.map((s) => <option key={s.id} value={s.id}>{s.doc_no}</option>)}
            </select>
          </Field>
          <Field label="Department">
            <select value={departmentId ?? ''} onChange={(e) => setDepartmentId(Number(e.target.value))}>
              <option value="">Select department…</option>
              {departments?.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
            </select>
          </Field>
          <Field label="Narration"><input value={narration} onChange={(e) => setNarration(e.target.value)} /></Field>
        </FormGrid>
      </Card>

      <Card style={{ padding: 18, marginBottom: 16 }}>
        <div style={{ fontSize: 12.5, fontWeight: 700, marginBottom: 10 }}>Vendors to send RFQ to</div>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
          {vendors?.map((v) => (
            <label key={v.id} style={{ display: 'flex', alignItems: 'center', gap: 6, border: '1px solid var(--td-border)', borderRadius: 20, padding: '5px 10px', fontSize: 12 }}>
              <input type="checkbox" checked={vendorIds.includes(v.id)} onChange={() => toggleVendor(v.id)} />
              {v.name}
            </label>
          ))}
        </div>
      </Card>

      <Card style={{ padding: 18 }}>
        <LineItemsEditor materials={materials ?? []} units={units ?? []} rows={rows} onChange={setRows} />
      </Card>
      <div style={{ marginTop: 16, display: 'flex', gap: 10 }}>
        <Button variant="primary" onClick={save} disabled={saving || !departmentId || vendorIds.length === 0}>{saving ? 'Saving…' : 'Save RFQ'}</Button>
        <Button onClick={() => navigate('/purchase/rfqs')}>Cancel</Button>
      </div>
    </div>
  );
}

function RfqDetail({ id, navigate }: { id: number; navigate: ReturnType<typeof useNavigate> }) {
  const { data: rfq } = useApiData<Rfq>(`/rfqs/${id}`);
  const { data: compare } = useApiData<CompareRow[]>(`/purchase-quotations/compare/${id}`);

  const columns: Column<CompareRow>[] = [
    { key: 'material_name', label: 'Material' },
    { key: 'vendor_name', label: 'Vendor' },
    { key: 'qty', label: 'Qty', align: 'right' },
    { key: 'rate', label: 'Rate', align: 'right', render: (r) => money(r.rate) },
    { key: 'amount', label: 'Amount', align: 'right', render: (r) => money(r.amount) },
    { key: 'doc_no', label: 'Quotation No.' },
  ];

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 14 }}>
        <div style={{ fontSize: 15, fontWeight: 700 }}>RFQ {rfq?.doc_no}</div>
        <Link to={`/purchase/quotations/new?rfq_id=${id}`}>
          <Button variant="primary">+ Log a vendor's quotation</Button>
        </Link>
      </div>
      <Card style={{ padding: 18, marginBottom: 16 }}>
        <div style={{ fontSize: 12.5, color: 'var(--td-text-secondary)' }}>
          Department: <b>{rfq?.department_name}</b> · Sanction Indent: <b>{rfq?.sanction_doc_no ?? '—'}</b>
        </div>
        <div style={{ fontSize: 12.5, color: 'var(--td-text-secondary)', marginTop: 6 }}>
          Sent to: {rfq?.vendors?.map((v) => v.name).join(', ') || '—'}
        </div>
      </Card>
      <Card title="Rate comparison across quotations received">
        <DataTable columns={columns} rows={(compare ?? []).map((r, i) => ({ ...r, id: i }))} emptyMessage="No quotations logged yet for this RFQ." />
      </Card>
      <div style={{ marginTop: 16 }}>
        <Button onClick={() => navigate('/purchase/rfqs')}>Back to RFQs</Button>
      </div>
    </div>
  );
}
