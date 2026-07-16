import type { CSSProperties, ReactNode } from 'react';

export function Card({ children, style, title, actions }: { children: ReactNode; style?: CSSProperties; title?: string; actions?: ReactNode }) {
  return (
    <div style={{ background: 'var(--td-surface)', border: '1px solid var(--td-border)', borderRadius: 'var(--td-radius)', overflow: 'hidden', ...style }}>
      {title && (
        <div style={{ padding: '14px 18px', borderBottom: '1px solid var(--td-divider)', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <div style={{ fontSize: 13, fontWeight: 700, color: 'var(--td-text)' }}>{title}</div>
          {actions}
        </div>
      )}
      {children}
    </div>
  );
}

const STATUS_COLORS: Record<string, { color: string; bg: string }> = {
  open: { color: 'var(--td-blue)', bg: 'var(--td-blue-bg)' },
  issued: { color: 'var(--td-blue)', bg: 'var(--td-blue-bg)' },
  sanctioned: { color: 'var(--td-amber)', bg: 'var(--td-amber-bg)' },
  partially_received: { color: 'var(--td-amber)', bg: 'var(--td-amber-bg)' },
  received: { color: 'var(--td-green)', bg: 'var(--td-green-bg)' },
  closed: { color: 'var(--td-gray)', bg: '#f0f1f3' },
  cancelled: { color: 'var(--td-red)', bg: 'var(--td-red-bg)' },
  RECEIVED: { color: 'var(--td-green)', bg: 'var(--td-green-bg)' },
  HOLD: { color: 'var(--td-amber)', bg: 'var(--td-amber-bg)' },
  CANCEL: { color: 'var(--td-red)', bg: 'var(--td-red-bg)' },
  NOT: { color: 'var(--td-gray)', bg: '#f0f1f3' },
};

export function Badge({ status, children }: { status?: string; children: ReactNode }) {
  const c = (status ? STATUS_COLORS[status] : undefined) ?? { color: 'var(--td-gray)', bg: '#f0f1f3' };
  return (
    <span style={{ fontSize: 11, fontWeight: 700, color: c.color, background: c.bg, padding: '3px 9px', borderRadius: 20, whiteSpace: 'nowrap' }}>
      {children}
    </span>
  );
}

export function KpiCard({ label, value, tag, tagColor }: { label: string; value: ReactNode; tag?: string; tagColor?: string }) {
  return (
    <div style={{ background: 'var(--td-surface)', border: '1px solid var(--td-border)', borderRadius: 'var(--td-radius)', padding: 16 }}>
      <div style={{ fontSize: 10.5, color: 'var(--td-text-muted)', textTransform: 'uppercase', letterSpacing: 0.5, fontWeight: 700 }}>{label}</div>
      <div style={{ fontSize: 24, fontWeight: 800, color: 'var(--td-text)', marginTop: 6 }}>{value}</div>
      {tag && <div style={{ fontSize: 11, color: tagColor ?? 'var(--td-text-secondary)', marginTop: 4, fontWeight: 600 }}>{tag}</div>}
    </div>
  );
}

export function Button({
  children, onClick, variant = 'default', type = 'button', disabled,
}: { children: ReactNode; onClick?: () => void; variant?: 'default' | 'primary' | 'danger'; type?: 'button' | 'submit'; disabled?: boolean }) {
  const styles: Record<string, CSSProperties> = {
    default: { background: 'var(--td-surface)', color: 'var(--td-text)', border: '1px solid var(--td-border)' },
    primary: { background: 'var(--td-accent)', color: '#fff', border: '1px solid var(--td-accent)' },
    danger: { background: '#fff', color: 'var(--td-red)', border: '1px solid var(--td-red)' },
  };
  return (
    <button
      type={type}
      onClick={onClick}
      disabled={disabled}
      style={{
        ...styles[variant],
        fontSize: 12.5, fontWeight: 700, padding: '8px 14px', borderRadius: 5, cursor: disabled ? 'not-allowed' : 'pointer',
        opacity: disabled ? 0.5 : 1,
      }}
    >
      {children}
    </button>
  );
}

export interface Column<T> {
  key: string;
  label: string;
  render?: (row: T) => ReactNode;
  align?: 'left' | 'right' | 'center';
  width?: string;
}

export function DataTable<T extends { id: number | string }>({ columns, rows, onRowClick, emptyMessage }: {
  columns: Column<T>[]; rows: T[]; onRowClick?: (row: T) => void; emptyMessage?: string;
}) {
  return (
    <table>
      <thead>
        <tr style={{ background: '#f8f8f9', textAlign: 'left' }}>
          {columns.map((c) => (
            <th key={c.key} style={{ padding: '10px 16px', fontSize: 10.5, color: 'var(--td-text-muted)', textTransform: 'uppercase', textAlign: c.align ?? 'left', width: c.width }}>
              {c.label}
            </th>
          ))}
        </tr>
      </thead>
      <tbody>
        {rows.length === 0 && (
          <tr><td colSpan={columns.length} style={{ padding: '24px 16px', textAlign: 'center', color: 'var(--td-text-muted)', fontSize: 12.5 }}>{emptyMessage ?? 'No records'}</td></tr>
        )}
        {rows.map((row) => (
          <tr
            key={row.id}
            onClick={onRowClick ? () => onRowClick(row) : undefined}
            style={{ borderTop: '1px solid var(--td-divider)', cursor: onRowClick ? 'pointer' : 'default' }}
          >
            {columns.map((c) => (
              <td key={c.key} style={{ padding: '11px 16px', fontSize: 12.5, color: 'var(--td-text)', textAlign: c.align ?? 'left' }}>
                {c.render ? c.render(row) : (row as Record<string, unknown>)[c.key] as ReactNode}
              </td>
            ))}
          </tr>
        ))}
      </tbody>
    </table>
  );
}

export function Field({ label, children, span }: { label: string; children: ReactNode; span?: number }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 4, gridColumn: span ? `span ${span}` : undefined }}>
      <label style={{ fontSize: 10.5, color: 'var(--td-text-muted)', textTransform: 'uppercase', fontWeight: 700, letterSpacing: 0.3 }}>{label}</label>
      {children}
    </div>
  );
}

export function FormGrid({ children, columns = 4 }: { children: ReactNode; columns?: number }) {
  return <div style={{ display: 'grid', gridTemplateColumns: `repeat(${columns}, 1fr)`, gap: 14 }}>{children}</div>;
}

export function money(n: number | undefined | null) {
  if (n === undefined || n === null) return '—';
  return `₹${Number(n).toLocaleString('en-IN', { maximumFractionDigits: 2 })}`;
}

export function qty(n: number | undefined | null) {
  if (n === undefined || n === null) return '—';
  return Number(n).toLocaleString('en-IN', { maximumFractionDigits: 3 });
}
