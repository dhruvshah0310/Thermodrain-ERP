import { useEffect, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { useApiData } from '../../../lib/hooks';
import { api } from '../../../lib/api';
import { Button, Card, Field, FormGrid } from '../../../components/ui';
import { LineItemsEditor, type LineRow } from '../LineItemsEditor';
import type { Account, Material, Rfq, Unit } from '../../../lib/types';

export function QuotationForm() {
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const rfqId = params.get('rfq_id');

  const { data: vendors } = useApiData<Account[]>('/accounts?kind=vendor');
  const { data: materials } = useApiData<Material[]>('/materials');
  const { data: units } = useApiData<Unit[]>('/units');
  const { data: nextNo } = useApiData<{ doc_no: string }>('/purchase-quotations/next-number');
  const { data: rfq } = useApiData<Rfq>(rfqId ? `/rfqs/${rfqId}` : '');

  const [docDate, setDocDate] = useState(new Date().toISOString().slice(0, 10));
  const [vendorId, setVendorId] = useState<number | undefined>();
  const [deliveryTerms, setDeliveryTerms] = useState('');
  const [narration, setNarration] = useState('');
  const [rows, setRows] = useState<LineRow[]>([{ qty: 0, rate: 0 }]);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (rfq?.items) {
      setRows(rfq.items.map((it) => ({ material_id: it.material_id, unit: it.unit, qty: it.qty, rate: 0 })));
    }
  }, [rfq]);

  async function save() {
    setSaving(true);
    try {
      await api.post('/purchase-quotations', {
        doc_date: docDate,
        vendor_id: vendorId,
        rfq_id: rfqId ? Number(rfqId) : null,
        rfq_no: rfq?.doc_no,
        rfq_date: rfq?.doc_date,
        department_id: rfq?.department_id,
        narration,
        delivery_terms: deliveryTerms,
        items: rows.filter((r) => r.material_id).map((r) => ({ material_id: r.material_id, description: r.description, unit: r.unit, qty: r.qty, rate: r.rate ?? 0 })),
      });
      navigate(rfqId ? `/purchase/rfqs/${rfqId}` : '/purchase/quotations');
    } finally {
      setSaving(false);
    }
  }

  return (
    <div>
      <div style={{ fontSize: 15, fontWeight: 700, marginBottom: 14 }}>
        New Purchase Quotation {rfq ? `(for RFQ ${rfq.doc_no})` : ''}
      </div>
      <Card style={{ padding: 18, marginBottom: 16 }}>
        <FormGrid columns={4}>
          <Field label="Document No."><input value={nextNo?.doc_no ?? 'auto'} disabled /></Field>
          <Field label="Date"><input type="date" value={docDate} onChange={(e) => setDocDate(e.target.value)} /></Field>
          <Field label="Supplier">
            <select value={vendorId ?? ''} onChange={(e) => setVendorId(Number(e.target.value))}>
              <option value="">Select vendor…</option>
              {vendors?.map((v) => <option key={v.id} value={v.id}>{v.name}</option>)}
            </select>
          </Field>
          <Field label="RFQ No."><input value={rfq?.doc_no ?? ''} disabled /></Field>
          <Field label="Delivery Terms"><input value={deliveryTerms} onChange={(e) => setDeliveryTerms(e.target.value)} /></Field>
          <Field label="Narration" span={2}><input value={narration} onChange={(e) => setNarration(e.target.value)} /></Field>
        </FormGrid>
      </Card>
      <Card style={{ padding: 18 }}>
        <LineItemsEditor materials={materials ?? []} units={units ?? []} rows={rows} onChange={setRows} showRate showDescription />
      </Card>
      <div style={{ marginTop: 16, display: 'flex', gap: 10 }}>
        <Button variant="primary" onClick={save} disabled={saving || !vendorId}>{saving ? 'Saving…' : 'Save Quotation'}</Button>
        <Button onClick={() => navigate('/purchase/quotations')}>Cancel</Button>
      </div>
    </div>
  );
}
