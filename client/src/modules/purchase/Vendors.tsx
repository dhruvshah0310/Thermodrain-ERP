import { useState } from 'react';
import { useApiData } from '../../lib/hooks';
import { api } from '../../lib/api';
import { Button, Card, DataTable, Field, FormGrid, type Column } from '../../components/ui';
import type { Account } from '../../lib/types';

const EMPTY = {
  kind: 'vendor', name: '', group_name: '', city: '', state: '', gst_no: '', mobile_no: '', email: '', cr_days: 0,
};

export function Vendors() {
  const { data, loading, reload } = useApiData<Account[]>('/accounts?kind=vendor');
  const [showForm, setShowForm] = useState(false);
  const [form, setForm] = useState<typeof EMPTY>(EMPTY);
  const [saving, setSaving] = useState(false);

  const vendors = (data ?? []).filter((a) => a.kind === 'vendor');

  async function save() {
    setSaving(true);
    try {
      await api.post('/accounts', form);
      setForm(EMPTY);
      setShowForm(false);
      reload();
    } finally {
      setSaving(false);
    }
  }

  const columns: Column<Account>[] = [
    { key: 'name', label: 'Vendor' },
    { key: 'group_name', label: 'Group' },
    { key: 'city', label: 'City' },
    { key: 'gst_no', label: 'GST No.' },
    { key: 'mobile_no', label: 'Mobile' },
    { key: 'cr_days', label: 'Credit Days', align: 'right' },
  ];

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 14 }}>
        <div style={{ fontSize: 15, fontWeight: 700 }}>Vendors ({vendors.length})</div>
        <Button variant="primary" onClick={() => setShowForm((s) => !s)}>{showForm ? 'Cancel' : '+ Add Vendor'}</Button>
      </div>

      {showForm && (
        <Card style={{ padding: 18, marginBottom: 16 }}>
          <FormGrid columns={3}>
            <Field label="Name"><input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} /></Field>
            <Field label="Group"><input value={form.group_name} onChange={(e) => setForm({ ...form, group_name: e.target.value })} /></Field>
            <Field label="City"><input value={form.city} onChange={(e) => setForm({ ...form, city: e.target.value })} /></Field>
            <Field label="State"><input value={form.state} onChange={(e) => setForm({ ...form, state: e.target.value })} /></Field>
            <Field label="GST No."><input value={form.gst_no} onChange={(e) => setForm({ ...form, gst_no: e.target.value })} /></Field>
            <Field label="Mobile"><input value={form.mobile_no} onChange={(e) => setForm({ ...form, mobile_no: e.target.value })} /></Field>
            <Field label="Email"><input value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} /></Field>
            <Field label="Credit Days"><input type="number" value={form.cr_days} onChange={(e) => setForm({ ...form, cr_days: Number(e.target.value) })} /></Field>
          </FormGrid>
          <div style={{ marginTop: 14 }}>
            <Button variant="primary" onClick={save} disabled={saving || !form.name}>{saving ? 'Saving…' : 'Save Vendor'}</Button>
          </div>
        </Card>
      )}

      <Card>
        {loading ? <div style={{ padding: 18, fontSize: 12.5, color: 'var(--td-text-muted)' }}>Loading…</div> : <DataTable columns={columns} rows={vendors} />}
      </Card>
    </div>
  );
}
