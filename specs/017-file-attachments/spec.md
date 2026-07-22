# Feature Specification: Real File Attachments

**Feature Branch**: `017-file-attachments`

**Created**: 2026-07-25

**Status**: Draft

**Input**: User description: "Real file attachments end-to-end (client-side; no backend). Replace the hardcoded photo.jpg attachment stub with a real cross-platform file picker; the chat's shared-files view derives from the chat's persisted message attachments (not a fabricated list) and updates reactively. Add the standard native picker configuration for all five target platforms with a documented fallback; no upload/download of bytes (metadata only)."

## Overview

Today, attaching a file to a message is a placeholder: the composer's attach action always produces the same fixed attachment (`photo.jpg`, 1.8 MB, image), no matter what the user wants to send. And the chat's "shared files" view (5.4) shows a **fabricated, fixed list** of eight files that has nothing to do with what was actually sent in that chat.

This feature makes attachments **real, end-to-end, on the client**:

- **Pick a real file.** Tapping attach opens the platform's native file picker; the file the user actually chooses drives the draft attachment — its real name, real size, and a type derived from its extension.
- **See the real files.** The chat card's shared-files view is derived from the messages actually sent in that chat, so it lists exactly the files that were shared there.
- **Stay current.** When a new file is attached and sent, it appears in the files view without a manual reload.

No file bytes are uploaded, downloaded, or stored — this is the UI-first phase, so only the attachment's **metadata** (name / size / type) matters; the real transfer lands with the backend. The picker is wired on all five target platforms; unlike the QR scanner (which genuinely lacks a camera on Windows/Linux), the chosen picker supports every target, so the attach action is available everywhere and the platform-fallback clause is a defensive, documented note rather than an active hidden affordance.

## Clarifications

### Session 2026-07-25

- Q: In what order does the 5.4 shared-files view list a chat's files? → A: **Newest-first** — the most recently shared files appear at the top (consistent with chat recency).
- Q: The picker library supports all five targets — is the attach action available on every platform, or hidden on some (as QR is on Windows/Linux)? → A: **Available on all five platforms**; the picker supports each target, so no affordance is hidden. The platform-fallback requirement is retained as a defensive, documented safeguard (non-crashing) rather than an active hide.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Attach a real file from the composer (Priority: P1)

As someone writing a message, when I tap the attach action I get my device's real file picker and can choose any file; the composer then shows *that* file's name, size and type as the pending attachment — not a fixed placeholder.

**Why this priority**: This is the feature's core and the enabler for the other two — without real picked files, the files view has nothing real to show. It replaces the most visible stub in the chat composer.

**Independent Test**: Tap attach, choose a file of a known name/size/type, and confirm the composer's draft attachment shows that exact name, a correctly formatted size, and the matching type glyph. Choose a different file type and confirm the type glyph changes. Cancel the picker and confirm the composer is unchanged.

**Acceptance Scenarios**:

1. **Given** the chat composer, **When** the user taps attach and selects a file named `report.pdf` of a known size, **Then** the draft attachment shows `report.pdf`, that size (formatted), and the PDF type glyph.
2. **Given** the picker is open, **When** the user selects a file with an image / video / audio / spreadsheet / archive / document / text / unknown extension, **Then** the draft attachment's type matches (image/video/audio/sheet/archive/doc/text/other respectively).
3. **Given** the picker is open, **When** the user cancels without choosing, **Then** the composer keeps whatever draft/text it had and no attachment is added.
4. **Given** a chosen draft attachment, **When** the user removes it, **Then** the composer returns to no-attachment (unchanged from today).
5. **Given** a chosen draft attachment, **When** the user sends the message, **Then** the sent message carries that real attachment (name/size/type).

---

### User Story 2 - The chat's files view shows the files actually shared (Priority: P1)

As someone browsing a chat's shared files, I see exactly the files that were sent in this chat — not a canned list unrelated to the conversation.

**Why this priority**: The fabricated eight-file list is misleading (it implies files that were never sent). Deriving from the real messages is a correctness fix and the payoff of picking real files.

**Independent Test**: Open a chat's files view and confirm every listed file corresponds to an attachment present in that chat's messages; a chat with no attachments shows an empty files view; attaching+sending a new file then reopening the view shows it.

**Acceptance Scenarios**:

1. **Given** a chat whose messages include attachments, **When** the files view is opened, **Then** it lists exactly those attachments (name/size/type) newest-first, and nothing that was not sent in this chat.
2. **Given** a chat with no attachments, **When** the files view is opened, **Then** it shows the empty state.
3. **Given** two different chats with different attachments, **When** each files view is opened, **Then** each shows only its own chat's files.

---

### User Story 3 - The files view stays current when a new file is shared (Priority: P2)

As someone who just shared a file, when I look at the chat's files view it already includes the file I just sent — I don't have to reload.

**Why this priority**: Polish on top of the correctness fix (US2). It makes the files view feel live, consistent with the rest of the app's reactive lists.

**Independent Test**: With the files view reflecting a chat's files, attach and send a new file, and confirm it appears in the files view without a manual refresh.

**Acceptance Scenarios**:

1. **Given** a chat's files view is showing its current files, **When** a new file is attached and sent to that chat, **Then** the new file appears in the files view without a manual reload.
2. **Given** the files view, **When** no new files are added, **Then** it continues to show the current set unchanged.

---

### Edge Cases

- **Picker fails to present** (defensive — no target is expected to lack support): the attach action degrades gracefully (documented, non-crashing) rather than throwing. Unlike QR (no camera on Windows/Linux), the picker is available on all five targets, so this is a safeguard, not a routine hidden affordance.
- **Picker cancelled / no selection**: leaves the composer exactly as it was.
- **A file with no extension or an unknown extension**: is attached with the generic ("other") type rather than being rejected.
- **Very large file / long file name**: the attachment records the real size and name; display formatting (size units, name truncation) is unchanged from today's file chip.
- **Files view with a mix of file types**: renders each with its correct type glyph, as today.
- **No bytes are read/copied**: only metadata is captured; the picker's file content is never uploaded, downloaded, or persisted.
- **The seeded mock history's one attachment** remains present, so an unmodified seeded chat's files view is non-empty.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The composer's attach action MUST open the platform's native file picker (any file type) instead of producing a fixed placeholder attachment.
- **FR-002**: When a file is chosen, the draft attachment MUST reflect that file's real name and real size.
- **FR-003**: The attachment's type MUST be derived from the chosen file's extension, mapped to the existing file-type set (image, video, audio, pdf, doc, sheet, text, archive, other); an unknown/absent extension MUST map to the generic "other" type.
- **FR-004**: Cancelling the picker (or selecting nothing) MUST leave the composer unchanged (no attachment added, existing draft/text preserved).
- **FR-005**: A sent message MUST carry the chosen real attachment (name/size/type); no file bytes are uploaded, downloaded, or stored (metadata only, UI-first phase).
- **FR-006**: The chat card's shared-files view MUST be derived from the chat's persisted message attachments — listing exactly the files sent in that chat, **newest-first** — and MUST NOT show a fabricated/fixed list.
- **FR-007**: A chat with no attachments MUST show the files-view empty state; each chat's files view MUST show only that chat's files.
- **FR-008**: The files view MUST stay current — a newly attached-and-sent file MUST appear without a manual reload (reactive, consistent with the app's existing reactive-refresh behaviour).
- **FR-009**: The file picker MUST be wired and AVAILABLE on all five target platforms (iOS, Android, macOS, Windows, Linux) with the standard native configuration; the attach action is not hidden on any target. A documented, non-crashing fallback MUST exist as a defensive safeguard should a picker fail to present (but no target is expected to lack support).
- **FR-010**: The picker MUST be reachable through a seam that keeps the calling logic testable without a real device dialog (the picker is mockable in tests).
- **FR-011**: Behaviour that is not part of this feature MUST be unchanged — the attachment chip display (size/name/type glyph), send flow, and the deterministic mock seed (which keeps its one seeded attachment) are preserved.
- **FR-012**: No new user-facing golden baseline is required for the native picker (an OS sheet); the existing 5.4 files-view coverage remains valid.

### Key Entities *(include if feature involves data)*

- **Attachment (metadata)**: the file a message carries / a chat shares — an identifier, a display name, a size, and a type (from the fixed file-type set). No file content/bytes are held. Existing shape; this feature populates it from a real chosen file and derives it from persisted messages.
- **Picked file**: the transient result of the native picker — a real name, size, and extension — mapped into an Attachment for the draft. Not persisted as its own entity.
- **Chat shared-files**: the set of attachments across a chat's messages, presented in the 5.4 files view; derived, not separately stored.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of attach actions open the real picker; 0% produce the old fixed `photo.jpg` placeholder.
- **SC-002**: For a chosen file, the draft attachment's name and size match the file exactly, and its type matches the extension mapping, in 100% of cases across the covered extension classes.
- **SC-003**: A cancelled picker changes the composer in 0% of cases.
- **SC-004**: The files view lists exactly the chat's real attachments — 0 fabricated entries and 0 missing sent-attachments — across chats with 0, 1, and several attachments.
- **SC-005**: After attaching+sending a file, it appears in the files view within ~1 second with no manual reload.
- **SC-006**: The app builds and runs on every target platform with the picker wired (verified at least on the locally-buildable platform), with a documented fallback for any platform without picker support — 0 crashes on the attach action.
- **SC-007**: 0 behavioural regressions elsewhere — the pre-existing test suite and golden baselines stay green (the fabricated-list source is the only intentional behaviour change).

## Assumptions

- **Metadata-only, no transfer**: consistent with the UI-first phase, the picker captures only name/size/type; reading, copying, uploading or downloading file bytes is out of scope (backend phase). A picker option that avoids loading file data is preferred so large files do not block the UI.
- **Files-view source swap**: the 5.4 files view derives from the local message store (the chat's persisted attachments). The previous fabricated file source is retired; whether the now-unused remote file-source seam (from the 016 data-layer work) is removed or repurposed is a planning decision, but the files view no longer shows fabricated files.
- **Reactive consistency**: US3 reuses the app's established reactive-refresh pattern (a change-signal over the local cache), not a new mechanism.
- **Native configuration is standard/minimal**: the picker needs the documented per-platform setup (notably the macOS user-selected read-only file-access entitlement); document platform builds that can't be verified locally so they are checked when CI resumes.
- **Fallback**: if a platform lacks picker support, the attach affordance is hidden/disabled with a documented rationale (as the QR scanner does for Windows/Linux) — never a crash.
- **Scope boundaries**: no upload/download, no file preview/thumbnails, no multi-file selection (single file per attachment, as today), no camera capture, no backend/wire changes. The attachment chip's existing display and the send flow are unchanged.
