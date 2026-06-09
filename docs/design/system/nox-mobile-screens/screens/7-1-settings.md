# 7.1 · Settings root

> **Settings** · mobile (iOS / Android) · Material 3

**Purpose.** Account identity + grouped settings entries.

## Anatomy
App bar (Settings). Identity card (name + masked ID). Grouped list: Notifications, Appearance, Language, Terms, About. Separate destructive Log out group. Bottom bar.

## States
- `loaded` — Loaded
- `id-shown` — ID revealed
- `editing` — Editing name
- `qr` — QR sheet
- `logout` — Logout dialog
- `logout-loading` — Logging out

## Behavior
- Identity card: name (edit inline) + ID masked as •••••••• with reveal / copy / show-QR actions.
- Reveal (id-shown): full ID rendered mono, wrapped break-all, with hide/copy/QR.
- Editing: name becomes an inline TextField with counter.
- Show QR → modal bottom sheet; the QR card surface is brand-fixed WHITE so it scans in dark mode.
- Log out → confirm AlertDialog (destructive action tinted error); confirming wipes ID + local data; shows a loading state.

## Navigation
- Rows → 7.2 / 7.3 / 7.4 / Terms / About.
- Log out (confirmed) → Login (2.1).

## Copy (EN)
- Title: Settings
- ID mask: ••••••••
- Logout title: Log out?
- Logout body: Your ID and local data will be removed from this device.
- Actions: Cancel · Log out

## Design-system components
- AppBar (title)
- IdentityCard
- SettingsGroup / SettingsNavRow
- QRSheet (brand white)
- LogoutDialog
- BottomBar

---
Live design: open `index.html` → 7.1 Settings root (switch states with the chips). Components are rendered from the shared design system (`_src/`).
