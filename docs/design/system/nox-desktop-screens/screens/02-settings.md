# 02 · Settings

> ⚠️ **Feature 032:** `Your ID` shows the PUBLIC author id with no Show/Hide — it stopped being a secret. The account QR is gone: scanning an id adds nobody, so `Show QR` leads to **Devices**, where an invite is minted with a one-shot token. Logout is irreversible now (the device revokes its own key), and its copy says so.

> **02 · Settings** · desktop (Windows / Linux / macOS) · Material 3 · window 1440×900

**Purpose.** List-detail settings: menu pane (left) + the selected section’s panel (right).

**Adaptation from mobile.** mobile full-screen settings → list-detail · bottom sheet → centered dialog · ID masked + account QR by default

## Anatomy
NavigationRail + settings menu pane (340, grouped nav items) + detail pane (content capped to ≤680). Each detail reuses the exact phone widgets.

## States
- `account` — Account
- `account-editing` — Account · editing
- `notifications` — Notifications
- `notifications-denied` — Notif · denied
- `appearance` — Appearance
- `language` — Language
- `terms` — Terms
- `about` — About
- `logout` — Logout dialog
- `qr` — QR dialog

## Behavior
- Selecting a menu item highlights it (secondaryContainer) and swaps the detail pane — no push.
- Account: identity card; by default the ID stays masked and the account QR is shown inline (no secret reveal on desktop). Editing → inline name field.
- Notifications: enable switch; OS-denied → InfoBanner + Open settings, switch off.
- Appearance: System / Light / Dark theme cards. Language: System / English / Українська.
- Log out → centered confirm Dialog (mobile’s sheet/dialog becomes a centered dialog); destructive action tinted error.
- Show QR → centered Dialog with the brand-fixed white QR card (mobile bottom-sheet → dialog).

## Navigation
- Menu item → swaps detail pane.
- Log out (confirmed) → Login (03).

## Copy (EN)
- Pane title: Settings
- Account QR caption: Show this code to let someone add you
- Logout: Log out? / Your ID and local data will be removed from this device.

## Design-system components
- NavRail
- PaneHeader
- SettingsNavItem
- IdentityCard
- FakeQR (brand white)
- SettingsGroup / SettingsSwitchRow / LangRow
- ThemeOptionCard
- InfoBanner
- TermsBody
- LogoutDialog / CenteredQR

---
Live design: open `index.html` → 02 Settings (switch states with the chips). The desktop shell re-arranges the SAME widgets as mobile — only the wrapper differs.
