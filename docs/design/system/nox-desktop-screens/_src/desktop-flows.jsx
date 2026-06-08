// ─────────────────────────────────────────────────────────────
// NOX · Desktop flows & dialogs (C1 + C2 milestone)
// Net-new desktop forms of mobile pushed-screens, plus the
// overlay hosts that float them over a base window.
//   6.1 Create chat   → centered dialog
//   5.3 File view      → centered lightbox
//   5.4 Chat card/Files→ right-side details drawer
//   3.1 Error          → full-window centered state
//   2.2 QR             → "scan with webcam" window + permission
// Everything inside reuses the shared widgets.
// Loads AFTER desktop-screens.jsx.
// ─────────────────────────────────────────────────────────────

// ── 6.1 Create chat · centered dialog ────────────────────────
const CreateChatDialog = ({ t, state = 'valid' }) => {
  const value = state === 'empty' ? '' : (state === 'taken' ? 'Night Owls' : 'Midnight Jazz');
  const error = state === 'taken' ? 'This name is taken' : null;
  const suffix = state === 'checking'
    ? <div style={{ width: 24, height: 24 }}><Spinner size={20} color={t.onSurfaceVariant} /></div> : null;
  const loading = state === 'loading';
  return (
    <div style={{ position: 'absolute', inset: 0, zIndex: 12, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 24 }}>
      <div style={{ position: 'absolute', inset: 0, background: hexA(t.scrim, 0.4) }} />
      <div style={{ position: 'relative', width: 460, maxWidth: '100%', background: t.surface, borderRadius: SHAPE.xl, boxShadow: elev(5, t.dark), padding: '24px 24px 20px' }}>
        <div style={{ ...ty('headlineSmall'), color: t.onSurface, marginBottom: 18 }}>New chat</div>
        <TextField t={t} label="Chat name" value={value} placeholder="e.g. Random thoughts"
          focused={state !== 'empty'} error={error} counter={`${value.length}/64`} suffix={suffix} />
        <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8, alignItems: 'center', marginTop: 24 }}>
          <TextButton t={t} label="Cancel" />
          {loading
            ? <div style={{ padding: '0 16px' }}><Spinner size={20} color={t.primary} /></div>
            : <FilledButton t={t} label="Create" disabled={state !== 'valid'} />}
        </div>
      </div>
    </div>
  );
};

// ── 5.3 File view · centered lightbox ────────────────────────
const FileViewDialog = ({ t, state = 'loaded' }) => (
  <div style={{ position: 'absolute', inset: 0, zIndex: 12, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 24 }}>
    <div style={{ position: 'absolute', inset: 0, background: hexA(t.scrim, 0.55) }} />
    <div style={{ position: 'relative', width: 520, maxWidth: '100%', background: t.surface, borderRadius: SHAPE.xl, boxShadow: elev(5, t.dark), overflow: 'hidden' }}>
      <div style={{ height: 60, display: 'flex', alignItems: 'center', gap: 8, padding: '0 8px 0 20px', borderBottom: `1px solid ${t.outlineVariant}` }}>
        <Icon name={fileIcon('pdf')} size={22} color={fileColor('pdf')} />
        <div style={{ ...ty('titleMedium'), color: t.onSurface, flex: 1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', marginLeft: 4 }}>quarterly-report.pdf</div>
        <IconButton t={t} name="download" />
        <IconButton t={t} name="close" />
      </div>
      {state === 'loading' && (
        <div style={{ height: 4, background: t.surfaceVariant }}><div style={{ width: '64%', height: '100%', background: t.primary }} /></div>
      )}
      <div style={{ padding: '40px 32px 36px', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 18 }}>
        <div style={{ width: 148, height: 148, borderRadius: 32, background: hexA(fileColor('pdf'), 0.14), display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <Icon name="picture_as_pdf" size={84} color={fileColor('pdf')} />
        </div>
        <div style={{ ...ty('titleLarge'), color: t.onSurface, textAlign: 'center' }}>quarterly-report.pdf</div>
        <div style={{ ...ty('bodyMedium'), color: t.onSurfaceVariant }}>{state === 'loading' ? 'Downloading… 64%' : '2.4 MB'}</div>
        {state !== 'loading' && <FilledButton t={t} label="Download" />}
      </div>
    </div>
  </div>
);

// ── 5.4 Chat card / Files · right details drawer ─────────────
const ChatInfoDrawer = ({ t, view = 'list' }) => (
  <div style={{ position: 'absolute', inset: 0, zIndex: 12, display: 'flex', justifyContent: 'flex-end' }}>
    <div style={{ position: 'absolute', inset: 0, background: hexA(t.scrim, 0.32) }} />
    <div style={{ position: 'relative', width: 380, background: t.surface, borderLeft: `1px solid ${t.outlineVariant}`, boxShadow: elev(4, t.dark), display: 'flex', flexDirection: 'column', minHeight: 0 }}>
      <div style={{ height: 60, flexShrink: 0, display: 'flex', alignItems: 'center', gap: 8, padding: '0 8px 0 20px', borderBottom: `1px solid ${t.outlineVariant}` }}>
        <span style={{ ...ty('titleLarge'), color: t.onSurface, flex: 1 }}>Details</span>
        <IconButton t={t} name="close" />
      </div>
      <div style={{ padding: '20px 16px', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 10, borderBottom: `1px solid ${t.outlineVariant}`, flexShrink: 0 }}>
        <div style={{ borderRadius: '50%', boxShadow: `0 0 0 2px ${hexA(t.onSurface, 0.06)}` }}><Avatar name="Night Owls" size={72} /></div>
        <div style={{ ...ty('headlineSmall'), color: t.onSurface }}>Night Owls</div>
        <div style={{ ...ty('bodyMedium'), color: t.onSurfaceVariant }}>Aria, Mox and you</div>
      </div>
      <div style={{ padding: '12px 16px', display: 'flex', alignItems: 'center', justifyContent: 'space-between', flexShrink: 0 }}>
        <span style={{ ...ty('titleMedium'), color: t.onSurface }}>Files</span>
        {view !== 'empty' && <Segmented t={t} options={['List', 'Grid']} value={view === 'grid' ? 'Grid' : 'List'} />}
      </div>
      <div style={{ flex: 1, minHeight: 0, overflow: 'hidden' }}>
        {view === 'empty' ? (
          <EmptyState t={t} glyph="folder_open" title="No files yet" message="Files sent in this chat will appear here." />
        ) : view === 'grid' ? (
          <div style={{ padding: '0 16px', display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: 8 }}>
            {FILES.map((f, i) => (
              <div key={i} style={{ aspectRatio: '1', background: t.surfaceContainerHigh, borderRadius: SHAPE.m, padding: 12, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 8, textAlign: 'center' }}>
                <FileGlyph type={f.type} size={26} box={48} />
                <div style={{ ...ty('labelMedium'), color: t.onSurface, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', maxWidth: '100%' }}>{f.name}</div>
                <div style={{ ...ty('labelSmall'), color: t.onSurfaceVariant }}>{f.size}</div>
              </div>
            ))}
          </div>
        ) : (
          FILES.map((f, i) => (
            <div key={i} className="nox-d-row" style={{ display: 'flex', alignItems: 'center', gap: 16, padding: '10px 16px', '--noxRowHover': hexA(t.onSurface, 0.04) }}>
              <FileGlyph type={f.type} size={24} box={44} />
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ ...ty('titleMedium'), color: t.onSurface, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{f.name}</div>
                <div style={{ ...ty('bodyMedium'), color: t.onSurfaceVariant }}>{f.size}</div>
              </div>
            </div>
          ))
        )}
      </div>
    </div>
  </div>
);

// ── 3.1 Error · full-window centered ─────────────────────────
const DesktopError = ({ t, icon = 'error_outline', title = 'Something went wrong', message = 'Please try again.' }) => (
  <div style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', textAlign: 'center', gap: 18, padding: '0 32px', background: t.surface }}>
    <Icon name={icon} size={96} color={t.onSurfaceVariant} />
    <div style={{ ...ty('headlineSmall'), color: t.onSurface }}>{title}</div>
    <div style={{ ...ty('bodyMedium'), color: t.onSurfaceVariant, maxWidth: 380 }}>{message}</div>
    <div style={{ marginTop: 8 }}><FilledButton t={t} label="Try again" /></div>
  </div>
);
const ErrorDesktop = ({ t, icon, title, message }) => (
  <DesktopWindow t={t} subtitle="Error">
    <DesktopError t={t} icon={icon} title={title} message={message} />
  </DesktopWindow>
);

// ── 2.2 QR · webcam scan window + permission ─────────────────
const Viewfinder = ({ size = 300 }) => {
  const c = { position: 'absolute', width: 40, height: 40, border: `3px solid ${BRAND.white}` };
  return (
    <div style={{ position: 'relative', width: size, height: size, borderRadius: 16, overflow: 'hidden', background: 'radial-gradient(120% 80% at 30% 20%, #2b3a38 0%, #161d1c 45%, #0b100f 100%)' }}>
      <div style={{ ...c, top: 16, left: 16, borderRight: 'none', borderBottom: 'none', borderRadius: '12px 0 0 0' }} />
      <div style={{ ...c, top: 16, right: 16, borderLeft: 'none', borderBottom: 'none', borderRadius: '0 12px 0 0' }} />
      <div style={{ ...c, bottom: 16, left: 16, borderRight: 'none', borderTop: 'none', borderRadius: '0 0 0 12px' }} />
      <div style={{ ...c, bottom: 16, right: 16, borderLeft: 'none', borderTop: 'none', borderRadius: '0 0 12px 0' }} />
    </div>
  );
};
const QRDesktop = ({ t, denied = false }) => (
  <DesktopWindow t={t} subtitle="Scan QR">
    <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', background: t.surface }}>
      {denied ? (
        <OnboardCard t={t}>
          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 14, marginTop: 8, textAlign: 'center' }}>
            <Icon name="no_photography" size={64} color={t.onSurfaceVariant} />
            <div style={{ ...ty('headlineSmall'), color: t.onSurface }}>Camera access needed</div>
            <div style={{ ...ty('bodyMedium'), color: t.onSurfaceVariant, maxWidth: 300 }}>To scan a QR code, allow camera access in system settings.</div>
            <div style={{ marginTop: 4 }}><FilledButton t={t} label="Open settings" /></div>
          </div>
        </OnboardCard>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 22 }}>
          <div style={{ ...ty('titleLarge'), color: t.onSurface }}>Scan a QR code</div>
          <Viewfinder size={300} />
          <div style={{ ...ty('bodyMedium'), color: t.onSurfaceVariant, textAlign: 'center', maxWidth: 340 }}>
            Point your webcam at a code, or <span style={{ color: t.primary }}>enter the ID manually</span>.
          </div>
        </div>
      )}
    </div>
  </DesktopWindow>
);

// ── overlay hosts (float a dialog/drawer over a base window) ──
const CreateChatDesktop = ({ t, state = 'valid' }) => (
  <ChatsDesktop t={t} empty overlay={<CreateChatDialog t={t} state={state} />} />
);
const FileViewDesktop = ({ t, state = 'loaded' }) => (
  <ChatsDesktop t={t} overlay={<FileViewDialog t={t} state={state} />} />
);
const ChatInfoDesktop = ({ t, view = 'list' }) => (
  <ChatsDesktop t={t} overlay={<ChatInfoDrawer t={t} view={view} />} />
);

Object.assign(window, {
  CreateChatDialog, FileViewDialog, ChatInfoDrawer, DesktopError, ErrorDesktop,
  Viewfinder, QRDesktop, CreateChatDesktop, FileViewDesktop, ChatInfoDesktop,
});
