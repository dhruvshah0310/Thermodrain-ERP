import { useState } from 'react';
import { useApiData } from '../../lib/hooks';
import { api } from '../../lib/api';
import { Button, Card, DataTable, Field, FormGrid, type Column } from '../../components/ui';
import type { Material, Unit } from '../../lib/types';

const EMPTY = {
  code: '', name: '', hsn_no: '', unit_id: undefined as number | undefined, material_type: '', group_head: '', sub_group: '', gst_percent: 18, reorder_level: 0,
};

export function Materials() {
  const { data, loading, reload } = useApiData<Material[]>('/materials');
  const { data: units } = useApiData<Unit[]>('/units');
  const [showForm, setShowForm] = useState(false);
  const [form, setForm] = useState(EMPTY);
  const [saving, setSaving] = useState(false);
  const [q, setQ] = useState('');

  const materials = (data ?? []).filter((m) => !q || m.name.toLowerCase().includes(q.toLowerCase()) || m.code.toLowerCase().includes(q.toLowerCase()));

  async function save() {
    setSaving(true);
    try {
      await api.post('/materials', form);
      setForm(EMPTY);
      setShowForm(false);
      reload();
    } finally {
      setSaving(false);
    }
  }

  const unitName = (id?: number | null) => units?.find((u) => u.id === id)?.name ?? '—';

  const columns: Column<Material>[] = [
    { key: 'code', label: 'Code' },
    { key: 'name', label: 'Material' },
    { key: 'material_type', label: 'Type' },
    { key: 'group_head', label: 'Group Head' },
    { key: 'unit_id', label: 'Unit', render: (r) => unitName(r.unit_id) },
    { key: 'gst_percent', label: 'GST %', align: 'right' },
    { key: 'reorder_level', label: 'Reorder Level', align: 'right' },
  ];

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 14 }}>
        <div style={{ fontSize: 15, fontWeight: 700 }}>Materials ({materials.length})</div>
        <div style={{ display: 'flex', gap: 8 }}>
          <input placeholder="Search materials…" value={q} onChange={(e) => setQ(e.target.value)} style={{ width: 220 }} />
          <Button variant="primary" onClick={() => setShowForm((s) => !s)}>{showForm ? 'Cancel' : '+ Add Material'}</Button>
        </div>
      </div>

      {showForm && (
        <Card style={{ padding: 18, marginBottom: 16 }}>
          <FormGrid columns={4}>
            <Field label="Code"><input value={form.code} onChange={(e) => setForm({ ...form, code: e.target.value })} /></Field>
            <Field label="Name" span={2}><input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} /></Field>
            <Field label="HSN No."><input value={form.hsn_no} onChange={(e) => setForm({ ...form, hsn_no: e.target.value })} /></Field>
            <Field label="Unit">
              <select value={form.unit_id ?? ''} onChange={(e) => setForm({ ...form, unit_id: e.target.value ? Number(e.target.value) : undefined })}>
                <option value="">Select unit…</option>
                {units?.map((u) => <option key={u.id} value={u.id}>{u.name}</option>)}
              </select>
            </Field>
            <Field label="Material Type"><input value={form.material_type} onChange={(e) => setForm({ ...form, material_type: e.target.value })} /></Field>
            <Field label="Group Head"><input value={form.group_head} onChange={(e) => setForm({ ...form, group_head: e.target.value })} /></Field>
            <Field label="Sub Group"><input value={form.sub_group} onChange={(e) => setForm({ ...form, sub_group: e.target.value })} /></Field>
            <Field label="GST %"><input type="number" value={form.gst_percent} onChange={(e) => setForm({ ...form, gst_percent: Number(e.target.value) })} /></Field>
            <Field label="Reorder Level"><input type="number" value={form.reorder_level} onChange={(e) => setForm({ ...form, reorder_level: Number(e.target.value) })} /></Field>
          </FormGrid>
          <div style={{ marginTop: 14 }}>
            <Button variant="primary" onClick={save} disabled={saving || !form.name || !form.code}>{saving ? 'Saving…' : 'Save Material'}</Button>
          </div>
        </Card>
      )}

      <Card>
        {loading ? <div style={{ padding: 18, fontSize: 12.5, color: 'var(--td-text-muted)' }}>Loading…</div> : <DataTable columns={columns} rows={materials} />}
      </Card>
    </div>
  );
}
