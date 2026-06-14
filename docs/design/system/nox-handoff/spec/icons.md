# NOX — Icon map

Set: **Material Symbols Rounded** (weight 400, optical 24, grade 0). Default size 24;
large icons on 3.1 / 5.3 are 48–96. Flutter: `Icons.*` (Material Icons) or the
`material_symbols_icons` package (`Symbols.*`) — same glyph. Authoritative set for the
mockups = Material Symbols Rounded.

> **Outlined vs filled = the FILL axis, not a name suffix.** Material Symbols has no `*_outlined`
> ligature; the base name (e.g. `forum`) renders outlined at `FILL 0` and filled at `FILL 1`.
> Flutter: `Icon(Symbols.forum, fill: 1)`, or the stock `Icons.forum` / `Icons.forum_outlined`
> constants which bake fill into the name. Names below are base ligatures.

## Navigation (4.1)
| Use | Selected (FILL 1) | Unselected (FILL 0) |
|---|---|---|
| Chats | `forum` | `forum` |
| Settings | `settings` | `settings` |
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
| Error | `error` (FILL 0) | `error` |

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
| 5.1 no chats | `forum` (FILL 0) |
| 5.2 no messages | `chat_bubble` (FILL 0) |
| 5.4 no files | `folder_open` |

## Misc
| Use | Icon |
|---|---|
| Universal error (3.1) | `error` (FILL 0) |
| Avatar fallback (no valid initials) | `forum` (white on hash-color bg) |
