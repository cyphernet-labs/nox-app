# 02 · Settings

> **One person, a public ID.** `Your ID` is the PUBLIC author id, shown whole with no Show/Hide and no QR: adding a device is the Devices pane's own job (09), with a one-shot token. Logout cannot be undone - the device revokes its own key - and its copy says so.

> **02 · Settings** · desktop (Windows / Linux / macOS) · Material 3 · window 1440×900

**Purpose.** List-detail settings: menu pane (left) + the selected section’s panel (right).

**Adaptation from mobile.** mobile full-screen settings → list-detail · bottom sheet → centered dialog · the identity card is the same widget at both widths

## Anatomy
NavigationRail + settings menu pane (340: an M3 NavigationDrawer - stadium destinations on the pane itself, each with a bare leading glyph, transparent until selected; the selected one fills `secondaryContainer`, recolours its glyph `onSecondaryContainer` and swaps it to the FILLED variant (the live design in `_src/` draws a 40dp tinted circle around the glyph; the app does not, by owner decision - it competes with the pill drawn around it); `Log out` pinned to the foot in `error`) + detail pane (content capped to ≤680). Each detail reuses the exact phone widgets. Three groups - Account+Devices+Connection · Notifications+Appearance+Language · Terms+About - separated by a line UNDER each group, below its padding, so nothing crosses a pill. No card around the destinations: the pane is the container, and a card would give the selection pill a rounded corner to break out through.

## States
- `account` — Account
- `account-editing` — Account · editing
- `devices` — Devices (pane 09; behaviour spec only, no chip in `index.html`)
- `connection` — Connection (pane 12; behaviour spec only, no chip in `index.html`)
- `notifications` — Notifications
- `notifications-denied` — Notif · denied
- `appearance` — Appearance
- `language` — Language
- `terms` — Terms
- `about` — About
- `logout` — Logout dialog

## Behavior
- Selecting a menu item highlights it (secondaryContainer) and swaps the detail pane — no push.
- Account: identity card as an account header — ringed initials avatar, name, the full public ID in mono, and the two tonal actions `Edit name` / `Copy ID`. Editing → inline name field in place of the name, `Edit name` withdrawn while it is open; no availability spinner, because names are not unique and, on a one-person server, there is nobody to collide with.
- No role badge and no `People` menu item: the machine holds one person, so such a mark would separate nothing. Same rule as the narrow width — one builder feeds both, so the two cannot drift apart.
- No mask and no account QR: the ID is public, and a QR of it would add nobody. The `Devices` menu item is the way to the pane that mints an invite.
- Connection (feature 045): the third item of the first group, glyph `lan` (filled when selected). Its pane is **12 · Connection** — the server address, the onion address and Use Tor — the same body as the phone's 7.10.
- Notifications: enable switch with a bare leading glyph (22, `onSurfaceVariant`) - no 40dp tinted circle; OS-denied → an inset InfoBanner card above it, in the same geometry as the settings cards, with `Open settings` at its trailing edge, switch off. The app never raises the OS permission prompt while push delivery is not settled (Q2 of the open-questions register): it only reads the status.
- Appearance: System / Light / Dark theme cards. Language: System / English / Українська. A choice that fails to save goes back to the previous one and says “Could not save. Try again.” in a snackbar.
- About: one settings-group row - the `info` glyph, `Version` and its value on the right (1.2.3 (build 456)); no chevron, not tappable.
- Log out → centered confirm Dialog (mobile’s sheet/dialog becomes a centered dialog); destructive action tinted error. Confirming does what it does on mobile 7.1: the device revokes its own key over a live connection, then the session and all local data are wiped. Until that ends the dialog stays up and modal, with a spinner in place of its Log out button; a logout that fails closes the dialog and says “Could not log out. Please try again.” in a snackbar.

## Navigation
- Menu item → swaps detail pane (Devices → 09 · Devices, Connection → 12 · Connection).
- Log out (confirmed) → Login (03).

## Copy (EN)
- Pane title: Settings
- Logout: Log out? / This device will be signed out and won't be able to connect again. You'll need a new pairing link to come back. · Cancel · Log out
- Logout error (snackbar): Could not log out. Please try again.
- Save error (snackbar): Could not save. Try again.

## Design-system components
- NavRail
- PaneHeader
- SettingsNavItem
- IdentityCard
- SettingsGroup / SettingsSwitchRow / LangRow
- ThemeOptionCard
- InfoBanner
- TermsBody
- LogoutDialog

---
Live design: open `index.html` → 02 Settings (switch states with the chips). The desktop shell re-arranges the SAME widgets as mobile — only the wrapper differs.
