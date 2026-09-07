# 02 · Settings

> ⚠️ **Feature 032:** `Your ID` shows the PUBLIC author id with no Show/Hide — it stopped being a secret. The account QR is gone: scanning an id adds nobody, so `Show QR` leads to **Devices**, where an invite is minted with a one-shot token. Logout is irreversible now (the device revokes its own key), and its copy says so.

> **02 · Settings** · desktop (Windows / Linux / macOS) · Material 3 · window 1440×900

**Purpose.** List-detail settings: menu pane (left) + the selected section’s panel (right).

**Adaptation from mobile.** mobile full-screen settings → list-detail · bottom sheet → centered dialog · the identity card, badge included, is the same widget at both widths

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
- `account-member` — Account, ownership not stated or not held: no badge

## Behavior
- Selecting a menu item highlights it (secondaryContainer) and swaps the detail pane — no push.
- Account: identity card carrying the name, the `Server owner` badge and the ID. Editing → inline name field, with the badge **above** it: ownership has nothing to do with editing a name.
- Owner badge (phase 033): shown only when the server states that this person owns it; "not stated" and "not the owner" both render nothing. Same rule and same placement as the narrow width — one builder feeds both, so the two cannot drift apart.
- ⚠️ Phase 032 removed both the mask and the inline account QR: the ID is public now, and a QR of it added nobody. `Show QR` selects the Devices pane, where an invite is minted with a real one-shot token.
- Notifications: enable switch; OS-denied → InfoBanner + Open settings, switch off.
- Appearance: System / Light / Dark theme cards. Language: System / English / Українська.
- Log out → centered confirm Dialog (mobile’s sheet/dialog becomes a centered dialog); destructive action tinted error.

## Navigation
- Menu item → swaps detail pane.
- Log out (confirmed) → Login (03).

## Copy (EN)
- Pane title: Settings
- Owner badge: Server owner
- Logout: Log out? / Your ID and local data will be removed from this device.

## Design-system components
- NavRail
- PaneHeader
- SettingsNavItem
- IdentityCard
- SettingsGroup / SettingsSwitchRow / LangRow
- ThemeOptionCard
- InfoBanner
- TermsBody
- LogoutDialog / CenteredQR

---
Live design: open `index.html` → 02 Settings (switch states with the chips). The desktop shell re-arranges the SAME widgets as mobile — only the wrapper differs.
