import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/general/app_clock.dart';
import 'package:nox_app/domain/repository/base/page_metadata.dart';
import 'package:nox_app/domain/repository/chat/get_chats_config.dart';

/// Skeleton MOCK source for the chats list (no real backend — UI phase). Synthesizes
/// a deterministic set of chats (varied recency + unread counts incl. a 99+ cap and
/// several with no badge), filters by `config.search` (name), and paginates. The real
/// impl wraps a Dio request (path `v1/chats`, query `page`/`page_size`/`search`) —
/// example/TBD until the NOX backend is chosen. `// TODO(backend):`.
@lazySingleton
class GetChatsApi {
  Future<(List<ChatModel>, PageMetadata)> execute({required GetChatsConfig config}) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));

    final all = _mockChats();
    final search = config.search?.trim().toLowerCase() ?? '';
    final filtered = search.isEmpty ? all : all.where((c) => c.name.toLowerCase().contains(search)).toList();

    const pageSize = GetChatsConfig.pageSize;
    final start = (config.page - 1) * pageSize;
    final slice = filtered.skip(start).take(pageSize).toList();
    final hasMore = start + pageSize < filtered.length;
    return (slice, PageMetadata(total: filtered.length, nextPage: hasMore ? config.page + 1 : null));
  }

  /// 28 deterministic chats, newest first. Timestamps are relative to "now" so the
  /// relative-time ladder (now / N min / N h / Yesterday / date) reads consistently.
  List<ChatModel> _mockChats() {
    final now = AppClock.now();
    const seed = <(String, String, Duration, int)>[
      ('Design crit', 'Aria: pushed the new spacing tokens', Duration(seconds: 20), 3),
      ('Random thoughts', 'Mox: anyone up for a walk?', Duration(minutes: 5), 0),
      ('NOX core', 'Kit: merged the shell PR 🎉', Duration(minutes: 18), 12),
      ('Weekend plans', 'Lee: trailhead at 8?', Duration(hours: 2), 0),
      ('Bug triage', 'Sam: repro on Android only', Duration(hours: 5), 142),
      ('Coffee club', 'Dana: new beans arrived', Duration(hours: 9), 0),
      ('Release 1.0', 'Robin: cutting the branch tonight', Duration(hours: 20), 1),
      ('Book swap', 'Toni: finished it, your turn', Duration(days: 1, hours: 1), 0),
      ('Garden', 'Pat: tomatoes are in', Duration(days: 1, hours: 6), 4),
      ('Music', 'Ezra: added 12 tracks', Duration(days: 2), 0),
      ('Photography', 'Nico: golden hour shots', Duration(days: 2, hours: 4), 0),
      ('Run club', 'Quinn: 5k Saturday', Duration(days: 3), 2),
      ('Recipes', 'Sky: the dough needs more time', Duration(days: 4), 0),
      ('Board games', 'Val: bring the dice', Duration(days: 5), 0),
      ('Travel', 'Remy: visas sorted', Duration(days: 6), 7),
      ('Movies', 'Ari: midnight showing?', Duration(days: 8), 0),
      ('Hardware', 'Jules: soldering iron died', Duration(days: 11), 0),
      ('Languages', 'Mika: 30-day streak', Duration(days: 14), 1),
      ('Climbing', 'Soren: new route at the gym', Duration(days: 19), 0),
      ('投資', 'Yuki: rebalanced the index', Duration(days: 23), 0),
      ('Cycling', 'Bo: flat tire again', Duration(days: 27), 0),
      ('Pottery', 'Wren: kiln is fired', Duration(days: 33), 0),
      ('Astronomy', 'Cleo: clear skies tonight', Duration(days: 41), 0),
      ('Chess', 'Idris: rematch?', Duration(days: 52), 0),
      ('Woodwork', 'Hana: sanded the table', Duration(days: 66), 0),
      ('History', 'Otto: archive day', Duration(days: 80), 0),
      ('Gardening 2', 'Pip: seedlings up', Duration(days: 120), 0),
      ('Archive', 'System: thread created', Duration(days: 400), 0),
    ];
    return [
      for (final (index, (name, preview, ago, unread)) in seed.indexed)
        ChatModel(id: 'chat_$index', name: name, lastMessagePreview: preview, lastMessageAt: now.subtract(ago), unreadCount: unread),
    ];
  }
}
