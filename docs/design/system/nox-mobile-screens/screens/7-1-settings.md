# 7.1 · Settings root

> ⚠️ **Feature 032:** `Your ID` shows the PUBLIC author id with no Show/Hide — it stopped being a secret. The account QR is gone: scanning an id adds nobody, so `Show QR` leads to **Devices**, where an invite is minted with a one-shot token. Logout is irreversible now (the device revokes its own key), and its copy says so.

> **Settings** · mobile (iOS / Android) · Material 3

**Purpose.** Account identity + grouped settings entries.

## Anatomy
App bar (Settings). Identity card (name + `Server owner` badge when the server states it + the public ID). Grouped list: Devices, Notifications, Appearance, Language, Terms, About. Separate destructive Log out group. Bottom bar.

## States
- `loaded` — Loaded (owner: badge beside the name)
- `loaded-member` — Loaded, ownership not stated or not held: no badge, and no gap where one would be
- `editing` — Editing name
- `logout` — Logout dialog
- `logout-loading` — Logging out

## Behavior
- Identity card: name (edit inline) + `Server owner` badge + ID with copy / show-QR actions.
- Owner badge (phase 033): shown only when the server states that this person owns it. "Not stated" and "not the owner" both render nothing — drawing "not the owner" before the server answers would be a claim the app cannot make, followed by a flicker when it is corrected. The badge sits beside the name and drops onto its own line when the name and the badge no longer fit one row (long localisation, large text scale).
- ⚠️ Phase 032 removed the mask and the reveal: the ID stopped being a secret — the person is recognised by the device's paired key — so there is nothing to hide and no `id-shown` state. The ID renders in full, at the card's ordinary text style.
- `Show QR` leads to **Devices**, where an invite is minted with a real one-shot token. It no longer shows a QR of the ID: that used to hand over a bearer secret.
- Editing: name becomes an inline TextField with counter.
- Show QR → modal bottom sheet; the QR card surface is brand-fixed WHITE so it scans in dark mode.
- Log out → confirm AlertDialog (destructive action tinted error); confirming wipes ID + local data; shows a loading state.

## Navigation
- Rows → 7.2 / 7.3 / 7.4 / Terms / About.
- Log out (confirmed) → Login (2.1).

## Copy (EN)
- Title: Settings
- Owner badge: Server owner
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
