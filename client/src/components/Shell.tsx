import type { ReactNode } from 'react';
import { useNavigate } from 'react-router-dom';
import { MODULES, roleLabel, useAuth } from '../state/AuthContext';

const MODULE_PATH: Record<string, string> = {
  overview: '/overview',
  marketing: '/marketing',
  quotation: '/quotation',
  salesPO: '/sales-po',
  workorder: '/work-order',
  inventory: '/inventory',
  production: '/production',
  qc: '/qc',
  logistics: '/logistics',
  purchase: '/purchase',
};

export function moduleHome(role: string) {
  return MODULE_PATH[role] ?? '/overview';
}

export function Shell({ children, activeModule, title }: { children: ReactNode; activeModule: string; title?: string }) {
  const { role, logout } = useAuth();
  const navigate = useNavigate();
  const isAdmin = role === 'admin';

  return (
    <div style={{ display: 'flex', width: '100%', minHeight: '100vh' }}>
      {isAdmin && (
        <div style={{ width: 216, flexShrink: 0, background: 'var(--td-dark)', minHeight: '100vh', padding: '20px 0', display: 'flex', flexDirection: 'column' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '0 20px 20px', borderBottom: '1px solid #2c323d' }}>
            <div style={{ width: 32, height: 32, background: 'var(--td-accent)', borderRadius: 5, display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--td-dark)', fontWeight: 800, fontSize: 14 }}>TD</div>
            <div style={{ color: '#fff', fontSize: 13.5, fontWeight: 700, letterSpacing: 0.3 }}>THERMODRAIN</div>
          </div>
          <div style={{ padding: '14px 10px', flex: 1, overflowY: 'auto' }}>
            {MODULES.map((m) => {
              const active = activeModule === m.key;
              return (
                <div
                  key={m.key}
                  onClick={() => navigate(MODULE_PATH[m.key])}
                  style={{
                    display: 'flex', alignItems: 'center', gap: 10, padding: '9px 12px', borderRadius: 5, cursor: 'pointer',
                    marginBottom: 2, background: active ? 'var(--td-accent)' : 'transparent', color: active ? 'var(--td-dark)' : '#c7cbd1',
                  }}
                >
                  <div style={{
                    width: 22, height: 22, borderRadius: 4, flexShrink: 0, display: 'flex', alignItems: 'center', justifyContent: 'center',
                    fontSize: 10, fontWeight: 800, background: active ? 'var(--td-dark)' : '#2c323d', color: active ? 'var(--td-accent)' : '#8a91a1',
                  }}>
                    {m.num}
                  </div>
                  <div style={{ fontSize: 12.5, fontWeight: 600 }}>{m.label}</div>
                </div>
              );
            })}
          </div>
          <div style={{ padding: '14px 20px 0', borderTop: '1px solid #2c323d' }}>
            <div style={{ color: '#8a91a1', fontSize: 11, marginBottom: 8 }}>Signed in as <span style={{ color: '#fff', fontWeight: 700 }}>Admin</span></div>
            <div onClick={logout} style={{ color: 'var(--td-accent)', fontSize: 12, fontWeight: 700, cursor: 'pointer' }}>Log out</div>
          </div>
        </div>
      )}

      <div style={{ flex: 1, minWidth: 0, minHeight: '100vh', display: 'flex', flexDirection: 'column' }}>
        {!isAdmin && (
          <div style={{ height: 56, flexShrink: 0, background: '#fff', borderBottom: '1px solid var(--td-border)', display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '0 28px' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <div style={{ width: 26, height: 26, background: 'var(--td-accent)', borderRadius: 5, display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--td-dark)', fontWeight: 800, fontSize: 11 }}>TD</div>
              <div style={{ fontSize: 13.5, fontWeight: 700, color: 'var(--td-text)' }}>Thermodrain ERP</div>
              <div style={{ color: '#c7cbd1' }}>/</div>
              <div style={{ fontSize: 13, fontWeight: 600, color: 'var(--td-text-secondary)' }}>{roleLabel(role)}</div>
            </div>
            <div onClick={logout} style={{ color: 'var(--td-accent)', fontSize: 12, fontWeight: 700, cursor: 'pointer' }}>Log out</div>
          </div>
        )}
        {isAdmin && (
          <div style={{ height: 56, flexShrink: 0, background: '#fff', borderBottom: '1px solid var(--td-border)', display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '0 28px' }}>
            <div style={{ fontSize: 15, fontWeight: 700, color: 'var(--td-text)' }}>{title ?? MODULES.find((m) => m.key === activeModule)?.label}</div>
            <div style={{ fontSize: 12, color: 'var(--td-text-muted)' }}>Admin · full access</div>
          </div>
        )}
        <div style={{ flex: 1, overflowY: 'auto', padding: 28 }}>
          {children}
        </div>
      </div>
    </div>
  );
}
