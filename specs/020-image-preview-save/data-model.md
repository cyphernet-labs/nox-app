# Data Model: Image thumbnails + full-screen viewer + real save (F4+F2)

## MessageAttachment (domain) — EDIT
| Field | Type | Note |
|-------|------|------|
| id, type, name, sizeBytes | (existing) | |
| `localPath` | `String?` | NEW — device-local path of the picked/sent file; null for seeded/backend attachments |

## PickedFile (domain typedef) — EDIT
`({String name, int sizeBytes, String? extension, String? path})` — `path` = `XFile.path`.

## MessageEntity (Sembast) — EDIT
| Field | Type | Note |
|-------|------|------|
| attachmentId/Type/Name/SizeBytes | (existing, nullable) | |
| `attachmentLocalPath` | `String?` | NEW — persists localPath (flattened) |

## MessageMapper (Sembast) — EDIT
- toModel: `localPath: entity.attachmentLocalPath` (inside the attachment build).
- toEntity: `attachmentLocalPath: model.attachment?.localPath`.

## Flow
```
pick image → PickedFile(path) → draft MessageAttachment(localPath) → send (echo preserves it) →
  MessageMapper.toEntity persists attachmentLocalPath in Sembast → survives restart (while the file exists).
getMessages seed (wire) → no localPath (seeded); user-sent messages read back from Sembast keep localPath.
render: type==image && localPath!=null/notEmpty && File(localPath).existsSync() → thumbnail (Image.file); else chip.
```

## Full-screen viewer (new)
`ImageViewerPage(localPath)` — adaptive (mobile push / desktop lightbox), `InteractiveViewer` (zoom) + close/back,
`Image.file` with a graceful error placeholder.
