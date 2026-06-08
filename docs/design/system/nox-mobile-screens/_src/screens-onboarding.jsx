// ─────────────────────────────────────────────────────────────
// NOX · Onboarding screens (1.1, 2.1, 2.2, 2.3, 3.1)
// Each screen renders INSIDE the content area of <Phone>.
// Microcopy is verbatim (EN) from the screen specs.
// ─────────────────────────────────────────────────────────────

const SAMPLE_ID = 'k7Qz9mN2pX4rT8wL3vB6yH1sD5fG0jCaE2uI4oP6qR8tYwZ1xV3bN5mK7uJ';
const SAMPLE_NAME = 'User1234';  // generated default handle — single source for mobile + desktop

// ── 1.1 Splash — brand-fixed dark, NOT themed ────────────────
const SplashScreen = () => (
  <div style={{
    position: 'absolute', inset: 0, background: BRAND.canvasDark,
    display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 20,
  }}>
    <img src="assets/logo.png" alt="NOX" style={{
      width: 168, height: 168, objectFit: 'contain',
      animation: 'noxSplashIn 0.6s cubic-bezier(0.05,0.7,0.1,1) both',
    }} />
    <div style={{
      fontFamily: SANS, fontSize: 28, fontWeight: 700, letterSpacing: '0.12em', color: BRAND.white,
      animation: 'noxSplashIn 0.6s cubic-bezier(0.05,0.7,0.1,1) both',
    }}>NOX</div>
  </div>
);

// ── 2.1 Login ────────────────────────────────────────────────
// state: 'empty' | 'filled' | 'loading' | 'error-format' | 'error-net'
const LoginScreen = ({ t, state = 'empty' }) => {
  const hasValue = state !== 'empty';
  const value = hasValue ? SAMPLE_ID : '';
  const loading = state === 'loading';
  const errorText = state === 'error-format' ? 'Invalid identifier'
    : state === 'error-net' ? 'Could not sign in. Check your connection and try again.'
    : null;
  const pasteColor = state === 'empty' ? hexA(t.onSurface, 0.38) : t.onSurfaceVariant;
  return (
    <>
      <AppBar t={t} wordmark />
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', padding: '8px 16px 24px', minHeight: 0 }}>
        <div style={{ marginTop: 12 }}>
          <TextField
            t={t} label="Your ID" value={value}
            placeholder="Paste or enter your ID"
            mono multiline minHeight={120}
            focused={state === 'filled'}
            error={errorText}
            suffix={
              <div style={{ width: 40, height: 40, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <Icon name="content_paste" size={22} color={pasteColor} />
              </div>
            }
          />
        </div>
        <div style={{ flex: 1 }} />
        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4 }}>
          <FilledButton t={t} label="Sign in" full disabled={state === 'empty' || loading} loading={loading} />
          <div style={{ height: 4 }} />
          <TextButton t={t} label="Scan QR" disabled={loading} />
        </div>
      </div>
    </>
  );
};

// ── 2.2 QR scan ──────────────────────────────────────────────
const QRScanScreen = ({ t }) => (
  <>
    <AppBar t={t} leading="back" actions={['flashlight_on', 'cameraswitch']} splash={false} />
    <div style={{ flex: 1, position: 'relative', overflow: 'hidden', background: '#101413' }}>
      {/* simulated camera feed */}
      <div style={{ position: 'absolute', inset: 0, background: 'radial-gradient(120% 80% at 30% 20%, #2b3a38 0%, #161d1c 45%, #0b100f 100%)' }} />
      <div style={{ position: 'absolute', left: '12%', top: '60%', width: 120, height: 80, background: 'rgba(255,255,255,0.04)', borderRadius: 8, transform: 'rotate(-8deg)' }} />
      <div style={{ position: 'absolute', right: '14%', top: '24%', width: 90, height: 60, background: 'rgba(255,255,255,0.03)', borderRadius: 6, transform: 'rotate(10deg)' }} />

      {/* top instruction */}
      <div style={{ position: 'absolute', top: 28, left: 0, right: 0, textAlign: 'center', padding: '0 32px' }}>
        <span style={{ ...ty('bodyLarge'), color: BRAND.white, textShadow: '0 1px 6px rgba(0,0,0,0.7)' }}>
          Aim your camera at a QR code
        </span>
      </div>

      {/* reticle with dark mask (box-shadow spread) */}
      <div style={{
        position: 'absolute', top: '50%', left: '50%', transform: 'translate(-50%,-50%)',
        width: 275, height: 275, borderRadius: 12,
        boxShadow: '0 0 0 2000px rgba(0,0,0,0.55)',
      }}>
        {[['top:-2px;left:-2px', '12px 0 0 0'], ['top:-2px;right:-2px', '0 12px 0 0'], ['bottom:-2px;left:-2px', '0 0 0 12px'], ['bottom:-2px;right:-2px', '0 0 12px 0']].map(([pos, br], i) => {
          const [a, b] = pos.split(';');
          const st = { position: 'absolute', width: 40, height: 40, border: `3px solid ${BRAND.white}`, borderRadius: br };
          const apply = (s) => { const [k, v] = s.split(':'); st[k] = v; };
          apply(a); apply(b);
          // keep only the two outer edges per corner
          if (i === 0) { st.borderRight = 'none'; st.borderBottom = 'none'; }
          if (i === 1) { st.borderLeft = 'none'; st.borderBottom = 'none'; }
          if (i === 2) { st.borderRight = 'none'; st.borderTop = 'none'; }
          if (i === 3) { st.borderLeft = 'none'; st.borderTop = 'none'; }
          return <div key={i} style={st} />;
        })}
      </div>

      {/* bottom action */}
      <div style={{ position: 'absolute', bottom: 24, left: 0, right: 0, display: 'flex', justifyContent: 'center' }}>
        <div style={{ background: 'rgba(0,0,0,0.35)', borderRadius: SHAPE.full }}>
          <span style={{ ...ty('labelLarge'), color: BRAND.white, padding: '10px 16px', display: 'inline-block' }}>Enter manually</span>
        </div>
      </div>
    </div>
  </>
);

// 2.2 permission-denied — opaque surface (NOT over camera)
const QRPermissionScreen = ({ t }) => (
  <>
    <AppBar t={t} leading="back" />
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', textAlign: 'center', padding: '0 32px', gap: 16 }}>
      <Icon name="no_photography" size={72} color={t.onSurfaceVariant} />
      <div style={{ ...ty('headlineSmall'), color: t.onSurface }}>Camera access needed</div>
      <div style={{ ...ty('bodyMedium'), color: t.onSurfaceVariant, maxWidth: 280 }}>
        To scan a QR code, allow camera access in system settings.
      </div>
      <div style={{ marginTop: 8 }}>
        <FilledButton t={t} label="Open settings" />
      </div>
    </div>
  </>
);

// ── 2.3 Set username ─────────────────────────────────────────
// state: 'prefilled' | 'checking' | 'taken' | 'empty'
const SetUsernameScreen = ({ t, state = 'prefilled' }) => {
  const value = state === 'empty' ? '' : (state === 'taken' ? 'Anna' : SAMPLE_NAME);
  const counter = `${value.length}/32`;
  const error = state === 'taken' ? 'This name is taken' : null;
  const focused = state === 'checking' || state === 'taken';
  const suffix = state === 'checking'
    ? <div style={{ width: 24, height: 24 }}><Spinner size={20} color={t.onSurfaceVariant} /></div>
    : null;
  const doneDisabled = state === 'taken' || state === 'empty';
  return (
    <>
      <AppBar t={t} wordmark />
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', padding: '8px 16px 24px', minHeight: 0 }}>
        <div style={{ marginTop: 12 }}>
          <TextField
            t={t} label="Name" value={value}
            placeholder="How others will see you"
            focused={focused} error={error}
            counter={counter} suffix={suffix}
            helper="Others see this name. You can change it now or later in Settings."
          />
        </div>
        <div style={{ flex: 1 }} />
        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4 }}>
          <FilledButton t={t} label="Done" full disabled={doneDisabled} />
          <div style={{ height: 4 }} />
          <TextButton t={t} label="Skip" />
        </div>
      </div>
    </>
  );
};

// ── 3.1 Error ────────────────────────────────────────────────
// mode: 'blocking' | 'embedded'; preset: {icon,title,message}
const ErrorScreen = ({ t, mode = 'blocking', icon = 'error_outline', title = 'Something went wrong', message = 'Please try again.' }) => (
  <>
    {mode === 'embedded' && <AppBar t={t} leading="back" />}
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', textAlign: 'center', padding: '0 32px', gap: 16 }}>
      <Icon name={icon} size={80} color={t.onSurfaceVariant} />
      <div style={{ ...ty('headlineSmall'), color: t.onSurface }}>{title}</div>
      <div style={{ ...ty('bodyMedium'), color: t.onSurfaceVariant, maxWidth: 300 }}>{message}</div>
      <div style={{ marginTop: 8 }}>
        <FilledButton t={t} label="Try again" />
      </div>
    </div>
  </>
);

Object.assign(window, {
  SplashScreen, LoginScreen, QRScanScreen, QRPermissionScreen,
  SetUsernameScreen, ErrorScreen, SAMPLE_ID, SAMPLE_NAME,
});
