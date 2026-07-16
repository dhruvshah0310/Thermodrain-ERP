import { useEffect, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { useApiData } from '../../../lib/hooks';
import { api } from '../../../lib/api';
import { Button, Card, Field, FormGrid } from '../../../components/ui';
import { LineItemsEditor, type LineRow } from '../LineItemsEditor';
import type { Department, Indent, Material, SanctionIndent, Unit } from '../../../lib/types';

export function SanctionForm() {
  const { id } = useParams();
  const isNew = !id || id === 'new';
  const navigate = useNavigate();

  const { data: departments } = useApiData<Department[]>('/departments');
  const { data: materials } = useApiData<Material[]>('/materials');
  const { data: units } = useApiData<Unit[]>('/units');
  const { data: openIndents } = useApiData<Indent[]>('/purchase-indents?status=open');
  const { data: nextNo } = useApiData<{ doc_no: string }>('/sanction-indents/next-number');
  const { data: existing } = useApiData<SanctionIndent>(isNew ? '' : `/sanction-indents/${id}`);

  const [docDate, setDocDate] = useState(new Date().toISOString().slice(0, 10));
  const [departmentId, setDepartmentId] = useState<number | undefined>();
  const [indentId, setIndentId] = useState<number | undefined>();
  const [narration, setNarration] = useState('');
  const [rows, setRows] = useState<LineRow[]>([]);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (existing) {
      setDocDate(existing.doc_date.slice(0, 10));
      setDepartmentId(existing.department_id);
      setIndentId(existing.indent_id ?? undefined);
      setNarration(existing.narration ?? '');
      setRows((existing.items ?? []).map((it) => ({ material_id: it.material_id, unit: it.unit, qty: it.qty, hsn_no: it.hsn_no, remark: it.remark })));
    }
  }, [existing]);

  async function loadFromIndent(indentIdValue: number) {
    setIndentId(indentIdValue);
    if (!indentIdValue) return;
    const indent = await api.get<Indent>(`/purchase-indents/${indentIdValue}`);
    setDepartmentId(indent.department_id);
    setNarration(indent.narration ?? '');
    setRows((indent.items ?? []).map((it) => ({ material_id: it.material_id, unit: it.unit, qty: it.req_qty, remark: it.remark })));
  }

  async function save() {
    setSaving(true);
    try {
      const payload = {
        doc_date: docDate,
        department_id: departmentId,
        indent_id: indentId ?? null,
        narration,
        default_printing: 'Sanction Indent',
        items: rows.filter((r) => r.material_id).map((r) => ({ material_id: r.material_id, unit: r.unit, qty: r.qty, hsn_no: r.hsn_no, remark: r.remark })),
      };
      if (isNew) {
        const created = await api.post<SanctionIndent>('/sanction-indents', payload);
        navigate(`/purchase/sanction-indents/${created.id}`);
      } else {
        await api.put(`/sanction-indents/${id}`, payload);
        navigate('/purchase/sanction-indents');
      }
    } finally {
      setSaving(false);
    }
  }

  return (
    <div>
      <div style={{ fontSize: 15, fontWeight: 700, marginBottom: 14 }}>
        {isNew ? 'New Sanction Indent' : `Sanction Indent ${existing?.doc_no ?? ''}`}
      </div>
      <Card style={{ padding: 18, marginBottom: 16 }}>
        <FormGrid columns={4}>
          <Field label="Document No."><input value={isNew ? (nextNo?.doc_no ?? 'auto') : (existing?.doc_no ?? '')} disabled /></Field>
          <Field label="Date"><input type="date" value={docDate} onChange={(e) => setDocDate(e.target.value)} /></Field>
          <Field label="Purchase Indent Link">
            <select value={indentId ?? ''} onChange={(e) => loadFromIndent(Number(e.target.value))}>
              <option value="">None — manual entry</option>
              {openIndents?.map((i) => <option key={i.id} value={i.id}>{i.indent_no} · {i.department_name}</option>)}
            </select>
          </Field>
          <Field label="Department">
            <select value={departmentId ?? ''} onChange={(e) => setDepartmentId(Number(e.target.value))}>
              <option value="">Select department…</option>
              {departments?.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
            </select>
          </Field>
          <Field label="Narration" span={2}><input value={narration} onChange={(e) => setNarration(e.target.value)} /></Field>
        </FormGrid>
      </Card>
      <Card style={{ padding: 18 }}>
        <LineItemsEditor materials={materials ?? []} units={units ?? []} rows={rows} onChange={setRows} showHsn showRemark />
      </Card>
      <div style={{ marginTop: 16, display: 'flex', gap: 10 }}>
        <Button variant="primary" onClick={save} disabled={saving || !departmentId}>{saving ? 'Saving…' : 'Save Sanction Indent'}</Button>
        <Button onClick={() => navigate('/purchase/sanction-indents')}>Cancel</Button>
      </div>
    </div>
  );
}
