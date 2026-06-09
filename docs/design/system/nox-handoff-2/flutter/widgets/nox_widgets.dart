// NOX · widgets — composite list/chat/file widgets.
// Idiomatic Material 3. Hand-written to match src/chats-parts.jsx 1:1.
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'nox_primitives.dart';
import 'nox_tokens.dart';

// ─────────────────────────────────────────────────────────────
// NoxSearchBar — persistent search field (5.1). Brand-teal search
// icon. surfaceContainerHigh, stadium, elevation 2.
// Source: src/chats-parts.jsx <SearchBar>.
// ─────────────────────────────────────────────────────────────
class NoxSearchBar extends StatelessWidget {
  const NoxSearchBar({super.key, this.value, this.hint = 'Search', this.onTap});
  final String? value;
  final String hint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final hasValue = value != null && value!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          NoxSpacing.s4, 0, NoxSpacing.s4, NoxSpacing.s2),
      child: Material(
        color: cs.surfaceContainerHigh,
        elevation: NoxElevation.level2,
        shadowColor: cs.shadow,
        borderRadius: BorderRadius.circular(NoxRadius.full),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(NoxRadius.full),
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: NoxSpacing.s4),
            child: Row(
              children: [
                // brand-teal icon is intentional (NOX accent), not a theme role
                Icon(Symbols.search, size: 24, color: const Color(0xFF12B4B4)),
                const SizedBox(width: NoxSpacing.s3),
                Text(
                  hasValue ? value! : hint,
                  style: tt.bodyLarge?.copyWith(
                    color: hasValue ? cs.onSurface : cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// NoxChatListItem — chat row (5.1 §9.3). Avatar ring + unread
// emphasis (name/preview bolder, badge, primary-tinted time).
// Source: src/chats-parts.jsx <ChatListItem>.
// ─────────────────────────────────────────────────────────────
class NoxChatListItem extends StatelessWidget {
  const NoxChatListItem({
    super.key,
    required this.name,
    required this.preview,
    required this.time,
    this.unread = 0,
    this.onTap,
  });

  final String name;
  final String preview;
  final String time;
  final int unread;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final hasUnread = unread > 0;
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 72),
        padding: const EdgeInsets.symmetric(
            horizontal: NoxSpacing.s4, vertical: NoxSpacing.s3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // subtle avatar ring
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: cs.onSurface.withValues(alpha: 0.06),
                      spreadRadius: 2),
                ],
              ),
              child: NoxAvatar(name: name, size: 40),
            ),
            const SizedBox(width: NoxSpacing.s4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.titleMedium?.copyWith(
                      color: cs.onSurface,
                      fontWeight:
                          hasUnread ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodyMedium?.copyWith(
                      color: hasUnread ? cs.onSurface : cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: NoxSpacing.s2),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  time,
                  style: tt.labelSmall?.copyWith(
                    color: hasUnread ? cs.primary : cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: NoxSpacing.s1 + 2),
                if (hasUnread)
                  Container(
                    constraints: const BoxConstraints(minWidth: 20),
                    height: 20,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(NoxRadius.full),
                    ),
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      style: tt.labelSmall?.copyWith(color: cs.onPrimary),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// File-chip (§9.7). inBubble → tint derived from the bubble text
// color (onColor); standalone → surfaceContainerHighest.
// Source: src/chats-parts.jsx <FileChip>.
// ─────────────────────────────────────────────────────────────
class NoxFileChip extends StatelessWidget {
  const NoxFileChip({
    super.key,
    required this.type,
    required this.name,
    required this.size,
    this.inBubble = false,
    this.onColor,
    this.removable = false,
    this.onRemove,
  });

  final NoxFileType type;
  final String name;
  final String size; // pre-formatted, e.g. "2.4 MB"
  final bool inBubble;
  final Color? onColor; // bubble text color when inBubble
  final bool removable;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final oc = onColor ?? cs.onPrimaryContainer;
    final bg = inBubble ? oc.withValues(alpha: 0.12) : cs.surfaceContainerHighest;
    final fg = inBubble ? oc : cs.onSurface;
    final sub = inBubble ? oc.withValues(alpha: 0.7) : cs.onSurfaceVariant;
    return Container(
      constraints: const BoxConstraints(minWidth: 200, maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(NoxRadius.xs),
      ),
      child: Row(
        children: [
          NoxIcon(noxFileIcon(type), size: 28, color: sub),
          const SizedBox(width: NoxSpacing.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.titleMedium?.copyWith(color: fg)),
                Text(size, style: tt.bodyMedium?.copyWith(color: sub)),
              ],
            ),
          ),
          if (removable)
            SizedBox(
              width: 32,
              height: 32,
              child: IconButton(
                padding: EdgeInsets.zero,
                onPressed: onRemove,
                icon: NoxIcon(Symbols.close, size: 20, color: cs.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Message bubble (5.2 §9.2). Base radius l(16); the own
// bottom-right / other bottom-left corner clips to xs(4).
// Own = primaryContainer; other = surfaceContainerHigh.
// Status (own only): pending schedule · sent check · error error.
// Source: src/chats-parts.jsx <MsgBubble>.
// ─────────────────────────────────────────────────────────────
enum NoxMsgStatus { none, pending, sent, error }

class NoxMessageBubble extends StatelessWidget {
  const NoxMessageBubble({
    super.key,
    required this.isOwn,
    this.text,
    required this.time,
    this.status = NoxMsgStatus.none,
    this.file, // an optional NoxFileChip rendered inside
    this.isLast = false,
  });

  final bool isOwn;
  final String? text;
  final String time;
  final NoxMsgStatus status;
  final Widget? file;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final bg = isOwn ? cs.primaryContainer : cs.surfaceContainerHigh;
    final fg = isOwn ? cs.onPrimaryContainer : cs.onSurface;
    final meta = isOwn
        ? cs.onPrimaryContainer.withValues(alpha: 0.7)
        : cs.onSurfaceVariant;
    final statusColor = status == NoxMsgStatus.error ? cs.error : meta;
    final hasFileOnly = file != null && (text == null || text!.isEmpty);

    return Align(
      alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(bottom: isLast ? 0 : 2),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.8,
        ),
        padding: hasFileOnly
            ? const EdgeInsets.all(8)
            : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: NoxRadius.bubble(isOwn: isOwn),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (file != null)
              Padding(
                padding: EdgeInsets.only(
                    bottom: (text != null && text!.isNotEmpty) ? 8 : 0),
                child: file!,
              ),
            if (text != null && text!.isNotEmpty)
              Text(text!, style: tt.bodyLarge?.copyWith(color: fg)),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(time, style: tt.labelSmall?.copyWith(color: meta)),
                if (isOwn && status != NoxMsgStatus.none) ...[
                  const SizedBox(width: 4),
                  NoxIcon(
                    status == NoxMsgStatus.pending
                        ? Symbols.schedule
                        : status == NoxMsgStatus.sent
                            ? Symbols.check
                            : Symbols.error,
                    size: 14,
                    color: statusColor,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Composer (5.2 §9.8). surfaceContainer, top divider, optional
// attachment chip above. Send active → primary (fill 1), else 38%.
// Source: src/chats-parts.jsx <Composer>.
// ─────────────────────────────────────────────────────────────
class NoxComposer extends StatelessWidget {
  const NoxComposer({
    super.key,
    this.value,
    this.attachment, // a NoxFileChip(removable: true)
    this.sendActive = false,
    this.onAttach,
    this.onSend,
  });

  final String? value;
  final Widget? attachment;
  final bool sendActive;
  final VoidCallback? onAttach;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final hasValue = value != null && value!.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (attachment != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Align(alignment: Alignment.centerLeft, child: attachment),
            ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: onAttach,
                  icon: NoxIcon(Symbols.attach_file,
                      size: 24, color: cs.onSurfaceVariant),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 12),
                    child: Text(
                      hasValue ? value! : 'Message',
                      style: tt.bodyLarge?.copyWith(
                        color: hasValue ? cs.onSurface : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: sendActive ? onSend : null,
                  icon: NoxIcon(
                    Symbols.send,
                    size: 24,
                    fill: sendActive ? 1 : 0,
                    color: sendActive
                        ? cs.primary
                        : cs.onSurface.withValues(alpha: 0.38),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// NoxEmptyState — illustration placeholder + title + message.
// Replace the placeholder box with a real SVG once illustrations
// ship (nox-assets/illustrations).
// Source: src/chats-parts.jsx <EmptyState>.
// ─────────────────────────────────────────────────────────────
class NoxEmptyState extends StatelessWidget {
  const NoxEmptyState({
    super.key,
    required this.glyph,
    required this.title,
    required this.message,
  });

  final IconData glyph;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // illustration placeholder — thin outline + brand accents (§10)
            Container(
              width: 132,
              height: 132,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: cs.outlineVariant, width: 1.5),
              ),
              child: NoxIcon(glyph, size: 56, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: tt.headlineSmall?.copyWith(color: cs.onSurface)),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Segmented control — single-select. Use the stock M3
// SegmentedButton; the theme (nox_theme.dart) sets the selected
// secondaryContainer fill + shape. Helper for the common case.
// Source: src/chats-parts.jsx <Segmented>.
// ─────────────────────────────────────────────────────────────
class NoxSegmented<T> extends StatelessWidget {
  const NoxSegmented({
    super.key,
    required this.options, // {value: label}
    required this.selected,
    required this.onChanged,
  });

  final Map<T, String> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<T>(
      segments: [
        for (final e in options.entries)
          ButtonSegment<T>(value: e.key, label: Text(e.value)),
      ],
      selected: {selected},
      showSelectedIcon: true,
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}
