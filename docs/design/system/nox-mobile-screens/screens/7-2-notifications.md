# 7.2 · Notifications

> **Settings** · mobile (iOS / Android) · Material 3

**Purpose.** Toggle push notifications.

## Anatomy
App bar (back + Notifications). Grouped switch row “Enable notifications” with a bare leading glyph (22, `onSurfaceVariant`) - no 40dp tinted circle around it. When the OS has refused the permission, an inset notice card sits above it - same geometry as every settings card, one surface step lighter - with its action at the trailing edge.

## States
- `on` — Enabled
- `denied` — OS-denied

## Behavior
- Single switch with supporting text “For new messages in your chats”.
- If the OS permission is denied, an InfoBanner appears (“Notifications are blocked” + Open settings) and the switch reads off and is disabled.
- The app never raises the OS permission prompt while push delivery is not settled (Q2 of the open-questions register): it only reads the permission status, and Open settings is the way to change it.

## Navigation
- Back → Settings (7.1).
- Open settings → OS settings.

## Copy (EN)
- Row: Enable notifications / For new messages in your chats
- Denied: Notifications are blocked / Allow notifications in system settings to receive messages from your chats. / Open settings

## Design-system components
- AppBar (title)
- SettingsGroup / SettingsSwitchRow
- InfoBanner

---
Live design: open `index.html` → 7.2 Notifications (switch states with the chips). Components are rendered from the shared design system (`_src/`).
