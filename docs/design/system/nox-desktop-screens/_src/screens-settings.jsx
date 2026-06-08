// ─────────────────────────────────────────────────────────────
// NOX · Settings flow (7.1 / 7.2 / 7.3 / 7.4 / 7.6 / 7.7)
// Verbatim EN microcopy from specs.
// ─────────────────────────────────────────────────────────────

const RAW_ID = 'k7Qz9mN2pX4rT8wL3vB6yH1sD5fG0jCaE2uI4oP6qR8tYwZ1xV3bN5mK7uJ';

// ── shared list controls ─────────────────────────────────────
const ListTile = ({ t, leading, headline, supporting, trailing, color, divider }) => (
  <div style={{ borderBottom: divider ? `1px solid ${t.outlineVariant}` : 'none' }}>
    <div style={{ display: 'flex', alignItems: 'center', gap: 16, padding: '0 16px', minHeight: 56 }}>
      {leading && <Icon name={leading} size={24} color={color || t.onSurfaceVariant} />}
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ ...ty('bodyLarge'), color: color || t.onSurface }}>{headline}</div>
        {supporting && <div style={{ ...ty('bodyMedium'), color: t.onSurfaceVariant }}>{supporting}</div>}
      </div>
      {trailing}
    </div>
  </div>
);

const SwitchTile = ({ t, label, on }) => (
  <div style={{ display: 'flex', alignItems: 'center', gap: 16, padding: '12px 16px', minHeight: 56 }}>
    <span style={{ ...ty('bodyLarge'), color: t.onSurface, flex: 1 }}>{label}</span>
    <div style={{ width: 52, height: 32, borderRadius: SHAPE.full, background: on ? t.primary : t.surfaceContainerHighest, border: on ? 'none' : `2px solid ${t.outline}`, position: 'relative', transition: 'all .15s' }}>
      <div style={{ position: 'absolute', top: on ? 4 : 6, left: on ? 24 : 6, width: on ? 24 : 16, height: on ? 24 : 16, borderRadius: '50%', background: on ? t.onPrimary : t.outline, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        {on && <Icon name="check" size={16} color={t.primary} />}
      </div>
    </div>
  </div>
);

const RadioTile = ({ t, label, selected }) => (
  <div style={{ margin: '0 12px 4px', borderRadius: SHAPE.m, background: selected ? t.surfaceContainerHigh : 'transparent', display: 'flex', alignItems: 'center', gap: 16, padding: '14px 16px', minHeight: 56, boxSizing: 'border-box' }}>
    <div style={{ width: 20, height: 20, borderRadius: '50%', border: `2px solid ${selected ? t.primary : t.onSurfaceVariant}`, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
      {selected && <div style={{ width: 10, height: 10, borderRadius: '50%', background: t.primary }} />}
    </div>
    <span style={{ ...ty('bodyLarge'), color: t.onSurface, flex: 1 }}>{label}</span>
  </div>
);

// permission/info banner (general)
const InfoBanner = ({ t, icon, title, message, action }) => (
  <div style={{ background: t.surfaceContainer, boxShadow: elev(3, t.dark), padding: '12px 16px', display: 'flex', gap: 12, flexShrink: 0 }}>
    <Icon name={icon} size={22} color={t.onSurfaceVariant} style={{ marginTop: 2 }} />
    <div style={{ flex: 1 }}>
      <div style={{ ...ty('bodyMedium'), color: t.onSurface, fontWeight: 500 }}>{title}</div>
      <div style={{ ...ty('bodyMedium'), color: t.onSurfaceVariant, marginTop: 2 }}>{message}</div>
      {action && <div style={{ marginTop: 8 }}><span style={{ ...ty('labelLarge'), color: t.primary }}>{action}</span></div>}
    </div>
  </div>
);

// identity card (§9.4)
const IdentityCard = ({ t, editing = false, idShown = false }) => (
  <div style={{ margin: '8px 16px 16px', background: t.surfaceContainerLow, borderRadius: SHAPE.m, boxShadow: elev(1, t.dark), padding: 16 }}>
    {/* name block */}
    <div style={{ ...ty('bodyMedium'), color: t.onSurfaceVariant, marginBottom: 6 }}>Name</div>
    {editing ? (
      <TextField t={t} value="Nyx" focused counter="3/32" suffix={null} />
    ) : (
      <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
        <span style={{ ...ty('titleMedium'), color: t.onSurface, flex: 1 }}>Nyx</span>
        <Icon name="edit" size={20} color={t.onSurfaceVariant} />
      </div>
    )}
    <div style={{ height: 1, background: t.outlineVariant, margin: '16px 0' }} />
    {/* id block */}
    <div style={{ ...ty('bodyMedium'), color: t.onSurfaceVariant, marginBottom: 6 }}>Your ID</div>
    {idShown ? (
      <div>
        <div style={{ fontFamily: MONO, fontSize: 16, lineHeight: '24px', color: t.onSurfaceVariant, wordBreak: 'break-all', marginBottom: 8 }}>{RAW_ID}</div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <Icon name="visibility_off" size={22} color={t.onSurfaceVariant} />
          <Icon name="content_copy" size={22} color={t.onSurfaceVariant} />
          <Icon name="qr_code" size={22} color={t.onSurfaceVariant} />
        </div>
      </div>
    ) : (
      <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
        <span style={{ fontFamily: MONO, fontSize: 16, color: t.onSurface, flex: 1, letterSpacing: 2 }}>••••••••</span>
        <Icon name="visibility" size={22} color={t.onSurfaceVariant} />
        <Icon name="content_copy" size={22} color={t.onSurfaceVariant} />
        <Icon name="qr_code" size={22} color={t.onSurfaceVariant} />
      </div>
    )}
  </div>
);

// deterministic fake QR matrix
function qrMatrix(n = 25, seed = 7) {
  const m = Array.from({ length: n }, () => Array(n).fill(false));
  const finder = (r, c) => {
    for (let i = -1; i <= 7; i++) for (let j = -1; j <= 7; j++) {
      const rr = r + i, cc = c + j;
      if (rr < 0 || cc < 0 || rr >= n || cc >= n) continue;
      const border = i === 0 || i === 6 || j === 0 || j === 6;
      const core = i >= 2 && i <= 4 && j >= 2 && j <= 4;
      m[rr][cc] = (i >= 0 && i <= 6 && j >= 0 && j <= 6) ? (border || core) : false;
    }
  };
  let s = seed;
  const rnd = () => (s = (s * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff;
  for (let r = 0; r < n; r++) for (let c = 0; c < n; c++) {
    const inFinder = (r < 8 && c < 8) || (r < 8 && c >= n - 8) || (r >= n - 8 && c < 8);
    if (!inFinder) m[r][c] = rnd() > 0.5;
  }
  finder(0, 0); finder(0, n - 7); finder(n - 7, 0);
  return m;
}
const FakeQR = ({ size = 200 }) => {
  const n = 25, m = qrMatrix(n);
  const cell = size / n;
  return (
    <div style={{ width: size, height: size, position: 'relative', background: BRAND.qrSurface }}>
      {m.map((row, r) => row.map((on, c) => on ? (
        <div key={r + '-' + c} style={{ position: 'absolute', left: c * cell, top: r * cell, width: cell, height: cell, background: BRAND.qrInk }} />
      ) : null))}
    </div>
  );
};

// QR modal bottom sheet overlay
const QRSheet = ({ t }) => (
  <div style={{ position: 'absolute', inset: 0, zIndex: 10 }}>
    <div style={{ position: 'absolute', inset: 0, background: hexA(t.scrim, 0.4) }} />
    <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, background: t.surface, borderTopLeftRadius: SHAPE.xl, borderTopRightRadius: SHAPE.xl, boxShadow: elev(5, t.dark), padding: '12px 24px 32px', display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
      <div style={{ width: 32, height: 4, borderRadius: 2, background: hexA(t.onSurfaceVariant, 0.4), marginBottom: 20 }} />
      <div style={{ ...ty('titleLarge'), color: t.onSurface, marginBottom: 20 }}>Your ID QR</div>
      <div style={{ padding: 16, background: BRAND.qrSurface, borderRadius: SHAPE.m }}>
        <FakeQR size={220} />
      </div>
      <div style={{ marginTop: 20 }}><TextButton t={t} label="Close" /></div>
    </div>
  </div>
);

// Logout AlertDialog overlay
const LogoutDialog = ({ t, loading = false }) => (
  <div style={{ position: 'absolute', inset: 0, zIndex: 10, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 24 }}>
    <div style={{ position: 'absolute', inset: 0, background: hexA(t.scrim, 0.4) }} />
    <div style={{ position: 'relative', background: t.surfaceContainerHigh, borderRadius: SHAPE.xl, boxShadow: elev(5, t.dark), padding: 24, maxWidth: 312 }}>
      <div style={{ ...ty('headlineSmall'), color: t.onSurface, marginBottom: 16 }}>Log out?</div>
      <div style={{ ...ty('bodyMedium'), color: t.onSurfaceVariant, marginBottom: 24 }}>Your ID and local data will be removed from this device.</div>
      <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8, alignItems: 'center' }}>
        <TextButton t={t} label="Cancel" />
        {loading
          ? <div style={{ padding: '0 16px' }}><Spinner size={20} color={t.error} /></div>
          : <TextButton t={t} label="Log out" color={t.error} />}
      </div>
    </div>
  </div>
);

// ── 7.1 Settings root ────────────────────────────────────────
// state: 'loaded' | 'id-shown' | 'editing' | 'qr' | 'logout' | 'logout-loading'
// grouped settings card + rich nav row
const SettingsGroup = ({ t, children }) => (
  <div style={{ margin: '4px 16px 16px', background: t.surfaceContainerLow, borderRadius: SHAPE.l, overflow: 'hidden', boxShadow: elev(1, t.dark) }}>{children}</div>
);
// grouped radio row (7.4)
const SettingsRadioRow = ({ t, label, selected, last }) => (
  <div style={{ display: 'flex', alignItems: 'center', gap: 16, padding: '14px 16px', borderBottom: last ? 'none' : `1px solid ${t.outlineVariant}`, background: selected ? hexA(t.primary, 0.10) : 'transparent' }}>
    <div style={{ width: 20, height: 20, borderRadius: '50%', border: `2px solid ${selected ? t.primary : t.onSurfaceVariant}`, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
      {selected && <div style={{ width: 10, height: 10, borderRadius: '50%', background: t.primary }} />}
    </div>
    <span style={{ ...ty('bodyLarge'), color: t.onSurface, flex: 1 }}>{label}</span>
  </div>
);
// grouped switch row (7.2)
const SettingsSwitchRow = ({ t, icon, label, sub, on }) => (
  <div style={{ display: 'flex', alignItems: 'center', gap: 16, padding: '14px 16px' }}>
    <div style={{ width: 40, height: 40, borderRadius: '50%', background: t.secondaryContainer, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
      <Icon name={icon} size={22} color={t.onSecondaryContainer} />
    </div>
    <div style={{ flex: 1, minWidth: 0 }}>
      <div style={{ ...ty('bodyLarge'), color: t.onSurface }}>{label}</div>
      {sub && <div style={{ ...ty('bodyMedium'), color: t.onSurfaceVariant }}>{sub}</div>}
    </div>
    <div style={{ width: 52, height: 32, borderRadius: SHAPE.full, background: on ? t.primary : t.surfaceContainerHighest, border: on ? 'none' : `2px solid ${t.outline}`, position: 'relative', flexShrink: 0 }}>
      <div style={{ position: 'absolute', top: on ? 4 : 6, left: on ? 24 : 6, width: on ? 24 : 16, height: on ? 24 : 16, borderRadius: '50%', background: on ? t.onPrimary : t.outline, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        {on && <Icon name="check" size={16} color={t.primary} />}
      </div>
    </div>
  </div>
);
const SettingsNavRow = ({ t, icon, label, last, danger, trailing }) => {
  const fg = danger ? t.error : t.onSurface;
  const iconBg = danger ? hexA(t.error, 0.14) : t.secondaryContainer;
  const iconFg = danger ? t.error : t.onSecondaryContainer;
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 16, padding: '14px 16px', borderBottom: last ? 'none' : `1px solid ${t.outlineVariant}` }}>
      <div style={{ width: 40, height: 40, borderRadius: '50%', background: iconBg, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
        <Icon name={icon} size={22} color={iconFg} fill={danger ? 1 : 0} />
      </div>
      <span style={{ ...ty('bodyLarge'), color: fg, flex: 1 }}>{label}</span>
      {trailing || (!danger && <Icon name="chevron_right" size={22} color={t.onSurfaceVariant} />)}
    </div>
  );
};

const SettingsRootScreen = ({ t, state = 'loaded' }) => (
  <>
    <AppBar t={t} title="Settings" />
    <div style={{ flex: 1, minHeight: 0, overflow: 'hidden' }}>
      <IdentityCard t={t} editing={state === 'editing'} idShown={state === 'id-shown'} />
      <SettingsGroup t={t}>
        <SettingsNavRow t={t} icon="notifications" label="Notifications" />
        <SettingsNavRow t={t} icon="palette" label="Appearance" />
        <SettingsNavRow t={t} icon="language" label="Language" />
        <SettingsNavRow t={t} icon="description" label="Terms" />
        <SettingsNavRow t={t} icon="info" label="About" last />
      </SettingsGroup>
      <SettingsGroup t={t}>
        <SettingsNavRow t={t} icon="logout" label="Log out" danger last />
      </SettingsGroup>
    </div>
    <BottomBar t={t} active="settings" />
    {state === 'qr' && <QRSheet t={t} />}
    {(state === 'logout' || state === 'logout-loading') && <LogoutDialog t={t} loading={state === 'logout-loading'} />}
  </>
);

// ── 7.2 Notifications ────────────────────────────────────────
const NotificationsScreen = ({ t, denied = false, on = true }) => (
  <>
    <AppBar t={t} leading="back" title="Notifications" />
    {denied && <InfoBanner t={t} icon="notifications_off" title="Notifications are blocked" message="Allow notifications in system settings to receive messages from your chats." action="Open settings" />}
    <div style={{ flex: 1, paddingTop: 4 }}>
      <SettingsGroup t={t}>
        <SettingsSwitchRow t={t} icon="notifications" label="Enable notifications" sub="Only for chats you're in" on={denied ? false : on} />
      </SettingsGroup>
    </div>
  </>
);

// ── 7.3 Appearance ───────────────────────────────────────────
// mini theme preview thumbnail
const MiniInner = ({ c }) => (
  <div style={{ position: 'absolute', inset: 0, background: c.surface, display: 'flex', flexDirection: 'column' }}>
    <div style={{ height: 16, display: 'flex', alignItems: 'center', padding: '0 8px' }}>
      <div style={{ width: 18, height: 4, borderRadius: 2, background: c.onSurface, opacity: 0.65 }} />
    </div>
    <div style={{ height: 2, margin: '0 8px', borderRadius: 1, background: `linear-gradient(90deg, ${BRAND.teal}, ${BRAND.gold}, ${BRAND.coral})` }} />
    {[BRAND.teal, BRAND.coral].map((dot, i) => (
      <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 6, padding: '6px 8px' }}>
        <div style={{ width: 14, height: 14, borderRadius: '50%', background: dot, flexShrink: 0 }} />
        <div style={{ flex: 1 }}>
          <div style={{ width: '72%', height: 4, borderRadius: 2, background: c.onSurface, opacity: 0.7, marginBottom: 4 }} />
          <div style={{ width: '46%', height: 4, borderRadius: 2, background: c.onSurfaceVariant, opacity: 0.55 }} />
        </div>
      </div>
    ))}
  </div>
);
const Thumb = ({ mode, ring }) => (
  <div style={{ width: 96, height: 76, borderRadius: SHAPE.s, overflow: 'hidden', position: 'relative', flexShrink: 0, boxShadow: `0 0 0 1px ${hexA('#000000', 0.12)}` }}>
    {mode === 'dark' ? <MiniInner c={DARK} />
      : mode === 'light' ? <MiniInner c={LIGHT} />
      : <>
          <MiniInner c={LIGHT} />
          <div style={{ position: 'absolute', inset: 0, clipPath: 'polygon(100% 0, 100% 100%, 0 100%)' }}><MiniInner c={DARK} /></div>
          <div style={{ position: 'absolute', inset: 0, background: `linear-gradient(45deg, transparent calc(50% - 1px), ${hexA('#FFFFFF', 0.5)} 50%, transparent calc(50% + 1px))` }} />
        </>}
  </div>
);
const ThemeOptionCard = ({ t, mode, label, sub, selected }) => (
  <div style={{ margin: '0 16px 12px', display: 'flex', alignItems: 'center', gap: 16, padding: 12, borderRadius: SHAPE.m, border: `${selected ? 2 : 1}px solid ${selected ? t.primary : t.outlineVariant}`, background: selected ? t.surfaceContainerHigh : 'transparent', boxSizing: 'border-box' }}>
    <Thumb mode={mode} />
    <div style={{ flex: 1, minWidth: 0 }}>
      <div style={{ ...ty('titleMedium'), color: t.onSurface }}>{label}</div>
      <div style={{ ...ty('bodyMedium'), color: t.onSurfaceVariant }}>{sub}</div>
    </div>
    <div style={{ width: 20, height: 20, borderRadius: '50%', border: `2px solid ${selected ? t.primary : t.onSurfaceVariant}`, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
      {selected && <div style={{ width: 10, height: 10, borderRadius: '50%', background: t.primary }} />}
    </div>
  </div>
);
const AppearanceScreen = ({ t, value = 'System' }) => (
  <>
    <AppBar t={t} leading="back" title="Appearance" />
    <div style={{ flex: 1, minHeight: 0, overflow: 'hidden', paddingTop: 6 }}>
      <ThemeOptionCard t={t} mode="system" label="System" sub="Match your device" selected={value === 'System'} />
      <ThemeOptionCard t={t} mode="light" label="Light" sub="Always light" selected={value === 'Light'} />
      <ThemeOptionCard t={t} mode="dark" label="Dark" sub="Always dark" selected={value === 'Dark'} />
    </div>
  </>
);

// ── 7.4 Language ─────────────────────────────────────────────
// circular flags (simple SVG) + system glyph
const FlagUA = ({ size = 28 }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" style={{ flexShrink: 0, display: 'block' }}>
    <defs><clipPath id="noxUA"><circle cx="12" cy="12" r="12" /></clipPath></defs>
    <g clipPath="url(#noxUA)">
      <rect width="24" height="12" fill="#005BBB" />
      <rect y="12" width="24" height="12" fill="#FFD500" />
    </g>
  </svg>
);
const FlagUK = ({ size = 28 }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" style={{ flexShrink: 0, display: 'block' }}>
    <defs><clipPath id="noxUK"><circle cx="12" cy="12" r="12" /></clipPath></defs>
    <g clipPath="url(#noxUK)">
      <rect width="24" height="24" fill="#012169" />
      <path d="M0,0 L24,24 M24,0 L0,24" stroke="#FFFFFF" strokeWidth="5" />
      <path d="M0,0 L24,24 M24,0 L0,24" stroke="#C8102E" strokeWidth="2.5" />
      <rect x="9" width="6" height="24" fill="#FFFFFF" />
      <rect y="9" width="24" height="6" fill="#FFFFFF" />
      <rect x="10" width="4" height="24" fill="#C8102E" />
      <rect y="10" width="24" height="4" fill="#C8102E" />
    </g>
  </svg>
);
const LangRow = ({ t, leading, label, selected, last }) => (
  <div style={{ display: 'flex', alignItems: 'center', gap: 16, padding: '14px 16px', borderBottom: last ? 'none' : `1px solid ${t.outlineVariant}`, background: selected ? hexA(t.primary, 0.10) : 'transparent' }}>
    {leading}
    <span style={{ ...ty('bodyLarge'), color: t.onSurface, flex: 1 }}>{label}</span>
    <div style={{ width: 20, height: 20, borderRadius: '50%', border: `2px solid ${selected ? t.primary : t.onSurfaceVariant}`, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
      {selected && <div style={{ width: 10, height: 10, borderRadius: '50%', background: t.primary }} />}
    </div>
  </div>
);
const SysCircle = ({ t }) => (
  <div style={{ width: 28, height: 28, borderRadius: '50%', background: t.secondaryContainer, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
    <Icon name="smartphone" size={17} color={t.onSecondaryContainer} />
  </div>
);
const LanguageScreen = ({ t, value = 'System' }) => (
  <>
    <AppBar t={t} leading="back" title="Language" />
    <div style={{ flex: 1, paddingTop: 4 }}>
      <SettingsGroup t={t}>
        <LangRow t={t} leading={<SysCircle t={t} />} label="System" selected={value === 'System'} />
        <LangRow t={t} leading={<FlagUK />} label="English" selected={value === 'English'} />
        <LangRow t={t} leading={<FlagUA />} label="Українська" selected={value === 'Українська'} last />
      </SettingsGroup>
    </div>
  </>
);

// ── 7.6 Terms ────────────────────────────────────────────────
// Shared body (no app bar) so mobile screen + desktop detail pane stay identical.
const TermsBody = ({ t }) => (
  <div style={{ padding: '8px 16px 16px' }}>
    <div style={{ ...ty('titleLarge'), color: t.onSurface, marginBottom: 12 }}>Terms of Service</div>
    {[
      ['1. Acceptance', 'By using NOX you agree to these terms. NOX is an open, shared messaging space — every chat is visible to everyone.'],
      ['2. Your identity', 'Your account is an anonymous identifier stored only on this device. You are responsible for keeping it safe; losing it means losing access.'],
      ['3. Content', 'You are responsible for what you send. Messages and files are permanent and cannot be deleted once posted.'],
      ['4. Privacy', 'NOX does not collect personal data such as phone numbers or email. See the Privacy Policy for details.'],
    ].map(([h, p]) => (
      <div key={h} style={{ marginBottom: 16 }}>
        <div style={{ ...ty('titleMedium'), color: t.onSurface, marginBottom: 4 }}>{h}</div>
        <div style={{ ...ty('bodyMedium'), color: t.onSurfaceVariant }}>{p}</div>
      </div>
    ))}
    <div style={{ height: 1, background: t.outlineVariant, margin: '8px 0 16px' }} />
    <div style={{ ...ty('bodyMedium'), color: t.onSurfaceVariant }}>Version 1.2.3</div>
  </div>
);
const TermsScreen = ({ t }) => (
  <>
    <AppBar t={t} leading="back" title="Terms" />
    <div style={{ flex: 1, minHeight: 0, overflow: 'hidden' }}>
      <TermsBody t={t} />
    </div>
  </>
);

// ── 7.7 About ────────────────────────────────────────────────
const AboutScreen = ({ t }) => (
  <>
    <AppBar t={t} leading="back" title="About" />
    <div style={{ flex: 1, paddingTop: 4 }}>
      <SettingsGroup t={t}>
        <SettingsNavRow t={t} icon="info" label="Version" last
          trailing={<span style={{ ...ty('bodyMedium'), color: t.onSurfaceVariant }}>1.2.3 (build 456)</span>} />
      </SettingsGroup>
    </div>
  </>
);

Object.assign(window, {
  RAW_ID, ListTile, SwitchTile, RadioTile, InfoBanner, IdentityCard, FakeQR, QRSheet, LogoutDialog,
  SettingsGroup, SettingsSwitchRow, SettingsNavRow, SettingsRadioRow, ThemeOptionCard,
  LangRow, FlagUK, FlagUA, SysCircle, Thumb,
  SettingsRootScreen, NotificationsScreen, AppearanceScreen, LanguageScreen, TermsBody, TermsScreen, AboutScreen,
});
