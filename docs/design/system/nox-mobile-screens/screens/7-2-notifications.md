# 7.2 · Notifications

> **Settings** · mobile (iOS / Android) · Material 3

**Purpose.** Toggle push notifications.

## Anatomy
App bar (back + Notifications). Grouped switch row “Enable notifications”.

## States
- `on` — Enabled
- `denied` — OS-denied

## Behavior
- Single switch with supporting text “Only for chats you’re in”.
- If the OS permission is denied, an InfoBanner appears (“Notifications are blocked” + Open settings) and the switch reads off.

## Navigation
- Back → Settings (7.1).
- Open settings → OS settings.

## Copy (EN)
- Row: Enable notifications / Only for chats you’re in
- Denied: Notifications are blocked / Allow notifications in system settings to receive messages from your chats. / Open settings

## Design-system components
- AppBar (title)
- SettingsGroup / SettingsSwitchRow
- InfoBanner

---
Live design: open `index.html` → 7.2 Notifications (switch states with the chips). Components are rendered from the shared design system (`_src/`).
