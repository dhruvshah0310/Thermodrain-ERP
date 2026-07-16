import { useEffect, useState } from 'react';
import { useNavigate, useParams, useSearchParams } from 'react-router-dom';
import { useApiData } from '../../../lib/hooks';
import { api } from '../../../lib/api';
import { Badge, Button, Card, DataTable, Field, FormGrid, money, qty, type Column } from '../../../components/ui';
import type { Grn, PoItem, PurchaseOrder } from '../../../lib/types';

interface ReceiptRow extends PoItem {
  receive_now: number;
}

export function GrnForm() {
  const { id } = useParams();
  const isView = !!id && id !== 'new';
  if (isView) return <GrnView id={Number(id)} />;
  return <GrnCreate />;
}

function GrnCreate() {
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const poIdParam = params.get('po_id');

  const { data: openPOs } = useApiData<PurchaseOrder[]>('/purchase-orders?status=issued');
  const { data: partialPOs } = useApiData<PurchaseOrder[]>('/purchase-orders?status=partially_received');
  const { data: nextNo } = useApiData<{ grn_no: string }>('/grns/next-number');
  const [poId, setPoId] = useState<number | undefined>(poIdParam ? Number(poIdParam) : undefined);
  const { data: po } = useApiData<PurchaseOrder>(poId ? `/purchase-orders/${poId}` : '');

  const [grnDate, setGrnDate] = useState(new Date().toISOString().slice(0, 10));
  const [billNo, setBillNo] = useState('');
  const [billDate, setBillDate] = useState('');
  const [challanNo, setChallanNo] = useState('');
  const [challanDate, setChallanDate] = useState('');
  const [status, setStatus] = useState<'RECEIVED' | 'HOLD' | 'CANCEL' | 'NOT'>('RECEIVED');
  const [rows, setRows] = useState<ReceiptRow[]>([]);
  const [saving, setSaving] = useState(false);

  const availablePOs = [...(openPOs ?? []), ...(partialPOs ?? [])];

  useEffect(() => {
    if (po?.items) {
      setRows(po.items.map((it) => ({ ...it, receive_now: Math.max(0, Number(it.qty) - Number(it.received_qty ?? 0)) })));
    }
  }, [po]);

  function updateRow(i: number, receiveNow: number) {
    const next = rows.slice();
    next[i] = { ...next[i], receive_now: receiveNow };
    setRows(next);
  }

  async function save() {
    setSaving(true);
    try {
      const created = await api.post<Grn>('/grns', {
        grn_date: grnDate,
        po_id: poId,
        bill_no: billNo,
        bill_date: billDate || null,
        challan_no: challanNo,
        challan_date: challanDate || null,
        receive_status: status,
        items: rows.filter((r) => r.receive_now > 0).map((r) => ({
          po_item_id: r.id, material_id: r.material_id, receive_qty: r.receive_now, rate: r.rate,
        })),
      });
      navigate(`/purchase/grns/${created.id}`);
    } finally {
      setSaving(false);
    }
  }

  return (
    <div>
      <div style={{ fontSize: 15, fontWeight: 700, marginBottom: 14 }}>New GRN (Goods Receipt Note)</div>
      <Card style={{ padding: 18, marginBottom: 16 }}>
        <FormGrid columns={4}>
          <Field label="GRN No."><input value={nextNo?.grn_no ?? 'auto'} disabled /></Field>
          <Field label="GRN Date"><input type="date" value={grnDate} onChange={(e) => setGrnDate(e.target.value)} /></Field>
          <Field label="Purchase Order">
            <select value={poId ?? ''} onChange={(e) => setPoId(Number(e.target.value))}>
              <option value="">Select PO…</option>
              {availablePOs.map((p) => <option key={p.id} value={p.id}>{p.doc_no} · {p.vendor_name}</option>)}
            </select>
          </Field>
          <Field label="Status">
            <select value={status} onChange={(e) => setStatus(e.target.value as typeof status)}>
              <option value="RECEIVED">RECEIVED</option>
              <option value="HOLD">HOLD</option>
              <option value="CANCEL">CANCEL</option>
              <option value="NOT">NOT</option>
            </select>
          </Field>
          <Field label="Bill No."><input value={billNo} onChange={(e) => setBillNo(e.target.value)} /></Field>
          <Field label="Bill Date"><input type="date" value={billDate} onChange={(e) => setBillDate(e.target.value)} /></Field>
          <Field label="Challan No."><input value={challanNo} onChange={(e) => setChallanNo(e.target.value)} /></Field>
          <Field label="Challan Date"><input type="date" value={challanDate} onChange={(e) => setChallanDate(e.target.value)} /></Field>
        </FormGrid>
      </Card>

      {po && (
        <Card style={{ padding: 18 }}>
          <div style={{ fontSize: 12.5, fontWeight: 700, marginBottom: 10 }}>Receive quantities</div>
          <table>
            <thead>
              <tr style={{ background: '#f8f8f9', textAlign: 'left' }}>
                <th style={th}>Material</th>
                <th style={{ ...th, textAlign: 'right' }}>Ordered</th>
                <th style={{ ...th, textAlign: 'right' }}>Already Received</th>
                <th style={{ ...th, textAlign: 'right' }}>Rate</th>
                <th style={{ ...th, textAlign: 'right' }}>Receive Now</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r, i) => (
                <tr key={r.id} style={{ borderTop: '1px solid var(--td-divider)' }}>
                  <td style={td}>{r.material_name}</td>
                  <td style={{ ...td, textAlign: 'right' }}>{qty(r.qty)}</td>
                  <td style={{ ...td, textAlign: 'right' }}>{qty(r.received_qty)}</td>
                  <td style={{ ...td, textAlign: 'right' }}>{money(r.rate)}</td>
                  <td style={{ ...td, textAlign: 'right' }}>
                    <input type="number" value={r.receive_now} onChange={(e) => updateRow(i, Number(e.target.value))} style={{ width: 90, textAlign: 'right' }} />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </Card>
      )}

      <div style={{ marginTop: 16, display: 'flex', gap: 10 }}>
        <Button variant="primary" onClick={save} disabled={saving || !poId}>{saving ? 'Saving…' : 'Save GRN'}</Button>
        <Button onClick={() => navigate('/purchase/grns')}>Cancel</Button>
      </div>
    </div>
  );
}

function GrnView({ id }: { id: number }) {
  const navigate = useNavigate();
  const { data: grn, loading } = useApiData<Grn>(`/grns/${id}`);
  if (loading) return <div style={{ fontSize: 12.5, color: 'var(--td-text-muted)' }}>Loading…</div>;
  if (!grn) return <div style={{ fontSize: 12.5, color: 'var(--td-red)' }}>GRN not found.</div>;

  const columns: Column<NonNullable<Grn['items']>[number] & { id: number }>[] = [
    { key: 'material_name', label: 'Material' },
    { key: 'receive_qty', label: 'Received Qty', align: 'right', render: (r) => qty(r.receive_qty) },
    { key: 'rate', label: 'Rate', align: 'right', render: (r) => money(r.rate) },
    { key: 'basic_receive_amount', label: 'Basic Amount', align: 'right', render: (r) => money(r.basic_receive_amount) },
    { key: 'freight_gst_recd_basic_amount', label: 'Freight+GST+Basic', align: 'right', render: (r) => money(r.freight_gst_recd_basic_amount) },
    { key: 'landed_rate', label: 'Landed Rate', align: 'right', render: (r) => money(r.landed_rate) },
  ];

  return (
    <div>
      <div style={{ marginBottom: 14 }}>
        <div style={{ fontSize: 15, fontWeight: 700 }}>GRN {grn.grn_no}</div>
        <div style={{ fontSize: 12, color: 'var(--td-text-secondary)', marginTop: 2 }}>
          PO {grn.po_doc_no} · {grn.vendor_name} · {grn.grn_date} · <Badge status={grn.receive_status}>{grn.receive_status}</Badge>
        </div>
      </div>
      <Card>
        <DataTable columns={columns} rows={(grn.items ?? []).map((it, i) => ({ ...it, id: it.id ?? i }))} />
      </Card>
      <div style={{ marginTop: 16 }}>
        <Button onClick={() => navigate('/purchase/grns')}>Back to GRNs</Button>
      </div>
    </div>
  );
}

const th = { padding: '8px 10px', fontSize: 10.5, color: 'var(--td-text-muted)', textTransform: 'uppercase' as const };
const td = { padding: '8px 10px', fontSize: 12.5 };
