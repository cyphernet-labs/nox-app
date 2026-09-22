# 7.1 · Settings root

> ⚠️ **Feature 037 (2026-09-10):** the `Server owner` badge is GONE. The machine holds one person, so a mark that told the owner apart from an invited member tells nothing apart — the state `loaded-member` is struck through below and kept only to say so; the badge copy line is gone outright. There is no `People` row either.

> ⚠️ **Feature 032:** `Your ID` shows the PUBLIC author id with no Show/Hide — it stopped being a secret. **The `Show QR` action is gone outright:** it once handed over a bearer secret, then became a shortcut into **7.8 Devices**, which the `Devices` row already is. Adding a device is that screen's own job, with a one-shot token. Logout is irreversible now (the device revokes its own key), and its copy says so.

> **Settings** · mobile (iOS / Android) · Material 3

**Purpose.** Account identity + grouped settings entries.

## Anatomy
App bar (Settings). Identity card as an account header: ringed initials avatar, name, the full public ID, and two tonal actions (Edit name / Copy ID). One rounded tile per destination (`surfaceContainerLow`, radius lg, 8 apart), each with a 40dp `secondaryContainer` chip in front and a chevron behind: Devices, Notifications, Appearance, Language, Terms, About. Destructive Log out in a tile of its own below a wider gap - `error` throughout, chip at 14%, glyph filled, no chevron. Bottom bar. Two earlier shapes were wrong and are recorded in the screen spec: bare rows on the scaffold background, and all of them merged into one card with hairlines.

## States
- `loaded` — Loaded
- ~~`loaded-member`~~ — dropped by 037 along with the badge: there is only one state now
- `editing` — Editing name
- `logout` — Logout dialog
- `logout-loading` — Logging out

## Behavior
- Identity card: avatar + name (edit inline) + the full ID, with `Edit name` and `Copy ID` as named tonal buttons. No QR action - adding a device is 7.8's own screen.
- ⚠️ The owner badge (phase 033) was removed by phase 037: with one person on the machine the mark has one possible answer, and a field with one answer only looks like information.
- ⚠️ Phase 032 removed the mask and the reveal: the ID stopped being a secret — the person is recognised by the device's paired key — so there is nothing to hide and no `id-shown` state. The ID renders in full, at the card's ordinary text style.
- There is no QR action in the card. Adding a device happens on **7.8 Devices**, reached by its own row, where an invite is minted with a real one-shot token.
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
