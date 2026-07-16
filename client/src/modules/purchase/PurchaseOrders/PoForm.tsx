import { useEffect, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { useApiData } from '../../../lib/hooks';
import { api } from '../../../lib/api';
import { Button, Card, Field, FormGrid, money } from '../../../components/ui';
import { LineItemsEditor, type LineRow } from '../LineItemsEditor';
import type { Account, Department, Material, PurchaseOrder, Quotation, SanctionIndent, Unit } from '../../../lib/types';

export function PoForm() {
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const quotationIdParam = params.get('quotation_id');

  const { data: vendors } = useApiData<Account[]>('/accounts?kind=vendor');
  const { data: departments } = useApiData<Department[]>('/departments');
  const { data: materials } = useApiData<Material[]>('/materials');
  const { data: units } = useApiData<Unit[]>('/units');
  const { data: sanctionIndents } = useApiData<SanctionIndent[]>('/sanction-indents');
  const { data: nextNo } = useApiData<{ doc_no: string }>('/purchase-orders/next-number');
  const { data: quotation } = useApiData<Quotation>(quotationIdParam ? `/purchase-quotations/${quotationIdParam}` : '');

  const [docDate, setDocDate] = useState(new Date().toISOString().slice(0, 10));
  const [vendorId, setVendorId] = useState<number | undefined>();
  const [departmentId, setDepartmentId] = useState<number | undefined>();
  const [deliveryTerms, setDeliveryTerms] = useState('');
  const [delDays, setDelDays] = useState<number | undefined>();
  const [delDate, setDelDate] = useState('');
  const [sanctionId, setSanctionId] = useState<number | undefined>();
  const [transport, setTransport] = useState('');
  const [paymentTerms, setPaymentTerms] = useState('');
  const [narration, setNarration] = useState('');
  const [consignee, setConsignee] = useState('');
  const [freight, setFreight] = useState(0);
  const [otherCharge, setOtherCharge] = useState(0);
  const [discountAmt, setDiscountAmt] = useState(0);
  const [roundOff, setRoundOff] = useState(0);
  const [rows, setRows] = useState<LineRow[]>([{ qty: 0, rate: 0 }]);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (quotation) {
      setVendorId(quotation.vendor_id);
      setDepartmentId(quotation.department_id ?? undefined);
      setDeliveryTerms(quotation.delivery_terms ?? '');
      setRows((quotation.items ?? []).map((it) => ({ material_id: it.material_id, unit: it.unit, qty: it.qty, rate: it.rate, description: it.description })));
    }
  }, [quotation]);

  async function loadFromSanction(sid: number) {
    setSanctionId(sid);
    if (!sid) return;
    const si = await api.get<SanctionIndent>(`/sanction-indents/${sid}`);
    setDepartmentId(si.department_id);
    if (!quotation) setRows((si.items ?? []).map((it) => ({ material_id: it.material_id, unit: it.unit, qty: it.qty, hsn_no: it.hsn_no, rate: 0 })));
  }

  const assessableAmt = rows.reduce((s, r) => s + Number(r.qty || 0) * Number(r.rate || 0), 0);

  async function save() {
    setSaving(true);
    try {
      const created = await api.post<PurchaseOrder>('/purchase-orders', {
        doc_date: docDate,
        vendor_id: vendorId,
        department_id: departmentId,
        delivery_terms: deliveryTerms,
        del_days: delDays,
        del_date: delDate || null,
        sanction_id: sanctionId ?? null,
        transport,
        payment_terms: paymentTerms,
        narration,
        quotation_id: quotationIdParam ? Number(quotationIdParam) : null,
        consignee,
        default_printing: 'PO Thermoset',
        freight,
        other_charge: otherCharge,
        discount_amt: discountAmt,
        round_off: roundOff,
        items: rows.filter((r) => r.material_id).map((r) => ({
          material_id: r.material_id, hsn_no: r.hsn_no, description: r.description,
          delivery_date: r.delivery_date, unit: r.unit, qty: r.qty, rate: r.rate ?? 0,
        })),
      });
      navigate(`/purchase/purchase-orders/${created.id}`);
    } finally {
      setSaving(false);
    }
  }

  return (
    <div>
      <div style={{ fontSize: 15, fontWeight: 700, marginBottom: 14 }}>New Purchase Order</div>
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
          <Field label="Department">
            <select value={departmentId ?? ''} onChange={(e) => setDepartmentId(Number(e.target.value))}>
              <option value="">Select department…</option>
              {departments?.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
            </select>
          </Field>
          <Field label="Delivery Terms"><input value={deliveryTerms} onChange={(e) => setDeliveryTerms(e.target.value)} /></Field>
          <Field label="Del Days"><input type="number" value={delDays ?? ''} onChange={(e) => setDelDays(Number(e.target.value))} /></Field>
          <Field label="Del Date"><input type="date" value={delDate} onChange={(e) => setDelDate(e.target.value)} /></Field>
          <Field label="Sanction Indent Link">
            <select value={sanctionId ?? ''} onChange={(e) => loadFromSanction(Number(e.target.value))}>
              <option value="">None — manual entry</option>
              {sanctionIndents?.map((s) => <option key={s.id} value={s.id}>{s.doc_no}</option>)}
            </select>
          </Field>
          <Field label="Transport"><input value={transport} onChange={(e) => setTransport(e.target.value)} /></Field>
          <Field label="Payment Terms"><input value={paymentTerms} onChange={(e) => setPaymentTerms(e.target.value)} /></Field>
          <Field label="Purchase Qty Link (Quotation)"><input value={quotation?.doc_no ?? ''} disabled /></Field>
          <Field label="Consignee"><input value={consignee} onChange={(e) => setConsignee(e.target.value)} /></Field>
          <Field label="Narration" span={2}><input value={narration} onChange={(e) => setNarration(e.target.value)} /></Field>
        </FormGrid>
      </Card>

      <Card style={{ padding: 18, marginBottom: 16 }}>
        <LineItemsEditor materials={materials ?? []} units={units ?? []} rows={rows} onChange={setRows} showRate showHsn showDescription showDeliveryDate />
      </Card>

      <Card style={{ padding: 18 }}>
        <FormGrid columns={4}>
          <Field label="Freight"><input type="number" value={freight} onChange={(e) => setFreight(Number(e.target.value))} /></Field>
          <Field label="Other Charge"><input type="number" value={otherCharge} onChange={(e) => setOtherCharge(Number(e.target.value))} /></Field>
          <Field label="Discount"><input type="number" value={discountAmt} onChange={(e) => setDiscountAmt(Number(e.target.value))} /></Field>
          <Field label="Round Off"><input type="number" value={roundOff} onChange={(e) => setRoundOff(Number(e.target.value))} /></Field>
        </FormGrid>
        <div style={{ marginTop: 14, fontSize: 12.5, fontWeight: 700, textAlign: 'right' }}>
          Assessable Amt (before tax): {money(assessableAmt)} — GST, freight & totals are computed on save.
        </div>
      </Card>

      <div style={{ marginTop: 16, display: 'flex', gap: 10 }}>
        <Button variant="primary" onClick={save} disabled={saving || !vendorId || rows.every((r) => !r.material_id)}>{saving ? 'Saving…' : 'Save Purchase Order'}</Button>
        <Button onClick={() => navigate('/purchase/purchase-orders')}>Cancel</Button>
      </div>
    </div>
  );
}
