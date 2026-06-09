# 05 · Error

> **05 · States** · desktop (Windows / Linux / macOS) · Material 3 · window 1440×900

**Purpose.** Full-window fatal / unexpected error with retry.

**Adaptation from mobile.** mobile 3.1 → full-window centered state

## Anatomy
Title bar (NOX · Error) + centered error glyph (96) + title + message + “Try again”.

## States
- `default` — Error

## Behavior
- Desktop form of mobile 3.1. Other recoverable states (offline / loading / empty) are shown as states of Chats (01) and Settings (02) rather than separate screens.

## Navigation
- Try again → re-runs the failed action.

## Copy (EN)
- Default: Something went wrong / Please try again. · Action: Try again

## Design-system components
- DesktopWindow + TitleBar
- DesktopError
- Icon: error_outline (96)
- FilledButton

---
Live design: open `index.html` → 05 Error (switch states with the chips). The desktop shell re-arranges the SAME widgets as mobile — only the wrapper differs.
