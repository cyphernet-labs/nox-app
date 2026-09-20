# 02 · Settings

> ⚠️ **Feature 032:** `Your ID` shows the PUBLIC author id with no Show/Hide — it stopped being a secret. **The `Show QR` action is gone outright:** it once handed over a bearer secret, then became a shortcut into **7.8 Devices**, which the `Devices` row already is. Adding a device is that screen's own job, with a one-shot token. Logout is irreversible now (the device revokes its own key), and its copy says so.

> **02 · Settings** · desktop (Windows / Linux / macOS) · Material 3 · window 1440×900

**Purpose.** List-detail settings: menu pane (left) + the selected section’s panel (right).

**Adaptation from mobile.** mobile full-screen settings → list-detail · bottom sheet → centered dialog · the identity card is the same widget at both widths

## Anatomy
NavigationRail + settings menu pane (340: one card of nav items, Log out in its own card at the foot - the same two cards as the phone) + detail pane (content capped to ≤680). Each detail reuses the exact phone widgets. The three sub-groups the pane used to have were separated by hairlines drawn across its full width, which cut through the selected pill.

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
- ~~`account-member`~~ — dropped by phase 037 along with the badge: there is only one Account state now

## Behavior
- Selecting a menu item highlights it (secondaryContainer) and swaps the detail pane — no push.
- Account: identity card as an account header — ringed initials avatar, name, the full public ID in mono, and the two tonal actions `Edit name` / `Copy ID`. Editing → inline name field in place of the name, `Edit name` withdrawn while it is open; no availability spinner, because names are not unique and, on a one-person server, there is nobody to collide with.
- ⚠️ **Phase 037 (2026-09-10) removed the `Server owner` badge** (added by 033) and there is no `People` menu item. The machine holds one person, so a mark that separated the owner from an invited member separates nothing. Same rule as the narrow width — one builder feeds both, so the two cannot drift apart.
- ⚠️ Phase 032 removed both the mask and the inline account QR: the ID is public now, and a QR of it added nobody. The QR action itself is gone too — the `Devices` menu item is the way to the pane that mints an invite.
- Notifications: enable switch, no leading glyph (settings rows are icon-less); OS-denied → an inset InfoBanner card above it, in the same geometry as the settings cards, with `Open settings` at its trailing edge, switch off.
- Appearance: System / Light / Dark theme cards. Language: System / English / Українська.
- Log out → centered confirm Dialog (mobile’s sheet/dialog becomes a centered dialog); destructive action tinted error.

## Navigation
- Menu item → swaps detail pane.
- Log out (confirmed) → Login (03).

## Copy (EN)
- Pane title: Settings
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
- LogoutDialog

---
Live design: open `index.html` → 02 Settings (switch states with the chips). The desktop shell re-arranges the SAME widgets as mobile — only the wrapper differs.
