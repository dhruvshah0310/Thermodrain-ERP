import { NavLink, Outlet } from 'react-router-dom';

const TABS = [
  { to: '/purchase', label: 'Dashboard', end: true },
  { to: '/purchase/indents', label: 'Purchase Indent' },
  { to: '/purchase/sanction-indents', label: 'Sanction Indent' },
  { to: '/purchase/rfqs', label: 'Request for Quote' },
  { to: '/purchase/quotations', label: 'Purchase Quotation' },
  { to: '/purchase/purchase-orders', label: 'Purchase Order' },
  { to: '/purchase/grns', label: 'GRN' },
  { to: '/purchase/vendors', label: 'Vendors' },
  { to: '/purchase/materials', label: 'Materials' },
  { to: '/purchase/reports', label: 'Reports' },
];

export function PurchaseShell() {
  return (
    <div>
      <div style={{ display: 'flex', gap: 2, borderBottom: '1px solid var(--td-border)', marginBottom: 20, overflowX: 'auto' }}>
        {TABS.map((t) => (
          <NavLink
            key={t.to}
            to={t.to}
            end={t.end}
            style={({ isActive }) => ({
              padding: '10px 14px',
              fontSize: 12.5,
              fontWeight: 700,
              color: isActive ? 'var(--td-accent)' : 'var(--td-text-secondary)',
              borderBottom: isActive ? '2px solid var(--td-accent)' : '2px solid transparent',
              whiteSpace: 'nowrap',
            })}
          >
            {t.label}
          </NavLink>
        ))}
      </div>
      <Outlet />
    </div>
  );
}
