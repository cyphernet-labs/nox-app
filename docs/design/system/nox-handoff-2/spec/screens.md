# NOX — Screen catalog (composition + states → Flutter)

Index of every screen, its assembled composition, the state variants to build, and the
Flutter scaffold to use. Each screen reuses the components in `components.md`. UI copy here is
**English**; the app ships English and Ukrainian. For pixel reference open the live builds
(`NOX - Mobile.html`, `NOX - Desktop.html`); full written specs are in `uploads/` — in this
repository `docs/design/spec/screens/`, same file names. Per-screen behaviour at each width:
`nox-mobile-screens/screens/` and `nox-desktop-screens/screens/`.

Legend: **M** = mobile build, **D** = desktop build.

---

## 1.1 Splash · `uploads/splash.md`
- **Scaffold:** full-screen, **brand-fixed** bg `brand/canvasDark` (not themed). Logo centered, wordmark `NOX` `#FAFAFA` below.
- **Motion:** one-shot reveal ~400ms `emphasizedDecelerate`. Cold start only.
- **Logic:** waits for the local data to open and the connection to start → Login (2.1), Set username (2.3) or Shell (4.1).
- **D:** `SplashDesktop` (edge-to-edge, no title bar).

## 2.1 Login · `uploads/login.md`
- **Scaffold:** `AppBar` + body with a mono multiline pairing-link `TextField` (paste/type), primary `Sign in`, secondary `Scan QR` → 2.2 (Windows / Linux: `Use a QR image`).
- **States:** idle · field-error (`errorText`: not a pairing link / a link from a newer app). The link is read on the device — no spinner; a readable link opens 2.4.
- **D:** `LoginDesktop` / `UsernameDesktop` centered card.

## 2.2 QR scan · `uploads/qr-scan.md`
- **Scaffold:** live camera + **brand-fixed** overlay (mask `#000`@55%, reticle `brand/white` 3dp corners `m`, instruction `#FAFAFA`). AppBar transparent over the feed (solid `surface` over the permission-denied panel). Actions: `flashlight_on/off`, `cameraswitch`.
- **States:** scanning · permission-denied (opaque `surface` overlay + `Open settings` `FilledButton`).
- **D:** `QRDesktop` + `Viewfinder` (300) under the title bar, macOS only.

## 2.4 Connect · `connect.md`
- **Scaffold:** `AppBar` (back, wordmark) + title + `Server address` / `Onion address` outlined fields + `Use Tor` `CheckboxListTile` + `Connect` (loading) + the reason line + `Cancel`.
- **States:** filled · field-error · connecting · failed (reason) · waiting (an invite waits for Allow on the issuing device: spinner + `Waiting for approval on your other device`, `Cancel` only) · declined.
- **D:** the same onboarding card as Login. No live design: the app's goldens pin it.

## 2.3 Set username · `uploads/set-username.md`
- **Scaffold:** `TextField` (≤32, charset `[A-Za-z0-9._-]` checked as typed; names are not unique, so nothing checks availability), counter `N/32`, `Done` (skip allowed — server pre-assigned `User<random>`).
- **States:** idle · invalid-charset (`errorText`) · valid.

## 3.1 Error (universal) · `uploads/error.md`
- **Scaffold:** centered `error_outline` `onSurfaceVariant` 48–96 + title/message + `Try again` `FilledButton`.
- **States/props:** `icon`, `title`, `message`, `onRetry`; **blocking** (no back, last in stack) vs **embeddable** (back arrow). Copy: `Could not <verb>. Check your connection and try again.`
- **D:** `DesktopError` / `ErrorDesktop` (state-driven).

## 4.1 Tab-bar shell · `uploads/tab-bar-shell.md`
- **Scaffold (M):** `Scaffold` + custom `BottomAppBar` (notch) + docked `FloatingActionButton` `+`. Tabs **Chats** (`forum`) / **Settings** (`settings`); both kept mounted in a `Stack`, ≤150ms fade. FAB `+` → Create chat (6.1), visible on both tabs.
- **Scaffold (D):** `NavigationRail` (80) on the left, account avatar pinned to its foot; `+` sits in the chat-list pane header, not on the rail; content is list-detail.

## 5.1 Chats list · `uploads/chats-list.md`
- **Scaffold:** `AppBar` (wordmark) + `SearchBar` + `ListView` of chat-list-items (§ components). Generated avatars, unread `Badge` (`99+`, hidden at 0). Relative timestamps.
- **States:** loaded · empty (`forum_outlined` empty-state) · offline (`MaterialBanner` `No connection` or its cause, top, `Try again`) · wrong server · load-error (`Could not load chats. Pull to refresh.`).
- **D:** `ChatsListPane` (360) — left pane of `ChatsDesktop` list-detail; `listState` prop.

## 5.2 Chat thread · `uploads/chat.md`
- **Scaffold:** `AppBar` (chat name `titleLarge`) + message `ListView` (bubbles, date separators `Today`/`Yesterday`/`12 May`) + `Composer`. Author by **ID** (stable), label shown is current. Status: `pending`/`sent`/`error` (tap to retry). No per-author avatars in feed.
- **States:** messages · empty (`chat_bubble_outline`) · offline banner · sending/pending/error bubbles.
- **D:** `ThreadPane` (`ThreadHeader` + `ThreadMessages`), readable column ≤980; desktop-only header actions: info (`folder_open`) and a permanently disabled `Invite a person`. `threadState` prop.

## 5.3 File view · `uploads/file-view.md`
- **Scaffold:** `AppBar` (file name `titleLarge`) + large type icon (48–96) + name/size + `download`, determinate `LinearProgressIndicator` (`primary`/track `surfaceVariant`). A picture whose bytes are on the device is shown instead of the icon; a video plays (iOS, Android, macOS).
- **D:** `FileViewDialog`/`FileViewDesktop` → **lightbox**.

## 5.4 Chat card · `uploads/chat-card.md`
- **Scaffold:** header (generated avatar + name `headlineSmall` + `Rename chat`) + `People` (the one person of this server + a permanently disabled `Invite a person`) + attachments list/grid (file cells, type icons). 
- **States:** has files · empty (`folder_open`).
- **D:** `ChatInfoDrawer`/`ChatInfoDesktop` → right **drawer**.

## 6.1 Create chat · `uploads/create-chat.md`
- **Scaffold:** `TextField` chat name (≤64, charset unrestricted, live uniqueness), counter `N/64`, `Create` `FilledButton`.
- **States:** idle · checking · taken · valid · submitting.
- **D:** `CreateChatDialog`/`CreateChatDesktop` → **Dialog**.

## 7 Settings · `uploads/settings-root.md`, `appearance.md`, `language.md`, `notifications.md`, `terms.md`, `about.md`
- **7.0 Root:** `AppBar` `Settings` + Identity card (7.1), then one tile per destination — Devices (7.8), Connection (7.10), Notifications (7.2), Appearance (7.3), Language (7.4), Terms, About — and Log out.
- **7.1 Identity:** identity `Card` as an account header — ringed initials avatar, name, the FULL public ID in mono, and two tonal actions `Edit name` / `Copy ID`. No mask, no `Show`/`Hide`, no QR action at either width: the ID is not a secret, and adding a device is 7.8's own screen.
- **7.3 Appearance:** single-select option cards (preview thumbnail + label + radio) System / Light / Dark → `themeMode`.
- **7.4 Language:** the same option cards, System / English / Українська (system falls back to English if OS ≠ EN/UK).
- **7.8 Devices · `devices.md`:** the paired devices (`This device` first), `Revoke`, `Add a device` → an invite card (QR + link, `Copy` / `Hide`). No live design.
- **7.10 Connection · `connection.md`:** `Server address`, `Onion address`, `Save`, the `Use Tor` switch row. No live design.
- **Logout:** `AlertDialog` confirm (destructive `error`) → the device revokes its own key, then the session and local data are wiped.
- **D:** `SettingsDesktop` = `SettingsListPane` (340) + `SettingsDetail` (`detailState` prop). `LogoutDialog` centered.

## 8.2 Pair request · `pair-request.md`
- **Scaffold:** `AlertDialog` over any signed-in screen, barrier not dismissible — `devices` glyph, `New device: {platform}. Allow it to join?`, `Deny` / `Allow`.
- **States:** asking · answering (spinner in the pressed button) · answer-failed (`error` line).
- **D:** the same dialog over the whole window. No live design.

---

## State-driven convention (desktop)

A new screen state = a new **prop** on the matching desktop component (e.g. `listState`,
`threadState`, `detailState`, `state`, `dialog`, `snack`, `overlay`) — internally it reuses the
shared widget. Do not fork copies. (Mirror this in Flutter: one widget, state enum / sealed class.)

## Feedback levels (global)

| Level | Trigger | Widget |
|---|---|---|
| Field | field validation | `TextField.errorText` |
| Transient | one-off, no recovery | `SnackBar` (bottom) |
| Persistent | needs retry/recover (offline) | `MaterialBanner` (top) |
| Fatal | unexpected / 5xx | screen 3.1 |
