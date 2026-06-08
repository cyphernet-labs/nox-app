// ─────────────────────────────────────────────────────────────
// NOX · Desktop shell (Windows / Linux / macOS · Flutter)
// The "wrapper" that differs from mobile. Everything INSIDE the
// panes reuses the exact same widgets as the phone build.
//   mobile BottomBar  →  desktop NavigationRail
//   mobile full screen →  desktop list-detail panes
//   mobile bottom-sheet→  desktop centered dialog
// Canonical window: 1440 × 900 (M3 "expanded" window-size class).
// ─────────────────────────────────────────────────────────────

// one-time desktop CSS (hover affordances — desktop-only state)
if (typeof document !== 'undefined' && !document.getElementById('nox-desktop-css')) {
  const s = document.createElement('style');
  s.id = 'nox-desktop-css';
  s.textContent = [
    '.nox-d-row{cursor:pointer;transition:background .12s}',
    '.nox-d-row:hover{background:var(--noxRowHover)}',
    '.nox-d-ctl{cursor:default;transition:background .12s}',
    '.nox-d-ctl:hover{background:var(--noxCtlHover)}',
    '.nox-d-fab{cursor:pointer;transition:filter .12s, box-shadow .12s}',
    '.nox-d-fab:hover{filter:brightness(1.04)}',
  ].join('\n');
  document.head.appendChild(s);
}

// Custom unified title bar — a branded Flutter desktop window draws its own.
// OS-neutral: wordmark left, window controls right, brand hairline beneath.
const TitleBar = ({ t, title = 'NOX', subtitle }) => (
  <div style={{ flexShrink: 0 }}>
    <div style={{
      height: 44, background: t.surfaceContainerLow,
      display: 'flex', alignItems: 'center', gap: 10, padding: '0 8px 0 16px',
    }}>
      <img src="assets/logo.png" alt="" style={{ width: 18, height: 18, objectFit: 'contain', opacity: 0.95 }} />
      <span style={{ fontFamily: SANS, fontSize: 13, fontWeight: 700, letterSpacing: '0.14em', color: t.onSurface }}>{title}</span>
      {subtitle && <span style={{ ...ty('bodyMedium'), color: t.onSurfaceVariant, marginLeft: 2 }}>— {subtitle}</span>}
      {/* draggable region */}
      <div style={{ flex: 1 }} />
      {/* window controls — neutral, custom-drawn */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 2 }}>
        {['remove', 'crop_square', 'close'].map((g) => (
          <div key={g} className="nox-d-ctl" style={{
            width: 36, height: 28, borderRadius: 6,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            '--noxCtlHover': hexA(t.onSurface, 0.08),
          }}>
            <Icon name={g} size={16} color={t.onSurfaceVariant} />
          </div>
        ))}
      </div>
    </div>
    {/* signature brand-splash hairline — same motif as mobile app bars */}
    <div style={{ height: 3, background: `linear-gradient(90deg, ${BRAND.teal}, ${BRAND.lime}, ${BRAND.gold}, ${BRAND.coral}, ${BRAND.red})` }} />
  </div>
);

// The desktop window. Fills its artboard edge-to-edge (maximised look).
const DesktopWindow = ({ t, title = 'NOX', subtitle, chrome = true, children }) => (
  <div style={{
    width: '100%', height: '100%', background: t.surface,
    display: 'flex', flexDirection: 'column', overflow: 'hidden',
    fontFamily: SANS, position: 'relative',
  }}>
    {chrome && <TitleBar t={t} title={title} subtitle={subtitle} />}
    <div style={{ flex: 1, minHeight: 0, display: 'flex', position: 'relative' }}>
      {children}
    </div>
  </div>
);

// NavigationRail — replaces the mobile BottomAppBar + docked FAB.
// Top FAB == the mobile "+" ; destinations == the two mobile tabs ;
// account avatar pinned to the bottom.
const NavRail = ({ t, active = 'chats', onFab }) => {
  const dest = (icon, label, key) => {
    const sel = active === key;
    return (
      <div key={key} className="nox-d-row" style={{
        display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4,
        width: '100%', padding: '4px 0', borderRadius: 12,
        '--noxRowHover': hexA(t.onSurface, 0.04),
      }}>
        <div style={{
          width: 56, height: 32, borderRadius: SHAPE.full,
          background: sel ? t.secondaryContainer : 'transparent',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>
          <Icon name={icon} size={24} color={sel ? t.onSecondaryContainer : t.onSurfaceVariant} fill={sel ? 1 : 0} />
        </div>
        <span style={{ ...ty('labelMedium'), color: sel ? t.onSurface : t.onSurfaceVariant }}>{label}</span>
      </div>
    );
  };
  return (
    <div style={{
      width: 80, flexShrink: 0, background: t.surface,
      borderRight: `1px solid ${t.outlineVariant}`,
      display: 'flex', flexDirection: 'column', alignItems: 'center',
      padding: '16px 8px 18px', boxSizing: 'border-box',
    }}>
      {/* FAB — same role as the mobile docked + */}
      <div className="nox-d-fab" style={{
        width: 56, height: 56, borderRadius: SHAPE.l, background: t.primaryContainer,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        boxShadow: elev(2, t.dark), marginBottom: 22, flexShrink: 0,
      }}>
        <Icon name="add" size={26} color={t.onPrimaryContainer} />
      </div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 12, width: '100%' }}>
        {dest('forum', 'Chats', 'chats')}
        {dest('settings', 'Settings', 'settings')}
      </div>
      <div style={{ flex: 1 }} />
      <div style={{ borderRadius: '50%', boxShadow: `0 0 0 2px ${hexA(t.onSurface, 0.06)}` }}>
        <Avatar name="Nyx" size={36} />
      </div>
    </div>
  );
};

// A pane header (the desktop stand-in for a mobile top app bar inside a pane).
const PaneHeader = ({ t, title, actions = [], children, dense = false }) => (
  <div style={{
    height: dense ? 60 : 64, flexShrink: 0, display: 'flex', alignItems: 'center',
    gap: 8, padding: '0 8px 0 20px', background: t.surface,
  }}>
    {children || <span style={{ ...ty('titleLarge'), color: t.onSurface, flex: 1 }}>{title}</span>}
    {children && <div style={{ flex: 1 }} />}
    {actions.map((a, i) => <IconButton key={i} t={t} name={a} />)}
  </div>
);

Object.assign(window, { TitleBar, DesktopWindow, NavRail, PaneHeader });
