# 03 · Splash

> **03 · Onboarding** · desktop (Windows / Linux / macOS) · Material 3 · window 1440×900

**Purpose.** Cold-start brand moment (desktop window, no chrome).

**Adaptation from mobile.** same SplashScreen content; desktop draws it edge-to-edge without the title bar

## Anatomy
Full dark window (brand-fixed canvas), no title bar; centered logo + NOX wordmark.

## States
- `default` — Splash

## Behavior
- Same role as mobile 1.1. Chrome hidden; brand-fixed dark, not themed. One-shot reveal.

## Navigation
- Valid ID → Chats (01).
- No ID → Login (03).

## Copy (EN)
- Wordmark: NOX

## Design-system components
- DesktopWindow (chrome=false)
- SplashScreen (shared)
- Brand: canvasDark, white

---
Live design: open `index.html` → 03 Splash (switch states with the chips). The desktop shell re-arranges the SAME widgets as mobile — only the wrapper differs.
