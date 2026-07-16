import { useEffect, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { useApiData } from '../../../lib/hooks';
import { api } from '../../../lib/api';
import { Button, Card, Field, FormGrid } from '../../../components/ui';
import { LineItemsEditor, type LineRow } from '../LineItemsEditor';
import type { Department, Indent, Material, Unit } from '../../../lib/types';

export function IndentForm() {
  const { id } = useParams();
  const isNew = !id || id === 'new';
  const navigate = useNavigate();

  const { data: departments } = useApiData<Department[]>('/departments');
  const { data: materials } = useApiData<Material[]>('/materials');
  const { data: units } = useApiData<Unit[]>('/units');
  const { data: nextNo } = useApiData<{ indent_no: string }>('/purchase-indents/next-number');
  const { data: existing } = useApiData<Indent>(isNew ? '' : `/purchase-indents/${id}`);

  const [indentDate, setIndentDate] = useState(new Date().toISOString().slice(0, 10));
  const [departmentId, setDepartmentId] = useState<number | undefined>();
  const [narration, setNarration] = useState('');
  const [rows, setRows] = useState<LineRow[]>([{ qty: 0 }]);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (existing) {
      setIndentDate(existing.indent_date.slice(0, 10));
      setDepartmentId(existing.department_id);
      setNarration(existing.narration ?? '');
      setRows((existing.items ?? []).map((it) => ({ material_id: it.material_id, unit: it.unit, qty: it.req_qty, remark: it.remark })));
    }
  }, [existing]);

  async function save() {
    setSaving(true);
    try {
      const payload = {
        indent_date: indentDate,
        department_id: departmentId,
        narration,
        items: rows.filter((r) => r.material_id).map((r) => ({ material_id: r.material_id, unit: r.unit, req_qty: r.qty, remark: r.remark })),
      };
      if (isNew) {
        const created = await api.post<Indent>('/purchase-indents', payload);
        navigate(`/purchase/indents/${created.id}`);
      } else {
        await api.put(`/purchase-indents/${id}`, payload);
        navigate('/purchase/indents');
      }
    } finally {
      setSaving(false);
    }
  }

  return (
    <div>
      <div style={{ fontSize: 15, fontWeight: 700, marginBottom: 14 }}>
        {isNew ? 'New Purchase Indent' : `Purchase Indent ${existing?.indent_no ?? ''}`}
      </div>
      <Card style={{ padding: 18, marginBottom: 16 }}>
        <FormGrid columns={4}>
          <Field label="Document No."><input value={isNew ? (nextNo?.indent_no ?? 'auto') : (existing?.indent_no ?? '')} disabled /></Field>
          <Field label="Date"><input type="date" value={indentDate} onChange={(e) => setIndentDate(e.target.value)} /></Field>
          <Field label="Department">
            <select value={departmentId ?? ''} onChange={(e) => setDepartmentId(Number(e.target.value))}>
              <option value="">Select department…</option>
              {departments?.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
            </select>
          </Field>
          <Field label="Narration" span={1}><input value={narration} onChange={(e) => setNarration(e.target.value)} /></Field>
        </FormGrid>
      </Card>
      <Card style={{ padding: 18 }}>
        <LineItemsEditor materials={materials ?? []} units={units ?? []} rows={rows} onChange={setRows} showRemark />
      </Card>
      <div style={{ marginTop: 16, display: 'flex', gap: 10 }}>
        <Button variant="primary" onClick={save} disabled={saving || !departmentId}>{saving ? 'Saving…' : 'Save Indent'}</Button>
        <Button onClick={() => navigate('/purchase/indents')}>Cancel</Button>
      </div>
    </div>
  );
}
