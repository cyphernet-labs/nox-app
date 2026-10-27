# Contract: image preview + full-screen + real save (F4+F2)

## Inline thumbnail (AppImageAttachmentWidget, new)
- Input: MessageAttachment (image, non-empty localPath, existing file) + onColor/inBubble context + onTap.
- Renders Image.file(File(localPath)) clipped to a rounded box, bounded to the bubble width.
- errorBuilder → falls back to AppFileChipWidget (never a broken image).
- onTap → open ImageViewerPage(localPath).

## Thread wiring (AppThreadViewWidget)
- if (attachment.type == FileType.image && (attachment.localPath?.isNotEmpty ?? false) && File(localPath).existsSync())
    → AppImageAttachmentWidget(...);  else → AppFileChipWidget(...) (unchanged).

## Full-screen viewer (ImageViewerPage, new)
- openImageViewer(context, localPath): mobile → push; desktop → Dialog lightbox (mirrors showFileView).
- InteractiveViewer (minScale 1, maxScale ~5) around Image.file; close (back / X / tap-scrim on desktop).
- Missing file → a graceful placeholder (icon + message), not a crash.

## Real save (FileViewPage._save, F2)
```
final path = file.localPath;
if (path == null || path.isEmpty || !File(path).existsSync()) { showSnackBar(savedToDownloads); return; } // mock fallback
final location = await getSaveLocation(suggestedName: file.name);
if (location == null) return; // cancelled
await File(location.path).writeAsBytes(await File(path).readAsBytes());
showSnackBar(savedToDownloads);
```
- Wrapped so any IO failure → error snackbar, never a crash.

## Invariants
- Non-image attachments, seeded thread, chips, thread goldens: UNCHANGED.
- localPath persists in Sembast; the S4 wire attachment is NOT changed (seeded → null → chip).
- macOS: files.user-selected.read-write entitlement for the save write.
