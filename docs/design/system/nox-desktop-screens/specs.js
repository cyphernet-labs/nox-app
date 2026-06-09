window.NOX_SPECS = [
  {
    "id": "d-chats",
    "num": "01",
    "title": "Chats",
    "group": "01 · Chats",
    "frame": "window",
    "purpose": "Primary workspace: a two-pane list-detail of all chats (left) and the open thread (right).",
    "states": [
      {
        "key": "filled",
        "label": "Selected"
      },
      {
        "key": "no-selection",
        "label": "No selection"
      },
      {
        "key": "thread-empty",
        "label": "Thread empty"
      },
      {
        "key": "attachment",
        "label": "Attachment"
      },
      {
        "key": "offline",
        "label": "Offline"
      },
      {
        "key": "loading",
        "label": "Loading"
      },
      {
        "key": "search",
        "label": "Search"
      },
      {
        "key": "search-empty",
        "label": "Search empty"
      },
      {
        "key": "snack",
        "label": "Snackbar"
      }
    ],
    "anatomy": "NavigationRail (80) + chat list pane (360, with pane header + SearchBar) + thread pane (header, message stream capped to a ≤980 reading column, composer). The mobile bottom bar becomes the rail; full-screen list/thread become side-by-side panes.",
    "behavior": [
      "Selecting a row highlights it (secondaryContainer) and loads the thread on the right — no navigation push.",
      "No-selection: the thread pane shows a “Select a chat” placeholder; the “+” lives on the rail.",
      "Thread header is persistent (avatar, members, search/folder/info actions) — a desktop affordance the mobile thread lacks.",
      "Offline: “No connection” banner appears in both panes. Loading: spinner in the list pane.",
      "Search filters the list pane in place; no match → “No chats found”.",
      "Transient feedback floats as a Snackbar centered over the thread pane."
    ],
    "navigation": [
      "Row → loads thread in right pane.",
      "Rail + → Create chat dialog (04).",
      "Thread folder/info → Chat info drawer (04).",
      "Attachment / file bubble → File view lightbox (04)."
    ],
    "copy": [
      "Pane titles: Chats",
      "No-selection: Select a chat / Choose a conversation on the left, or press + to start a new one.",
      "Thread sub: Aria, Mox and you"
    ],
    "ds": [
      "NavRail",
      "PaneHeader",
      "SearchBar",
      "ChatListItem (selectable ChatRow)",
      "ThreadHeader",
      "MsgBubble / DateSep / AuthorHeader",
      "Composer",
      "MaterialBanner",
      "EmptyState",
      "Snackbar"
    ],
    "adapt": "mobile BottomBar → NavigationRail · full screens (5.1 + 5.2) → list-detail panes"
  },
  {
    "id": "d-settings",
    "num": "02",
    "title": "Settings",
    "group": "02 · Settings",
    "frame": "window",
    "purpose": "List-detail settings: menu pane (left) + the selected section’s panel (right).",
    "states": [
      {
        "key": "account",
        "label": "Account"
      },
      {
        "key": "account-editing",
        "label": "Account · editing"
      },
      {
        "key": "notifications",
        "label": "Notifications"
      },
      {
        "key": "notifications-denied",
        "label": "Notif · denied"
      },
      {
        "key": "appearance",
        "label": "Appearance"
      },
      {
        "key": "language",
        "label": "Language"
      },
      {
        "key": "terms",
        "label": "Terms"
      },
      {
        "key": "about",
        "label": "About"
      },
      {
        "key": "logout",
        "label": "Logout dialog"
      },
      {
        "key": "qr",
        "label": "QR dialog"
      }
    ],
    "anatomy": "NavigationRail + settings menu pane (340, grouped nav items) + detail pane (content capped to ≤680). Each detail reuses the exact phone widgets.",
    "behavior": [
      "Selecting a menu item highlights it (secondaryContainer) and swaps the detail pane — no push.",
      "Account: identity card; by default the ID stays masked and the account QR is shown inline (no secret reveal on desktop). Editing → inline name field.",
      "Notifications: enable switch; OS-denied → InfoBanner + Open settings, switch off.",
      "Appearance: System / Light / Dark theme cards. Language: System / English / Українська.",
      "Log out → centered confirm Dialog (mobile’s sheet/dialog becomes a centered dialog); destructive action tinted error.",
      "Show QR → centered Dialog with the brand-fixed white QR card (mobile bottom-sheet → dialog)."
    ],
    "navigation": [
      "Menu item → swaps detail pane.",
      "Log out (confirmed) → Login (03)."
    ],
    "copy": [
      "Pane title: Settings",
      "Account QR caption: Show this code to let someone add you",
      "Logout: Log out? / Your ID and local data will be removed from this device."
    ],
    "ds": [
      "NavRail",
      "PaneHeader",
      "SettingsNavItem",
      "IdentityCard",
      "FakeQR (brand white)",
      "SettingsGroup / SettingsSwitchRow / LangRow",
      "ThemeOptionCard",
      "InfoBanner",
      "TermsBody",
      "LogoutDialog / CenteredQR"
    ],
    "adapt": "mobile full-screen settings → list-detail · bottom sheet → centered dialog · ID masked + account QR by default"
  },
  {
    "id": "d-splash",
    "num": "03",
    "title": "Splash",
    "group": "03 · Onboarding",
    "frame": "window",
    "purpose": "Cold-start brand moment (desktop window, no chrome).",
    "states": [
      {
        "key": "default",
        "label": "Splash"
      }
    ],
    "anatomy": "Full dark window (brand-fixed canvas), no title bar; centered logo + NOX wordmark.",
    "behavior": [
      "Same role as mobile 1.1. Chrome hidden; brand-fixed dark, not themed. One-shot reveal."
    ],
    "navigation": [
      "Valid ID → Chats (01).",
      "No ID → Login (03)."
    ],
    "copy": [
      "Wordmark: NOX"
    ],
    "ds": [
      "DesktopWindow (chrome=false)",
      "SplashScreen (shared)",
      "Brand: canvasDark, white"
    ],
    "adapt": "same SplashScreen content; desktop draws it edge-to-edge without the title bar"
  },
  {
    "id": "d-login",
    "num": "03",
    "title": "Login",
    "group": "03 · Onboarding",
    "frame": "window",
    "purpose": "Sign in with an ID on desktop — a centered card on an empty window.",
    "states": [
      {
        "key": "filled",
        "label": "Filled"
      },
      {
        "key": "empty",
        "label": "Empty"
      },
      {
        "key": "loading",
        "label": "Submitting"
      },
      {
        "key": "error-format",
        "label": "Format error"
      },
      {
        "key": "error-net",
        "label": "Network error"
      }
    ],
    "anatomy": "Title bar (NOX · Sign in) + centered OnboardCard (440): logo + wordmark + brand hairline, mono multiline ID field, “Sign in”, “Scan QR”.",
    "behavior": [
      "Same field rules as mobile 2.1 (mono, multiline, paste, validation, loading), re-laid into a centered card.",
      "Empty → Sign in disabled. Submitting → button spinner. Format/network errors → inline errorText."
    ],
    "navigation": [
      "Success → Set username (03) or Chats (01).",
      "Scan QR → QR scan (03)."
    ],
    "copy": [
      "Label: Your ID",
      "Primary: Sign in",
      "Secondary: Scan QR",
      "Errors: Invalid identifier · Network error. Try again."
    ],
    "ds": [
      "DesktopWindow + TitleBar",
      "OnboardCard",
      "TextField (mono, multiline)",
      "FilledButton (loading)",
      "TextButton"
    ],
    "adapt": "mobile full-screen form → centered card; identical field + button widgets"
  },
  {
    "id": "d-username",
    "num": "03",
    "title": "Set username",
    "group": "03 · Onboarding",
    "frame": "window",
    "purpose": "Pick the display name — centered card.",
    "states": [
      {
        "key": "prefilled",
        "label": "Prefilled"
      },
      {
        "key": "checking",
        "label": "Checking"
      },
      {
        "key": "taken",
        "label": "Taken"
      },
      {
        "key": "empty",
        "label": "Empty"
      }
    ],
    "anatomy": "Title bar (NOX · Set up) + OnboardCard with name field (counter N/32, helper), “Done”, “Skip”.",
    "behavior": [
      "Same as mobile 2.3: pre-filled default, ≤32 chars, live uniqueness (spinner), taken → error + Done disabled."
    ],
    "navigation": [
      "Done / Skip → Chats (01)."
    ],
    "copy": [
      "Label: Name",
      "Counter: N/32",
      "Helper: Others see this name. You can change it now or later in Settings.",
      "Primary: Done · Secondary: Skip"
    ],
    "ds": [
      "DesktopWindow + TitleBar",
      "OnboardCard",
      "TextField (counter, spinner)",
      "FilledButton",
      "TextButton"
    ],
    "adapt": "mobile full-screen form → centered card"
  },
  {
    "id": "d-qr",
    "num": "03",
    "title": "QR scan",
    "group": "03 · Onboarding",
    "frame": "window",
    "purpose": "Scan an ID QR with the webcam, or fall back to manual entry.",
    "states": [
      {
        "key": "scan",
        "label": "Scanning"
      },
      {
        "key": "denied",
        "label": "Permission denied"
      }
    ],
    "anatomy": "Title bar (NOX · Scan QR) + centered viewfinder (300, brand-white corners) + helper with a manual-entry link. Denied → OnboardCard with no_photography + Open settings.",
    "behavior": [
      "Webcam feed inside the viewfinder; valid code signs in. Manual-entry link routes to Login.",
      "Permission denied → card with explanation + Open settings (system)."
    ],
    "navigation": [
      "Valid scan → Set username / Chats.",
      "Enter manually → Login (03).",
      "Open settings → OS settings."
    ],
    "copy": [
      "Title: Scan a QR code",
      "Helper: Point your webcam at a code, or enter the ID manually.",
      "Denied: Camera access needed / To scan a QR code, allow camera access in system settings. / Open settings"
    ],
    "ds": [
      "DesktopWindow + TitleBar",
      "Viewfinder",
      "OnboardCard (denied)",
      "Brand: white",
      "Icon: no_photography",
      "FilledButton"
    ],
    "adapt": "mobile full-screen camera → windowed viewfinder; permission state reuses the onboarding card"
  },
  {
    "id": "d-create",
    "num": "04",
    "title": "Create chat",
    "group": "04 · Flows & dialogs",
    "frame": "window",
    "purpose": "Create a chat — a centered modal dialog over the chats window.",
    "states": [
      {
        "key": "valid",
        "label": "Valid"
      },
      {
        "key": "checking",
        "label": "Checking"
      },
      {
        "key": "taken",
        "label": "Taken"
      },
      {
        "key": "loading",
        "label": "Submitting"
      },
      {
        "key": "empty",
        "label": "Empty"
      }
    ],
    "anatomy": "Scrim + centered Dialog (460): “New chat”, chat-name field (counter N/64), Cancel + Create.",
    "behavior": [
      "Mobile’s pushed 6.1 screen becomes a centered dialog over the (deselected) chats window.",
      "Same validation: ≤64 chars, live uniqueness (spinner), taken → error + Create disabled, submitting → spinner."
    ],
    "navigation": [
      "Create → opens the new thread in the right pane.",
      "Cancel / scrim → dismiss."
    ],
    "copy": [
      "Title: New chat",
      "Label: Chat name",
      "Counter: N/64",
      "Error: This name is taken",
      "Cancel · Create"
    ],
    "ds": [
      "ChatsDesktop (base)",
      "CreateChatDialog",
      "TextField (counter, spinner)",
      "FilledButton / TextButton"
    ],
    "adapt": "mobile pushed screen (6.1) → centered dialog"
  },
  {
    "id": "d-file",
    "num": "04",
    "title": "File view",
    "group": "04 · Flows & dialogs",
    "frame": "window",
    "purpose": "Inspect / download a file — a centered lightbox.",
    "states": [
      {
        "key": "loaded",
        "label": "Loaded"
      },
      {
        "key": "loading",
        "label": "Downloading"
      }
    ],
    "anatomy": "Heavier scrim + centered lightbox (520): header (type icon, name, download, close), large type glyph, name, size, Download.",
    "behavior": [
      "No content preview (type glyph). Downloading → determinate progress bar + “Downloading… N%”. Loaded → size + Download."
    ],
    "navigation": [
      "Close / scrim → back to the thread.",
      "Download → saves to disk."
    ],
    "copy": [
      "Size: 2.4 MB",
      "Progress: Downloading… 64%",
      "Action: Download"
    ],
    "ds": [
      "ChatsDesktop (base)",
      "FileViewDialog",
      "LinearProgress",
      "FileGlyph / fileColor",
      "FilledButton"
    ],
    "adapt": "mobile pushed File view (5.3) → centered lightbox"
  },
  {
    "id": "d-drawer",
    "num": "04",
    "title": "Chat info / Files",
    "group": "04 · Flows & dialogs",
    "frame": "window",
    "purpose": "Chat details + shared files — a right-side drawer.",
    "states": [
      {
        "key": "list",
        "label": "Files · list"
      },
      {
        "key": "grid",
        "label": "Files · grid"
      },
      {
        "key": "empty",
        "label": "Empty"
      }
    ],
    "anatomy": "Scrim + right drawer (380): Details header, chat avatar/name/members, “Files” with List/Grid toggle, file rows or 2-col grid.",
    "behavior": [
      "Mobile’s pushed Chat card (5.4) becomes a right drawer over the thread. Segmented switches List ⇄ Grid; empty → folder_open state."
    ],
    "navigation": [
      "Opened from the thread header info/folder action.",
      "File row / cell → File view lightbox.",
      "Close / scrim → dismiss."
    ],
    "copy": [
      "Title: Details",
      "Section: Files",
      "Empty: No files yet / Files sent in this chat will appear here."
    ],
    "ds": [
      "ChatsDesktop (base)",
      "ChatInfoDrawer",
      "Avatar (72)",
      "Segmented",
      "FileGlyph",
      "EmptyState"
    ],
    "adapt": "mobile pushed Chat card (5.4) → right details drawer"
  },
  {
    "id": "d-error",
    "num": "05",
    "title": "Error",
    "group": "05 · States",
    "frame": "window",
    "purpose": "Full-window fatal / unexpected error with retry.",
    "states": [
      {
        "key": "default",
        "label": "Error"
      }
    ],
    "anatomy": "Title bar (NOX · Error) + centered error glyph (96) + title + message + “Try again”.",
    "behavior": [
      "Desktop form of mobile 3.1. Other recoverable states (offline / loading / empty) are shown as states of Chats (01) and Settings (02) rather than separate screens."
    ],
    "navigation": [
      "Try again → re-runs the failed action."
    ],
    "copy": [
      "Default: Something went wrong / Please try again. · Action: Try again"
    ],
    "ds": [
      "DesktopWindow + TitleBar",
      "DesktopError",
      "Icon: error_outline (96)",
      "FilledButton"
    ],
    "adapt": "mobile 3.1 → full-window centered state"
  }
];
