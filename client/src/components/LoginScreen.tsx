import { ROLES, useAuth } from '../state/AuthContext';

export function LoginScreen() {
  const { login } = useAuth();
  return (
    <div style={{
      width: '100%', minHeight: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center',
      background: 'linear-gradient(135deg, #1b2029 0%, #262c38 55%, #33261a 100%)',
    }}>
      <div style={{ width: 860, background: '#fff', borderRadius: 4, boxShadow: '0 30px 60px rgba(0,0,0,0.35)', overflow: 'hidden', display: 'flex' }}>
        <div style={{ width: 320, background: 'var(--td-dark)', padding: '40px 32px', display: 'flex', flexDirection: 'column', justifyContent: 'space-between' }}>
          <div>
            <div style={{ width: 44, height: 44, background: 'var(--td-accent)', borderRadius: 6, display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--td-dark)', fontWeight: 800, fontSize: 20 }}>TD</div>
            <div style={{ color: '#fff', fontSize: 22, fontWeight: 700, letterSpacing: 0.3, marginTop: 20 }}>THERMODRAIN</div>
            <div style={{ color: 'var(--td-text-on-dark-muted)', fontSize: 12, letterSpacing: 1.5, marginTop: 4, textTransform: 'uppercase' }}>Manufacturing ERP</div>
          </div>
          <div style={{ color: '#6b7284', fontSize: 12, lineHeight: 1.7 }}>
            Lead → Quotation → PO → Work Order → Production → QC → Dispatch
            <br /><br />
            Select your department to sign in.
          </div>
        </div>
        <div style={{ flex: 1, padding: '36px 32px' }}>
          <div style={{ fontSize: 15, fontWeight: 700, color: 'var(--td-text)', marginBottom: 2 }}>Sign in</div>
          <div style={{ fontSize: 12.5, color: 'var(--td-text-muted)', marginBottom: 18 }}>Each department sees only its own workspace. Admin sees everything.</div>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
            {ROLES.map((r) => (
              <div
                key={r.key}
                onClick={() => login(r.key)}
                style={{ border: '1px solid var(--td-border)', borderRadius: 4, padding: '12px 14px', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 10 }}
                onMouseEnter={(e) => { e.currentTarget.style.borderColor = 'var(--td-accent)'; e.currentTarget.style.background = 'var(--td-accent-soft)'; }}
                onMouseLeave={(e) => { e.currentTarget.style.borderColor = 'var(--td-border)'; e.currentTarget.style.background = 'transparent'; }}
              >
                <div style={{ width: 28, height: 28, borderRadius: 4, background: r.badgeBg, color: '#fff', fontSize: 11, fontWeight: 800, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                  {r.initials}
                </div>
                <div style={{ minWidth: 0 }}>
                  <div style={{ fontSize: 12.5, fontWeight: 700, color: 'var(--td-text)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{r.label}</div>
                  <div style={{ fontSize: 10.5, color: '#9a9fa8' }}>{r.sub}</div>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
