# NOX — Screen catalog (composition + states → Flutter)

Index of every screen, its assembled composition, the state variants to build, and the
Flutter scaffold to use. Each screen reuses the components in `components.md`. UI copy is
**English** (Ukrainian localization is a later task). For pixel reference open the live builds
(`NOX - Mobile.html`, `NOX - Desktop.html`); full written specs are in `uploads/`.

Legend: **M** = mobile build, **D** = desktop build.

---

## 1.1 Splash · `uploads/splash.md`
- **Scaffold:** full-screen, **brand-fixed** bg `brand/canvasDark` (not themed). Logo centered, wordmark `NOX` `#FAFAFA` below.
- **Motion:** one-shot reveal ~400ms `emphasizedDecelerate`. Cold start only.
- **Logic:** decides auth → Login (2.1) or Shell (4.1).
- **D:** `SplashDesktop` (single splash under the title bar).

## 2.1 Login · `uploads/login.md`
- **Scaffold:** `AppBar` + body with ID `TextField` (paste/type), `qr_code_scanner` action → 2.2, primary `Sign in`.
- **States:** idle · validating (suffix spinner) · field-error (`errorText`, format/network inline) · submitting (button loading). Fatal/5xx → 3.1.
- **D:** `LoginDesktop` / `UsernameDesktop` centered card.

## 2.2 QR scan · `uploads/qr-scan.md`
- **Scaffold:** live camera + **brand-fixed** overlay (mask `#000`@55%, reticle `brand/white` 3dp corners `m`, instruction `#FAFAFA`). AppBar solid `surface`. Actions: `flashlight_on/off`, `cameraswitch`.
- **States:** scanning · permission-denied (opaque `surface` overlay + `Open settings` `FilledButton`).
- **D:** `QRDesktop` + `Viewfinder` in a dialog/pane.

## 2.3 Set username · `uploads/set-username.md`
- **Scaffold:** `TextField` (≤32, charset `[A-Za-z0-9._-]`, live uniqueness), counter `N/32`, `Done` (skip allowed — server pre-assigned `User<random>`).
- **States:** idle · checking (suffix spinner) · taken (`errorText`) · valid.

## 3.1 Error (universal) · `uploads/error.md`
- **Scaffold:** centered `error_outline` `onSurfaceVariant` 48–96 + title/message + `Try again` `FilledButton`.
- **States/props:** `icon`, `title`, `message`, `onRetry`; **blocking** (no back, last in stack) vs **embeddable** (back arrow). Copy: `Could not <verb>. Check your connection and try again.`
- **D:** `DesktopError` / `ErrorDesktop` (state-driven).

## 4.1 Tab-bar shell · `uploads/tab-bar-shell.md`
- **Scaffold (M):** `Scaffold` + custom `BottomAppBar` (notch) + docked `FloatingActionButton` `+`. Tabs **Chats** (`forum`) / **Settings** (`settings`); `IndexedStack` with ≤150ms fade. FAB `+` → Create chat (6.1), visible on both tabs.
- **Scaffold (D):** `NavigationRail` (80) on the left; `+` is a rail action; content is list-detail.

## 5.1 Chats list · `uploads/chats-list.md`
- **Scaffold:** `AppBar` (wordmark) + `SearchBar` + `ListView` of chat-list-items (§ components). Generated avatars, unread `Badge` (`99+`, hidden at 0). Relative timestamps.
- **States:** loaded · empty (`forum_outlined` empty-state) · offline (`MaterialBanner` `No connection`, top) · load-error (`Could not load chats. Pull to refresh.`).
- **D:** `ChatsListPane` (360) — left pane of `ChatsDesktop` list-detail; `listState` prop.

## 5.2 Chat thread · `uploads/chat.md`
- **Scaffold:** `AppBar` (chat name `titleLarge`) + message `ListView` (bubbles, date separators `Today`/`Yesterday`/`12 May`) + `Composer`. Author by **ID** (stable), label shown is current. Status: `pending`/`sent`/`error` (tap to retry). No per-author avatars in feed.
- **States:** messages · empty (`chat_bubble_outline`) · offline banner · sending/pending/error bubbles.
- **D:** `ThreadPane` (`ThreadHeader` + `ThreadMessages`), readable column ≤980; desktop-only header actions search/folder/info (intentional affordance). `threadState` prop.

## 5.3 File view · `uploads/file-view.md`
- **Scaffold:** `AppBar` (file name `titleLarge`) + large type icon (48–96, **no content preview**) + name/size + `download`, determinate `LinearProgressIndicator` (`primary`/track `surfaceVariant`).
- **D:** `FileViewDialog`/`FileViewDesktop` → **lightbox**.

## 5.4 Chat card · `uploads/chat-card.md`
- **Scaffold:** header (generated avatar + name `headlineSmall`) + attachments list/grid (file cells, type icons). 
- **States:** has files · empty (`folder_open`).
- **D:** `ChatInfoDrawer`/`ChatInfoDesktop` → right **drawer**.

## 6.1 Create chat · `uploads/create-chat.md`
- **Scaffold:** `TextField` chat name (≤64, charset unrestricted, live uniqueness), counter `N/64`, `Create` `FilledButton`.
- **States:** idle · checking · taken · valid · submitting.
- **D:** `CreateChatDialog`/`CreateChatDesktop` → **Dialog**.

## 7 Settings · `uploads/settings-root.md`, `appearance.md`, `language.md`, `notifications.md`, `terms.md`, `about.md`
- **7.0 Root:** `AppBar` `Settings` + grouped list — Identity card (7.1), Appearance (7.3), Language (7.4), Notifications switch, Terms, About, Logout.
- **7.1 Identity:** identity `Card` (mask `••••••••` / `Show` / `Copy` / `Show QR`). **Show QR** → bottom sheet (M) with **brand-fixed** white QR surface. **D:** Account masks ID by default + shows account QR (no secret reveal).
- **7.3 Appearance:** `RadioListTile` System / Light / Dark → `themeMode`.
- **7.4 Language:** `RadioListTile` System / English / Українська (system falls back to English if OS ≠ EN/UK).
- **Logout:** `AlertDialog` confirm (destructive `error`) → wipes ID + local data.
- **D:** `SettingsDesktop` = `SettingsListPane` (340) + `SettingsDetail` (`detailState` prop). `LogoutDialog` centered.

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
