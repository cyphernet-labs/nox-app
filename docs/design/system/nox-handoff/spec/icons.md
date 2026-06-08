# NOX — Icon map

Set: **Material Symbols Rounded** (weight 400, optical 24, grade 0). Default size 24;
large icons on 3.1 / 5.3 are 48–96. Flutter: `Icons.*` (Material Icons) or the
`material_symbols_icons` package (`Symbols.*`) — same glyph. Authoritative set for the
mockups = Material Symbols Rounded.

## Navigation (4.1)
| Use | Selected | Unselected |
|---|---|---|
| Chats | `forum` | `forum_outlined` |
| Settings | `settings` | `settings_outlined` |
| Center action | `add` | — |

## Actions
| Action | Icon |
|---|---|
| Back | `arrow_back` |
| Paste | `content_paste` |
| Scan QR | `qr_code_scanner` |
| Attach | `attach_file` |
| Send | `send` |
| Flashlight | `flashlight_on` / `flashlight_off` |
| Switch camera | `cameraswitch` |
| Search | `search` |
| Show / hide | `visibility` / `visibility_off` |
| Copy | `content_copy` |
| Show QR | `qr_code` |
| Save / download | `download` |
| Edit | `edit` |
| Remove attachment | `close` |

## Message status (5.2)
| Status | Icon | Color |
|---|---|---|
| Pending | `schedule` | `onSurfaceVariant` |
| Sent | `check` | `onSurfaceVariant` |
| Error | `error_outline` | `error` |

## File-type chips (no content preview anywhere)
| Type | Icon |
|---|---|
| Image | `image` |
| Video | `videocam` |
| Audio | `audiotrack` |
| PDF | `picture_as_pdf` |
| Document (doc/docx/odt) | `description` |
| Spreadsheet (xls/csv) | `table_chart` |
| Text | `article` |
| Archive (zip/rar/7z) | `folder_zip` |
| Other / unknown | `insert_drive_file` |

## Empty states (fallback until illustrations ship)
| Screen | Icon |
|---|---|
| 5.1 no chats | `forum_outlined` |
| 5.2 no messages | `chat_bubble_outline` |
| 5.4 no files | `folder_open` |

## Misc
| Use | Icon |
|---|---|
| Universal error (3.1) | `error_outline` |
| Avatar fallback (no valid initials) | `forum` (white on hash-color bg) |
