import { createContext, useContext, useMemo, useState, type ReactNode } from 'react';

export interface RoleDef {
  key: string;
  label: string;
  sub: string;
  initials: string;
  badgeBg: string;
}

export const ROLES: RoleDef[] = [
  { key: 'admin', label: 'Admin', sub: 'Full access', initials: 'AD', badgeBg: '#1c2129' },
  { key: 'marketing', label: 'Marketing & Leads', sub: 'Mobile app', initials: 'ML', badgeBg: '#e8703a' },
  { key: 'quotation', label: 'Quotation Workflow', sub: 'Operations', initials: 'QW', badgeBg: '#3d6fa8' },
  { key: 'salesPO', label: 'Purchase Order', sub: 'Sales ops', initials: 'PO', badgeBg: '#3d6fa8' },
  { key: 'workorder', label: 'Work Order Mgmt', sub: 'Production', initials: 'WO', badgeBg: '#6a6f78' },
  { key: 'inventory', label: 'Inventory Control', sub: 'Stores', initials: 'IN', badgeBg: '#6a6f78' },
  { key: 'production', label: 'Production Tracking', sub: 'Shop floor', initials: 'PT', badgeBg: '#6a6f78' },
  { key: 'qc', label: 'Quality Control', sub: 'QC team', initials: 'QC', badgeBg: '#c0392b' },
  { key: 'logistics', label: 'Logistics & Dispatch', sub: 'Dispatch', initials: 'LD', badgeBg: '#3d6fa8' },
  { key: 'purchase', label: 'Purchase', sub: 'Raw material & vendor mgmt', initials: 'PU', badgeBg: '#e8703a' },
];

export const MODULES = [
  { key: 'overview', label: 'Overview', num: 'OV' },
  { key: 'marketing', label: 'Marketing & Leads', num: '1' },
  { key: 'quotation', label: 'Quotation Workflow', num: '2' },
  { key: 'salesPO', label: 'Purchase Order', num: '3' },
  { key: 'workorder', label: 'Work Order Mgmt', num: '4' },
  { key: 'inventory', label: 'Inventory Control', num: '5' },
  { key: 'production', label: 'Production Tracking', num: '6' },
  { key: 'qc', label: 'Quality Control', num: '7' },
  { key: 'logistics', label: 'Logistics & Dispatch', num: '8' },
  { key: 'purchase', label: 'Purchase', num: '9' },
];

interface AuthState {
  role: string | null;
  login: (roleKey: string) => void;
  logout: () => void;
}

const AuthContext = createContext<AuthState | null>(null);

const STORAGE_KEY = 'thermodrain.role';

export function AuthProvider({ children }: { children: ReactNode }) {
  const [role, setRole] = useState<string | null>(() => sessionStorage.getItem(STORAGE_KEY));

  const value = useMemo<AuthState>(() => ({
    role,
    login: (roleKey: string) => {
      sessionStorage.setItem(STORAGE_KEY, roleKey);
      setRole(roleKey);
    },
    logout: () => {
      sessionStorage.removeItem(STORAGE_KEY);
      setRole(null);
    },
  }), [role]);

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within AuthProvider');
  return ctx;
}

export function roleLabel(key: string | null) {
  return ROLES.find((r) => r.key === key)?.label ?? '';
}
