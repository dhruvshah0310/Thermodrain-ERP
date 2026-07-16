import type { CSSProperties } from 'react';
import { Button, money, qty as fmtQty } from '../../components/ui';
import type { Material, Unit } from '../../lib/types';

export interface LineRow {
  material_id?: number;
  unit?: string;
  qty: number;
  rate?: number;
  hsn_no?: string;
  remark?: string;
  description?: string;
  delivery_date?: string;
}

interface Props {
  materials: Material[];
  units: Unit[];
  rows: LineRow[];
  onChange: (rows: LineRow[]) => void;
  showRate?: boolean;
  showHsn?: boolean;
  showRemark?: boolean;
  showDescription?: boolean;
  showDeliveryDate?: boolean;
}

export function LineItemsEditor({ materials, units, rows, onChange, showRate, showHsn, showRemark, showDescription, showDeliveryDate }: Props) {
  const unitName = (id?: number | null) => units.find((u) => u.id === id)?.name ?? '';

  function updateRow(i: number, patch: Partial<LineRow>) {
    const next = rows.slice();
    next[i] = { ...next[i], ...patch };
    onChange(next);
  }

  function setMaterial(i: number, materialId: number) {
    const mat = materials.find((m) => m.id === materialId);
    updateRow(i, {
      material_id: materialId,
      unit: mat ? unitName(mat.unit_id) : rows[i].unit,
      hsn_no: showHsn ? (mat?.hsn_no ?? '') : rows[i].hsn_no,
    });
  }

  function addRow() {
    onChange([...rows, { qty: 0, rate: 0 }]);
  }

  function removeRow(i: number) {
    onChange(rows.filter((_, idx) => idx !== i));
  }

  const totalQty = rows.reduce((s, r) => s + Number(r.qty || 0), 0);
  const totalAmt = rows.reduce((s, r) => s + Number(r.qty || 0) * Number(r.rate || 0), 0);

  return (
    <div>
      <table>
        <thead>
          <tr style={{ background: '#f8f8f9', textAlign: 'left' }}>
            <th style={th}>#</th>
            <th style={th}>Material</th>
            {showHsn && <th style={th}>HSN</th>}
            {showDescription && <th style={th}>Description</th>}
            {showDeliveryDate && <th style={th}>Delivery Date</th>}
            <th style={th}>Unit</th>
            <th style={{ ...th, textAlign: 'right' }}>Qty</th>
            {showRate && <th style={{ ...th, textAlign: 'right' }}>Rate</th>}
            {showRate && <th style={{ ...th, textAlign: 'right' }}>Amount</th>}
            {showRemark && <th style={th}>Remark</th>}
            <th style={th} />
          </tr>
        </thead>
        <tbody>
          {rows.map((row, i) => (
            <tr key={i} style={{ borderTop: '1px solid var(--td-divider)' }}>
              <td style={td}>{i + 1}</td>
              <td style={td}>
                <select value={row.material_id ?? ''} onChange={(e) => setMaterial(i, Number(e.target.value))} style={{ width: 220 }}>
                  <option value="">Select material…</option>
                  {materials.map((m) => <option key={m.id} value={m.id}>{m.name}</option>)}
                </select>
              </td>
              {showHsn && <td style={td}><input value={row.hsn_no ?? ''} onChange={(e) => updateRow(i, { hsn_no: e.target.value })} style={{ width: 90 }} /></td>}
              {showDescription && <td style={td}><input value={row.description ?? ''} onChange={(e) => updateRow(i, { description: e.target.value })} style={{ width: 160 }} /></td>}
              {showDeliveryDate && <td style={td}><input type="date" value={row.delivery_date ?? ''} onChange={(e) => updateRow(i, { delivery_date: e.target.value })} /></td>}
              <td style={td}><input value={row.unit ?? ''} onChange={(e) => updateRow(i, { unit: e.target.value })} style={{ width: 60 }} /></td>
              <td style={td}><input type="number" value={row.qty} onChange={(e) => updateRow(i, { qty: Number(e.target.value) })} style={{ width: 80, textAlign: 'right' }} /></td>
              {showRate && <td style={td}><input type="number" value={row.rate ?? 0} onChange={(e) => updateRow(i, { rate: Number(e.target.value) })} style={{ width: 90, textAlign: 'right' }} /></td>}
              {showRate && <td style={{ ...td, textAlign: 'right' }}>{money(Number(row.qty || 0) * Number(row.rate || 0))}</td>}
              {showRemark && <td style={td}><input value={row.remark ?? ''} onChange={(e) => updateRow(i, { remark: e.target.value })} style={{ width: 140 }} /></td>}
              <td style={td}><Button variant="danger" onClick={() => removeRow(i)}>✕</Button></td>
            </tr>
          ))}
        </tbody>
      </table>
      <div style={{ padding: '10px 0' }}>
        <Button onClick={addRow}>+ Add line</Button>
      </div>
      <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 24, fontSize: 12.5, fontWeight: 700, padding: '8px 4px' }}>
        <div>Total Qty: {fmtQty(totalQty)}</div>
        {showRate && <div>Total Amt: {money(totalAmt)}</div>}
      </div>
    </div>
  );
}

const th: CSSProperties = { padding: '8px 10px', fontSize: 10.5, color: 'var(--td-text-muted)', textTransform: 'uppercase' };
const td: CSSProperties = { padding: '6px 10px', fontSize: 12.5 };
