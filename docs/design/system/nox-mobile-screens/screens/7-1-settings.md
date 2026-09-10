# 7.1 · Settings root

> ⚠️ **Feature 037 (2026-09-10):** the `Server owner` badge is GONE. The machine holds one person, so a mark that told the owner apart from an invited member tells nothing apart — the states `loaded-member` and the badge copy below are dead and kept only to say so. There is no `People` row either.

> ⚠️ **Feature 032:** `Your ID` shows the PUBLIC author id with no Show/Hide — it stopped being a secret. The account QR is gone: scanning an id adds nobody, so `Show QR` leads to **Devices**, where an invite is minted with a one-shot token. Logout is irreversible now (the device revokes its own key), and its copy says so.

> **Settings** · mobile (iOS / Android) · Material 3

**Purpose.** Account identity + grouped settings entries.

## Anatomy
App bar (Settings). Identity card (name + the public ID). Grouped list: Devices, Notifications, Appearance, Language, Terms, About. Separate destructive Log out group. Bottom bar.

## States
- `loaded` — Loaded
- ~~`loaded-member`~~ — dropped by 037 along with the badge: there is only one state now
- `editing` — Editing name
- `logout` — Logout dialog
- `logout-loading` — Logging out

## Behavior
- Identity card: name (edit inline) + ID with copy / show-QR actions.
- ⚠️ The owner badge (phase 033) was removed by phase 037: with one person on the machine the mark has one possible answer, and a field with one answer only looks like information.
- ⚠️ Phase 032 removed the mask and the reveal: the ID stopped being a secret — the person is recognised by the device's paired key — so there is nothing to hide and no `id-shown` state. The ID renders in full, at the card's ordinary text style.
- `Show QR` leads to **Devices**, where an invite is minted with a real one-shot token. It no longer shows a QR of the ID: that used to hand over a bearer secret.
- Editing: name becomes an inline TextField with counter. No availability spinner: names are not unique and, on a one-person server, there is nobody to collide with.
- Log out → confirm AlertDialog (destructive action tinted error); confirming wipes ID + local data; shows a loading state.

## Navigation
- Rows → 7.2 / 7.3 / 7.4 / Terms / About.
- Log out (confirmed) → Login (2.1).

## Copy (EN)
- Title: Settings
- Logout title: Log out?
- Logout body: Your ID and local data will be removed from this device.
- Actions: Cancel · Log out

## Design-system components
- AppBar (title)
- IdentityCard
- SettingsGroup / SettingsNavRow
- LogoutDialog
- BottomBar

---
Live design: open `index.html` → 7.1 Settings root (switch states with the chips). Components are rendered from the shared design system (`_src/`).
