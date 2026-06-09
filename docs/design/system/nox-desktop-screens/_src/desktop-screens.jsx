// ─────────────────────────────────────────────────────────────
// NOX · Desktop screens — list-detail compositions.
// These files contain almost no new "content": they arrange the
// SAME widgets the phone build uses into desktop panes.
// ─────────────────────────────────────────────────────────────

// ============================================================
// CHATS · list-detail (5.1 list  +  5.2 thread, side by side)
// ============================================================

// Selectable chat row — wraps the reused <ChatListItem> with an
// M3 list-detail selection highlight + hover.
const ChatRow = ({ t, selected, ...c }) => (
  <div className="nox-d-row" style={{
    margin: '0 8px', borderRadius: SHAPE.l,
    background: selected ? t.secondaryContainer : 'transparent',
    '--noxRowHover': hexA(t.onSurface, 0.04),
  }}>
    <ChatListItem t={t} {...c} />
  </div>
);

const ChatsListPane = ({ t, selected, state = 'filled', query }) => {
  const isSearch = state === 'search' || state === 'search-empty';
  return (
    <div style={{
      width: 360, flexShrink: 0, background: t.surface,
      borderRight: `1px solid ${t.outlineVariant}`,
      display: 'flex', flexDirection: 'column', minHeight: 0,
    }}>
      <PaneHeader t={t} title="Chats" />
      <SearchBar t={t} value={isSearch ? (query || 'night') : undefined} placeholder="Search" />
      {state === 'offline' && <MaterialBanner t={t} text="No connection" />}
      {state === 'inline-error' && <MaterialBanner t={t} icon="error_outline" text="Couldn’t load chats." action="Retry" />}
      <div style={{ flex: 1, minHeight: 0, overflow: 'hidden', display: 'flex', flexDirection: 'column', paddingTop: 2 }}>
        {state === 'loading' ? (
          <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Spinner size={40} color={t.primary} /></div>
        ) : state === 'empty' ? (
          <EmptyState t={t} glyph="forum" title="No chats yet" message="Press + to create the first one." />
        ) : state === 'search-empty' ? (
          <div style={{ paddingTop: 44, textAlign: 'center' }}><span style={{ ...ty('bodyMedium'), color: t.onSurfaceVariant }}>No chats found</span></div>
        ) : isSearch ? (
          CHATS.filter((c) => c.name.toLowerCase().includes('night')).map((c, i) => <ChatRow key={i} t={t} {...c} selected={c.name === selected} />)
        ) : (
          CHATS.map((c, i) => <ChatRow key={i} t={t} {...c} selected={c.name === selected} />)
        )}
      </div>
    </div>
  );
};

// thread header (replaces mobile back-app-bar; persistent context instead)
const ThreadHeader = ({ t }) => (
  <div style={{
    height: 64, flexShrink: 0, display: 'flex', alignItems: 'center', gap: 14,
    padding: '0 8px 0 24px', borderBottom: `1px solid ${t.outlineVariant}`,
    background: t.surface,
  }}>
    <div style={{ borderRadius: '50%', boxShadow: `0 0 0 2px ${hexA(t.onSurface, 0.06)}` }}>
      <Avatar name="Night Owls" size={40} />
    </div>
    <div style={{ flex: 1, minWidth: 0 }}>
      <div style={{ ...ty('titleMedium'), color: t.onSurface, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>Night Owls</div>
      <div style={{ ...ty('bodyMedium'), color: t.onSurfaceVariant }}>Aria, Mox and you</div>
    </div>
    <IconButton t={t} name="search" />
    <IconButton t={t} name="folder" />
    <IconButton t={t} name="info" />
  </div>
);

// the reused message stream (MsgBubble / DateSep / AuthorHeader / SystemLine),
// constrained to a comfortable reading column for wide windows.
const ThreadMessages = ({ t, state = 'filled' }) => {
  const op = bubblePreset(t, 'current');
  return (
    <div style={{ flex: 1, minHeight: 0, overflow: 'hidden', display: 'flex', flexDirection: 'column', alignItems: 'center', padding: '8px 24px 4px' }}>
      <div style={{ width: '100%', maxWidth: 980, flex: 1, display: 'flex', flexDirection: 'column', justifyContent: 'flex-end' }}>
        <SystemLine t={t} text="Chat created by Aria" />
        <DateSep t={t} label="Today" />
        <AuthorHeader t={t} name="Aria" />
        <MsgBubble t={t} text="Anyone around tonight?" time="22:01" />
        <MsgBubble t={t} text="I’m setting up the room." time="22:01" last />
        <div style={{ height: 12 }} />
        <MsgBubble t={t} mine ownPreset={op} text="On my way." time="22:03" status="sent" />
        <MsgBubble t={t} mine ownPreset={op} file={{ type: 'pdf', name: 'set-list.pdf', size: '240 KB' }} time="22:03" status="sent" last />
        <div style={{ height: 12 }} />
        <AuthorHeader t={t} name="Mox" />
        <MsgBubble t={t} text="Nice. Saving us a spot." time="22:05" last />
        <div style={{ height: 12 }} />
        {state === 'offline'
          ? <MsgBubble t={t} mine ownPreset={op} text="Two minutes." time="22:06" status="pending" last />
          : <MsgBubble t={t} mine ownPreset={op} text="Couldn’t send this one." time="22:06" status="error" last />}
      </div>
    </div>
  );
};

// composer reused, aligned to the same reading column
const ThreadComposer = ({ t, value, attachment, sendActive }) => (
  <div style={{ display: 'flex', justifyContent: 'center' }}>
    <div style={{ width: '100%', maxWidth: 980 }}>
      <Composer t={t} value={value} attachment={attachment} sendActive={sendActive} />
    </div>
  </div>
);

// thread pane — either a live thread or the "no selection" placeholder
const ThreadPane = ({ t, empty = false, state = 'filled', snack = null }) => {
  if (empty) {
    return (
      <div style={{ flex: 1, minWidth: 0, background: t.surfaceContainerLowest, display: 'flex', flexDirection: 'column' }}>
        <EmptyState t={t} glyph="forum" title="Select a chat" message="Choose a conversation on the left, or press + to start a new one." />
      </div>
    );
  }
  const isEmpty = state === 'empty';
  return (
    <div style={{ flex: 1, minWidth: 0, background: t.surfaceContainerLowest, display: 'flex', flexDirection: 'column', minHeight: 0, position: 'relative' }}>
      <ThreadHeader t={t} />
      {state === 'offline' && <MaterialBanner t={t} text="No connection" />}
      {isEmpty ? (
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column' }}>
          <EmptyState t={t} glyph="chat_bubble_outline" title="No messages yet" message="Send the first one." />
        </div>
      ) : (
        <ThreadMessages t={t} state={state} />
      )}
      <ThreadComposer
        t={t}
        value={state === 'attachment' ? 'Here’s the set list' : (isEmpty ? null : 'Two minutes')}
        attachment={state === 'attachment' ? { type: 'pdf', name: 'set-list.pdf', size: '240 KB' } : null}
        sendActive={state === 'attachment' || !isEmpty}
      />
      {snack && (
        <div style={{ position: 'absolute', left: 0, right: 0, bottom: 86, display: 'flex', justifyContent: 'center', padding: '0 24px', zIndex: 5 }}>
          <div style={{ width: '100%', maxWidth: 480 }}><Snackbar t={t} {...snack} /></div>
        </div>
      )}
    </div>
  );
};

const ChatsDesktop = ({ t, empty = false, listState = 'filled', threadState = 'filled', query, snack = null, overlay = null }) => (
  <DesktopWindow t={t} subtitle="Chats">
    <NavRail t={t} active="chats" />
    <ChatsListPane t={t} selected={empty ? null : 'Night Owls'} state={listState} query={query} />
    <ThreadPane t={t} empty={empty} state={threadState} snack={snack} />
    {overlay}
  </DesktopWindow>
);

// ============================================================
// SETTINGS · list-detail (7.1 menu pane  +  selected section)
// ============================================================

const SETTINGS_NAV = [
  { key: 'Account', icon: 'person', group: 0 },
  { key: 'Notifications', icon: 'notifications', group: 1 },
  { key: 'Appearance', icon: 'palette', group: 1 },
  { key: 'Language', icon: 'language', group: 1 },
  { key: 'Terms', icon: 'description', group: 2 },
  { key: 'About', icon: 'info', group: 2 },
];

// selectable settings nav item (the new wrapper element)
const SettingsNavItem = ({ t, icon, label, selected, danger }) => {
  const fg = danger ? t.error : (selected ? t.onSecondaryContainer : t.onSurface);
  const iconBg = danger ? hexA(t.error, 0.14) : (selected ? hexA(t.onSecondaryContainer, 0.12) : t.secondaryContainer);
  const iconFg = danger ? t.error : t.onSecondaryContainer;
  return (
    <div className="nox-d-row" style={{
      display: 'flex', alignItems: 'center', gap: 16, padding: '10px 16px', margin: '0 8px',
      borderRadius: SHAPE.full, background: selected ? t.secondaryContainer : 'transparent',
      '--noxRowHover': hexA(t.onSurface, 0.04),
    }}>
      <div style={{ width: 40, height: 40, borderRadius: '50%', background: iconBg, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
        <Icon name={icon} size={22} color={iconFg} fill={selected || danger ? 1 : 0} />
      </div>
      <span style={{ ...ty('bodyLarge'), color: fg, flex: 1 }}>{label}</span>
    </div>
  );
};

const SettingsListPane = ({ t, selected }) => (
  <div style={{
    width: 340, flexShrink: 0, background: t.surface,
    borderRight: `1px solid ${t.outlineVariant}`,
    display: 'flex', flexDirection: 'column', minHeight: 0,
  }}>
    <PaneHeader t={t} title="Settings" />
    <div style={{ flex: 1, minHeight: 0, overflow: 'hidden', display: 'flex', flexDirection: 'column', gap: 4, paddingTop: 2 }}>
      {[0, 1, 2].map((g) => (
        <div key={g} style={{ paddingBottom: 6, marginBottom: 6, borderBottom: g < 2 ? `1px solid ${t.outlineVariant}` : 'none' }}>
          {SETTINGS_NAV.filter((s) => s.group === g).map((s) => (
            <SettingsNavItem key={s.key} t={t} icon={s.icon} label={s.key} selected={s.key === selected} />
          ))}
        </div>
      ))}
      <div style={{ flex: 1 }} />
      <div style={{ paddingBottom: 10 }}>
        <SettingsNavItem t={t} icon="logout" label="Log out" danger />
      </div>
    </div>
  </div>
);

// detail content — every panel reuses the phone widgets verbatim
const SettingsDetail = ({ t, section, detailState = null }) => {
  const wrap = (children) => (
    <div style={{ flex: 1, minHeight: 0, overflow: 'hidden', background: t.surfaceContainerLowest, display: 'flex', flexDirection: 'column' }}>
      <PaneHeader t={t} title={section} />
      <div style={{ flex: 1, minHeight: 0, overflow: 'hidden', display: 'flex', justifyContent: 'center' }}>
        <div style={{ width: '100%', maxWidth: 680, padding: '4px 8px' }}>{children}</div>
      </div>
    </div>
  );

  if (section === 'Account') {
    return wrap(
      <div>
        <IdentityCard t={t} editing={detailState === 'editing'} />
        {detailState !== 'editing' && (
          <div style={{ margin: '4px 16px 0', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 12, padding: '12px 0 4px' }}>
            <div style={{ padding: 16, background: BRAND.qrSurface, borderRadius: SHAPE.m }}><FakeQR size={184} /></div>
            <div style={{ ...ty('bodyMedium'), color: t.onSurfaceVariant, textAlign: 'center' }}>Show this code to let someone add you</div>
          </div>
        )}
      </div>
    );
  }
  if (section === 'Notifications') {
    return wrap(
      <div>
        {detailState === 'denied' && (
          <div style={{ margin: '4px 16px 12px' }}>
            <InfoBanner t={t} icon="notifications_off" title="Notifications are blocked" message="Allow notifications in system settings to receive messages from your chats." action="Open settings" />
          </div>
        )}
        <SettingsGroup t={t}>
          <SettingsSwitchRow t={t} icon="notifications" label="Enable notifications" sub="Only for chats you're in" on={detailState !== 'denied'} />
        </SettingsGroup>
      </div>
    );
  }
  if (section === 'Appearance') {
    return wrap(
      <div style={{ paddingTop: 6 }}>
        <ThemeOptionCard t={t} mode="system" label="System" sub="Match your device" selected />
        <ThemeOptionCard t={t} mode="light" label="Light" sub="Always light" />
        <ThemeOptionCard t={t} mode="dark" label="Dark" sub="Always dark" />
      </div>
    );
  }
  if (section === 'Language') {
    return wrap(
      <SettingsGroup t={t}>
        <LangRow t={t} leading={<SysCircle t={t} />} label="System" selected />
        <LangRow t={t} leading={<FlagUK />} label="English" />
        <LangRow t={t} leading={<FlagUA />} label="Українська" last />
      </SettingsGroup>
    );
  }
  if (section === 'About') {
    return wrap(
      <SettingsGroup t={t}>
        <SettingsNavRow t={t} icon="info" label="Version" last
          trailing={<span style={{ ...ty('bodyMedium'), color: t.onSurfaceVariant }}>1.2.3 (build 456)</span>} />
      </SettingsGroup>
    );
  }
  // Terms
  return wrap(<TermsBody t={t} />);
};

const SettingsDesktop = ({ t, section = 'Appearance', dialog = null, detailState = null }) => (
  <DesktopWindow t={t} subtitle="Settings">
    <NavRail t={t} active="settings" />
    <SettingsListPane t={t} selected={section} />
    <SettingsDetail t={t} section={section} detailState={detailState} />
    {dialog === 'logout' && <LogoutDialog t={t} />}
    {dialog === 'logout-loading' && <LogoutDialog t={t} loading />}
    {dialog === 'qr' && <CenteredQR t={t} />}
  </DesktopWindow>
);

// desktop QR: mobile bottom-sheet → centered dialog (same FakeQR widget)
const CenteredQR = ({ t }) => (
  <div style={{ position: 'absolute', inset: 0, zIndex: 10, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
    <div style={{ position: 'absolute', inset: 0, background: hexA(t.scrim, 0.4) }} />
    <div style={{ position: 'relative', background: t.surface, borderRadius: SHAPE.xl, boxShadow: elev(5, t.dark), padding: '24px 28px 28px', display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
      <div style={{ ...ty('titleLarge'), color: t.onSurface, marginBottom: 20 }}>Your ID QR</div>
      <div style={{ padding: 16, background: BRAND.qrSurface, borderRadius: SHAPE.m }}><FakeQR size={220} /></div>
      <div style={{ marginTop: 16 }}><TextButton t={t} label="Close" /></div>
    </div>
  </div>
);

// ============================================================
// ONBOARDING · centered card (reuses the phone form content)
// ============================================================

const OnboardCard = ({ t, children, width = 440 }) => (
  <div style={{ width, background: t.surfaceContainerLowest, borderRadius: SHAPE.xl, boxShadow: elev(2, t.dark), border: `1px solid ${t.outlineVariant}`, padding: '32px 32px 28px', boxSizing: 'border-box' }}>
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', marginBottom: 8 }}>
      <img src="assets/logo.png" alt="" style={{ width: 56, height: 56, objectFit: 'contain', marginBottom: 12 }} />
      <span style={{ fontFamily: SANS, fontSize: 22, fontWeight: 700, letterSpacing: '0.14em', color: t.onSurface }}>NOX</span>
      <div style={{ height: 3, width: 120, marginTop: 12, borderRadius: 2, background: `linear-gradient(90deg, ${BRAND.teal}, ${BRAND.lime}, ${BRAND.gold}, ${BRAND.coral}, ${BRAND.red})` }} />
    </div>
    {children}
  </div>
);

const LoginDesktop = ({ t, state = 'filled' }) => {
  const loading = state === 'loading';
  const errorText = state === 'error-format' ? 'Invalid identifier'
    : state === 'error-net' ? 'Network error. Try again.' : null;
  const value = state === 'empty' ? '' : SAMPLE_ID;
  return (
    <DesktopWindow t={t} subtitle="Sign in">
      <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', background: t.surface }}>
        <OnboardCard t={t}>
          <div style={{ marginTop: 18 }}>
            <TextField t={t} label="Your ID" value={value} mono multiline minHeight={120}
              focused={state !== 'empty'} error={errorText} placeholder="Paste or enter your ID"
              suffix={<div style={{ width: 40, height: 40, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Icon name="content_paste" size={22} color={t.onSurfaceVariant} /></div>} />
          </div>
          <div style={{ height: 22 }} />
          <FilledButton t={t} label="Sign in" full disabled={state === 'empty' || loading} loading={loading} />
          <div style={{ height: 6 }} />
          <div style={{ display: 'flex', justifyContent: 'center' }}><TextButton t={t} label="Scan QR" disabled={loading} /></div>
        </OnboardCard>
      </div>
    </DesktopWindow>
  );
};

const UsernameDesktop = ({ t, state = 'prefilled' }) => {
  const value = state === 'empty' ? '' : (state === 'taken' ? 'Anna' : SAMPLE_NAME);
  const error = state === 'taken' ? 'This name is taken' : null;
  const suffix = state === 'checking'
    ? <div style={{ width: 24, height: 24 }}><Spinner size={20} color={t.onSurfaceVariant} /></div> : null;
  return (
    <DesktopWindow t={t} subtitle="Set up">
      <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', background: t.surface }}>
        <OnboardCard t={t}>
          <div style={{ marginTop: 18 }}>
            <TextField t={t} label="Name" value={value} placeholder="How others will see you"
              focused={state !== 'empty'} error={error} counter={`${value.length}/32`} suffix={suffix}
              helper="Others see this name. You can change it now or later in Settings." />
          </div>
          <div style={{ height: 22 }} />
          <FilledButton t={t} label="Done" full disabled={state === 'taken' || state === 'empty'} />
          <div style={{ height: 6 }} />
          <div style={{ display: 'flex', justifyContent: 'center' }}><TextButton t={t} label="Skip" /></div>
        </OnboardCard>
      </div>
    </DesktopWindow>
  );
};

const SplashDesktop = () => (
  <DesktopWindow t={DARK} chrome={false}>
    <SplashScreen />
  </DesktopWindow>
);

Object.assign(window, {
  ChatRow, ChatsListPane, ThreadHeader, ThreadMessages, ThreadPane, ChatsDesktop,
  SETTINGS_NAV, SettingsNavItem, SettingsListPane, SettingsDetail, SettingsDesktop, CenteredQR,
  OnboardCard, LoginDesktop, UsernameDesktop, SplashDesktop,
});
