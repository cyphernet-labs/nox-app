# 7.1 · Settings root

> **One person, a public ID.** The machine holds one person, so the card carries no role badge and the list has no `People` row. `Your ID` is the PUBLIC author id, shown whole with no Show/Hide and no QR: adding a device is 7.8's own job, with a one-shot token. Logout cannot be undone - the device revokes its own key - and its copy says so.

> **Settings** · mobile (iOS / Android) · Material 3

**Purpose.** Account identity + grouped settings entries.

## Anatomy
App bar (Settings). Identity card as an account header: ringed initials avatar, name, the full public ID, and two tonal actions (Edit name / Copy ID). One rounded tile per destination (`surfaceContainerLow`, radius lg, 8 apart), each with a bare leading glyph (22, `onSurfaceVariant`) and a chevron behind: Devices, Connection, Notifications, Appearance, Language, Terms, About. Destructive Log out in a tile of its own below a wider gap - `error` throughout, glyph filled, no chevron. The live design in `_src/` draws these glyphs inside a 40dp tinted circle; the app draws them bare (owner decision). Bottom bar.

## States
- `loaded` — Loaded
- `editing` — Editing name
- `logout` — Logout dialog
- `logout-loading` — Logging out

## Behavior
- Identity card: avatar + name (edit inline) + the full ID, with `Edit name` and `Copy ID` as named tonal buttons. No QR action - adding a device is 7.8's own screen.
- No role badge: with one person on the machine such a mark has one possible answer, and a field with one answer only looks like information.
- No mask and no reveal: the ID is not a secret — the person is recognised by the device's paired key — so there is nothing to hide and no `id-shown` state. The ID renders in full, in mono (`onSurfaceVariant`).
- There is no QR action in the card. Adding a device happens on **7.8 Devices**, reached by its own row, where an invite is minted with a real one-shot token.
- **Connection** (feature 045), directly under Devices with the `lan` glyph, opens **7.10 Connection**: the server address, the onion address and Use Tor.
- Editing: name becomes an inline TextField with counter. No availability spinner: names are not unique and, on a one-person server, there is nobody to collide with.
- Log out → confirm AlertDialog (destructive action tinted error); confirming revokes this device's key over a live connection (with none, the wipe goes on at once and the orphaned key is left to be revoked from another device, 7.8), then wipes the session and every bit of local data; shows a loading state.

## Navigation
- Rows → Devices (7.8) / Connection (7.10) / 7.2 / 7.3 / 7.4 / Terms / About.
- Log out (confirmed) → Login (2.1).

## Copy (EN)
- Title: Settings
- Rows: Devices · Connection · Notifications · Appearance · Language · Terms · About
- Logout title: Log out?
- Logout body: This device will be signed out and won't be able to connect again. You'll need a new pairing link to come back.
- Logout error (snackbar): Could not log out. Please try again.
- Actions: Cancel · Log out

## Design-system components
- AppBar (title)
- IdentityCard
- SettingsGroup / SettingsNavRow
- LogoutDialog
- BottomBar

---
Live design: open `index.html` → 7.1 Settings root (switch states with the chips). Components are rendered from the shared design system (`_src/`).
