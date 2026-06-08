window.NOX_SPECS = [
  {
    "id": "splash",
    "num": "1.1",
    "title": "Splash",
    "group": "Onboarding",
    "purpose": "Cold-start brand moment while the app resolves auth and decides where to route.",
    "states": [
      {
        "key": "default",
        "label": "Splash"
      }
    ],
    "anatomy": "Brand-fixed dark canvas (#0C2424, NOT themed). Centered logo (168) + NOX wordmark below (Bold 700, +0.12em, #FAFAFA).",
    "behavior": [
      "Shown only on cold start. One-shot reveal ~400ms (emphasized-decelerate); no looping.",
      "While visible the app restores the stored ID and checks session validity.",
      "Background and wordmark colors are brand-fixed — they do NOT switch with light/dark theme."
    ],
    "navigation": [
      "Has stored, valid ID → Chats shell (4.1 / 5.1).",
      "No ID → Login (2.1).",
      "Resolution error → Error (3.1, blocking)."
    ],
    "copy": [
      "Wordmark: NOX"
    ],
    "ds": [
      "Brand: canvasDark, white",
      "Type: wordmark (Bold 700)",
      "Motion: splashIn 400ms"
    ]
  },
  {
    "id": "login",
    "num": "2.1",
    "title": "Login",
    "group": "Onboarding",
    "purpose": "Sign in by pasting / typing an existing account ID, or jump to QR scan.",
    "states": [
      {
        "key": "empty",
        "label": "Empty"
      },
      {
        "key": "filled",
        "label": "Filled"
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
    "anatomy": "App bar (NOX wordmark + splash hairline). Multiline mono ID field with a paste affordance (suffix). Pinned bottom: primary “Sign in”, secondary “Scan QR”.",
    "behavior": [
      "ID field is monospace, multiline (min 120), wraps break-all so a long ID never overflows.",
      "Empty: Sign in disabled, paste icon at 38%. As soon as there is a value → enabled.",
      "Submitting: button shows an inline spinner (onPrimary); field + Scan QR disabled.",
      "Format error: inline errorText “Invalid identifier” (client-side check before submit).",
      "Network/5xx on submit: inline errorText “Could not sign in. Check your connection and try again.”"
    ],
    "navigation": [
      "Success → Set username (2.3) for new IDs, else Chats (5.1).",
      "Scan QR → QR scan (2.2).",
      "Fatal/unexpected → Error (3.1)."
    ],
    "copy": [
      "Label: Your ID",
      "Placeholder: Paste or enter your ID",
      "Primary: Sign in",
      "Secondary: Scan QR",
      "Errors: “Invalid identifier” · “Could not sign in. Check your connection and try again.”"
    ],
    "ds": [
      "AppBar (wordmark)",
      "TextField (outlined, mono, multiline)",
      "FilledButton (loading)",
      "TextButton",
      "Icon: content_paste"
    ]
  },
  {
    "id": "qr-scan",
    "num": "2.2",
    "title": "QR scan",
    "group": "Onboarding",
    "purpose": "Scan another device’s ID QR with the camera.",
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
    "anatomy": "Live camera fills the screen. Transparent app bar (back, flashlight, switch-camera). Centered reticle with a 55% black mask (brand-fixed). Top instruction; bottom “Enter manually”.",
    "behavior": [
      "App bar over the feed has no surface fill and no splash hairline (splash=false).",
      "Reticle stroke is brand white (3dp), corners radius m; mask is #000 at 55% (brand-fixed, not themed).",
      "Detecting a valid code signs in immediately (same outcome as Login success).",
      "Permission denied → opaque surface screen (NOT over the camera) with no_photography glyph + “Open settings”."
    ],
    "navigation": [
      "Valid scan → Set username (2.3) / Chats (5.1).",
      "Back → Login (2.1).",
      "Enter manually → Login (2.1).",
      "Open settings → OS settings."
    ],
    "copy": [
      "Instruction: Aim your camera at a QR code",
      "Bottom: Enter manually",
      "Denied title: Camera access needed",
      "Denied body: To scan a QR code, allow camera access in system settings.",
      "Denied action: Open settings"
    ],
    "ds": [
      "AppBar (splash=false, actions flashlight_on/cameraswitch)",
      "Brand: white, scrim mask",
      "Icon: no_photography",
      "FilledButton"
    ]
  },
  {
    "id": "username",
    "num": "2.3",
    "title": "Set username",
    "group": "Onboarding",
    "purpose": "Pick the display name others see (optional — server pre-assigns one).",
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
    "anatomy": "App bar (wordmark). Name field with counter N/32 + helper. Pinned bottom: primary “Done”, secondary “Skip”.",
    "behavior": [
      "Pre-filled with the server default handle (e.g. User1234); user may keep, edit or skip.",
      "Max 32 chars; counter updates live. Charset for username is restricted ([A-Za-z0-9._-]).",
      "Checking: trailing spinner while uniqueness is verified.",
      "Taken: errorText “This name is taken”; Done disabled until resolved. Empty: Done disabled."
    ],
    "navigation": [
      "Done / Skip → Chats shell (5.1)."
    ],
    "copy": [
      "Label: Name",
      "Placeholder: How others will see you",
      "Counter: N/32",
      "Helper: Others see this name. You can change it now or later in Settings.",
      "Error: This name is taken",
      "Primary: Done",
      "Secondary: Skip"
    ],
    "ds": [
      "AppBar (wordmark)",
      "TextField (counter, helper, spinner suffix)",
      "FilledButton",
      "TextButton"
    ]
  },
  {
    "id": "error",
    "num": "3.1",
    "title": "Error (universal)",
    "group": "Onboarding",
    "purpose": "Reusable fatal / unexpected error state with a retry.",
    "states": [
      {
        "key": "blocking",
        "label": "Blocking"
      },
      {
        "key": "embedded",
        "label": "Embedded"
      }
    ],
    "anatomy": "Centered error glyph (onSurfaceVariant, 48–96) + title + message + primary “Try again”.",
    "behavior": [
      "Blocking variant has NO back (it is the last entry in the stack — e.g. failed cold-start).",
      "Embedded variant shows a back arrow (reached from within a flow).",
      "Props: icon, title, message, onRetry. Copy pattern: “Could not <verb>. Check your connection and try again.”"
    ],
    "navigation": [
      "Try again → re-runs the failed action.",
      "Embedded back → previous screen."
    ],
    "copy": [
      "Default title: Something went wrong",
      "Action: Try again"
    ],
    "ds": [
      "Icon: error_outline (80)",
      "Type: headlineSmall + bodyMedium",
      "FilledButton",
      "AppBar (embedded only)"
    ]
  },
  {
    "id": "shell",
    "num": "4.1",
    "title": "Navigation shell",
    "group": "Shell & Chats",
    "purpose": "Top-level scaffold hosting the two destinations + the create action.",
    "states": [
      {
        "key": "chats",
        "label": "Chats tab"
      },
      {
        "key": "settings",
        "label": "Settings tab"
      }
    ],
    "anatomy": "BottomAppBar (surfaceContainer, elev 2) with a circular notch; two tabs (Chats forum / Settings settings); a docked “+” FAB (primaryContainer, elev 3) cradled in the notch.",
    "behavior": [
      "Two destinations switch via an IndexedStack with a ≤150ms fade (tabFade); state is preserved per tab.",
      "Selected tab → primary + filled icon; unselected → onSurfaceVariant + outlined icon.",
      "The “+” is an action (create chat), NOT a third tab — it is visible on both tabs."
    ],
    "navigation": [
      "Chats tab → 5.1.",
      "Settings tab → 7.1.",
      "+ → Create chat (6.1)."
    ],
    "copy": [
      "Tabs: Chats · Settings"
    ],
    "ds": [
      "BottomBar (notch + docked FAB)",
      "Icon: forum / settings / add",
      "Motion: tabFade 150ms"
    ]
  },
  {
    "id": "chats",
    "num": "5.1",
    "title": "Chats list",
    "group": "Shell & Chats",
    "purpose": "Browse and search all chats; entry point to threads and create.",
    "states": [
      {
        "key": "filled",
        "label": "Filled"
      },
      {
        "key": "loading",
        "label": "Loading"
      },
      {
        "key": "empty",
        "label": "Empty"
      },
      {
        "key": "offline",
        "label": "Offline"
      },
      {
        "key": "inline-error",
        "label": "Load error"
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
    "anatomy": "App bar (wordmark) + persistent SearchBar + scrollable list of chat rows. Bottom bar + FAB.",
    "behavior": [
      "Rows: avatar (with ring) + name + last-message preview + relative time + unread badge.",
      "Unread emphasis: name w600, preview onSurface, time primary, badge shown (caps 99+, hidden at 0).",
      "Loading: centered spinner. Empty: forum empty-state.",
      "Offline: persistent “No connection” MaterialBanner at top. Load error: banner “Could not load chats. Pull to refresh.”",
      "Tapping the SearchBar opens the full search view (back + query + caret, clear); results filter live; no match → “No chats found”.",
      "Transient one-off feedback appears as a Snackbar floating above the bottom bar."
    ],
    "navigation": [
      "Row → Chat thread (5.2).",
      "+ → Create chat (6.1).",
      "Search → search view (same screen)."
    ],
    "copy": [
      "Search hint: Search",
      "Empty: No chats yet / Tap + to create the first one.",
      "Load error: Could not load chats. Pull to refresh.",
      "Search empty: No chats found"
    ],
    "ds": [
      "AppBar (wordmark)",
      "SearchBar / SearchView",
      "ChatListItem (unread Badge)",
      "MaterialBanner",
      "EmptyState",
      "Snackbar",
      "BottomBar"
    ]
  },
  {
    "id": "thread",
    "num": "5.2",
    "title": "Chat thread",
    "group": "Shell & Chats",
    "purpose": "Read and send messages + files within one chat.",
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
        "key": "attachment",
        "label": "Attachment"
      },
      {
        "key": "offline",
        "label": "Offline"
      }
    ],
    "anatomy": "App bar (back + chat name). Message stream with date separators, author headers and bubbles. Composer pinned at bottom.",
    "behavior": [
      "Messages group by author; an AuthorHeader precedes each group (no per-message avatars in the feed).",
      "Own bubbles = primaryContainer (right, bottom-right corner clipped); others = surfaceContainerHigh (left, bottom-left clipped).",
      "Own message status: pending (schedule) → sent (check) → error (error, tinted error; tap to retry).",
      "Date separators: Today / Yesterday / 12 May. A system line marks chat creation.",
      "Empty: chat_bubble_outline empty-state. Offline: top banner + queued messages show pending.",
      "Composer: attach + text + send. Send enables when there is text or an attachment; attachment shows a removable chip above the row."
    ],
    "navigation": [
      "Back → Chats list (5.1).",
      "Attachment chip / file bubble → File view (5.3).",
      "(Header affordances to chat card exist on desktop; mobile reaches files via 5.4 entry.)"
    ],
    "copy": [
      "System: Chat created by Aria",
      "Composer placeholder: Message"
    ],
    "ds": [
      "AppBar (title)",
      "MsgBubble (+status)",
      "FileChip (in-bubble)",
      "DateSep / AuthorHeader / SystemLine",
      "Composer",
      "MaterialBanner",
      "EmptyState"
    ]
  },
  {
    "id": "file",
    "num": "5.3",
    "title": "File view",
    "group": "Shell & Chats",
    "purpose": "Inspect / download a single file. No in-app content preview.",
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
    "anatomy": "App bar (back + file name + download action). Large type glyph in a tinted tile + file name + size.",
    "behavior": [
      "No content preview — a large file-type glyph stands in (brand-tinted by type).",
      "Downloading: a determinate LinearProgress under the app bar (primary on surfaceVariant track) + “Downloading… N%”.",
      "Loaded: shows the file size."
    ],
    "navigation": [
      "Back → previous (thread 5.2 or chat card 5.4).",
      "Download → saves to device."
    ],
    "copy": [
      "Size example: 2.4 MB",
      "Progress: Downloading… 64%"
    ],
    "ds": [
      "AppBar (title, action download)",
      "FileGlyph / fileColor",
      "LinearProgress",
      "Type: titleLarge + bodyMedium"
    ]
  },
  {
    "id": "card",
    "num": "5.4",
    "title": "Chat card",
    "group": "Shell & Chats",
    "purpose": "Chat header + its shared files.",
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
    "anatomy": "App bar (back + chat name). Header: avatar (56) + name (headlineSmall). “Files” section with a List/Grid segmented toggle, then file rows or a grid.",
    "behavior": [
      "List rows: file glyph + name (ellipsis) + size + chevron. Grid: square type cells.",
      "Segmented control switches List ⇄ Grid (single-select).",
      "Empty: folder_open empty-state."
    ],
    "navigation": [
      "Back → thread (5.2).",
      "File row / cell → File view (5.3)."
    ],
    "copy": [
      "Section: Files",
      "Empty: No files yet / Files sent in this chat will appear here."
    ],
    "ds": [
      "AppBar (title)",
      "Avatar (56)",
      "Segmented",
      "FileGlyph",
      "EmptyState"
    ]
  },
  {
    "id": "create",
    "num": "6.1",
    "title": "Create chat",
    "group": "Shell & Chats",
    "purpose": "Create a new chat by unique name.",
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
    "anatomy": "App bar (back + “New chat”). Chat-name field with counter N/64. Pinned primary “Create”.",
    "behavior": [
      "Max 64 chars, charset unrestricted; counter updates live.",
      "Checking: trailing spinner during uniqueness check. Taken: errorText “This name is taken”, Create disabled.",
      "Valid → Create enabled. Submitting: button spinner."
    ],
    "navigation": [
      "Create success → the new Chat thread (5.2).",
      "Back → Chats list (5.1)."
    ],
    "copy": [
      "Label: Chat name",
      "Placeholder: e.g. Random thoughts",
      "Counter: N/64",
      "Error: This name is taken",
      "Primary: Create"
    ],
    "ds": [
      "AppBar (title)",
      "TextField (counter, spinner suffix)",
      "FilledButton (loading)"
    ]
  },
  {
    "id": "settings",
    "num": "7.1",
    "title": "Settings root",
    "group": "Settings",
    "purpose": "Account identity + grouped settings entries.",
    "states": [
      {
        "key": "loaded",
        "label": "Loaded"
      },
      {
        "key": "id-shown",
        "label": "ID revealed"
      },
      {
        "key": "editing",
        "label": "Editing name"
      },
      {
        "key": "qr",
        "label": "QR sheet"
      },
      {
        "key": "logout",
        "label": "Logout dialog"
      },
      {
        "key": "logout-loading",
        "label": "Logging out"
      }
    ],
    "anatomy": "App bar (Settings). Identity card (name + masked ID). Grouped list: Notifications, Appearance, Language, Terms, About. Separate destructive Log out group. Bottom bar.",
    "behavior": [
      "Identity card: name (edit inline) + ID masked as •••••••• with reveal / copy / show-QR actions.",
      "Reveal (id-shown): full ID rendered mono, wrapped break-all, with hide/copy/QR.",
      "Editing: name becomes an inline TextField with counter.",
      "Show QR → modal bottom sheet; the QR card surface is brand-fixed WHITE so it scans in dark mode.",
      "Log out → confirm AlertDialog (destructive action tinted error); confirming wipes ID + local data; shows a loading state."
    ],
    "navigation": [
      "Rows → 7.2 / 7.3 / 7.4 / Terms / About.",
      "Log out (confirmed) → Login (2.1)."
    ],
    "copy": [
      "Title: Settings",
      "ID mask: ••••••••",
      "Logout title: Log out?",
      "Logout body: Your ID and local data will be removed from this device.",
      "Actions: Cancel · Log out"
    ],
    "ds": [
      "AppBar (title)",
      "IdentityCard",
      "SettingsGroup / SettingsNavRow",
      "QRSheet (brand white)",
      "LogoutDialog",
      "BottomBar"
    ]
  },
  {
    "id": "notifications",
    "num": "7.2",
    "title": "Notifications",
    "group": "Settings",
    "purpose": "Toggle push notifications.",
    "states": [
      {
        "key": "on",
        "label": "Enabled"
      },
      {
        "key": "denied",
        "label": "OS-denied"
      }
    ],
    "anatomy": "App bar (back + Notifications). Grouped switch row “Enable notifications”.",
    "behavior": [
      "Single switch with supporting text “Only for chats you’re in”.",
      "If the OS permission is denied, an InfoBanner appears (“Notifications are blocked” + Open settings) and the switch reads off."
    ],
    "navigation": [
      "Back → Settings (7.1).",
      "Open settings → OS settings."
    ],
    "copy": [
      "Row: Enable notifications / Only for chats you’re in",
      "Denied: Notifications are blocked / Allow notifications in system settings to receive messages from your chats. / Open settings"
    ],
    "ds": [
      "AppBar (title)",
      "SettingsGroup / SettingsSwitchRow",
      "InfoBanner"
    ]
  },
  {
    "id": "appearance",
    "num": "7.3",
    "title": "Appearance",
    "group": "Settings",
    "purpose": "Choose the theme: System / Light / Dark.",
    "states": [
      {
        "key": "System",
        "label": "System"
      },
      {
        "key": "Light",
        "label": "Light"
      },
      {
        "key": "Dark",
        "label": "Dark"
      }
    ],
    "anatomy": "App bar (back + Appearance). Three theme option cards, each a mini preview thumbnail + label + radio.",
    "behavior": [
      "Single-select radio cards; the selected card is outlined primary + filled surface.",
      "System matches the OS; selection maps to Flutter ThemeMode.{system,light,dark}.",
      "Applies immediately, app-wide."
    ],
    "navigation": [
      "Back → Settings (7.1)."
    ],
    "copy": [
      "Options: System / Match your device · Light / Always light · Dark / Always dark"
    ],
    "ds": [
      "AppBar (title)",
      "ThemeOptionCard (radio + thumbnail)"
    ]
  },
  {
    "id": "language",
    "num": "7.4",
    "title": "Language",
    "group": "Settings",
    "purpose": "Choose the app language.",
    "states": [
      {
        "key": "System",
        "label": "System"
      },
      {
        "key": "English",
        "label": "English"
      },
      {
        "key": "Українська",
        "label": "Українська"
      }
    ],
    "anatomy": "App bar (back + Language). Grouped radio rows with a leading flag/glyph: System, English, Українська.",
    "behavior": [
      "Single-select. System follows the OS locale and falls back to English if the OS is neither EN nor UK.",
      "Applies immediately."
    ],
    "navigation": [
      "Back → Settings (7.1)."
    ],
    "copy": [
      "Options: System · English · Українська"
    ],
    "ds": [
      "AppBar (title)",
      "SettingsGroup / LangRow",
      "FlagUK / FlagUA / SysCircle"
    ]
  },
  {
    "id": "terms",
    "num": "7.6",
    "title": "Terms",
    "group": "Settings",
    "purpose": "Static Terms of Service text.",
    "states": [
      {
        "key": "default",
        "label": "Terms"
      }
    ],
    "anatomy": "App bar (back + Terms). Scrollable titled sections + version line. Body is shared verbatim with the desktop Terms detail pane (TermsBody).",
    "behavior": [
      "Read-only legal copy. The exact same TermsBody renders on mobile and desktop — one source."
    ],
    "navigation": [
      "Back → Settings (7.1)."
    ],
    "copy": [
      "Heading: Terms of Service",
      "Sections: Acceptance · Your identity · Content · Privacy",
      "Footer: Version 1.2.3"
    ],
    "ds": [
      "AppBar (title)",
      "TermsBody (shared)"
    ]
  },
  {
    "id": "about",
    "num": "7.7",
    "title": "About",
    "group": "Settings",
    "purpose": "App version / build.",
    "states": [
      {
        "key": "default",
        "label": "About"
      }
    ],
    "anatomy": "App bar (back + About). Grouped row: Version → 1.2.3 (build 456).",
    "behavior": [
      "Static informational row."
    ],
    "navigation": [
      "Back → Settings (7.1)."
    ],
    "copy": [
      "Version: 1.2.3 (build 456)"
    ],
    "ds": [
      "AppBar (title)",
      "SettingsGroup / SettingsNavRow (trailing value)"
    ]
  }
];
