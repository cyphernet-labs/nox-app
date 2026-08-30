import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:nox_app/data/entity/base/response_entity.dart';
import 'package:nox_app/data/entity/chat/wire/chats_wire_entity.dart';
import 'package:nox_app/data/mapper/chat/chat_wire_mapper.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/general/app_clock.dart';
import 'package:nox_app/general/chat_seed_mock_data.dart';
import 'package:nox_app/domain/repository/chat/get_chats_config.dart';

/// Skeleton MOCK source for the chats list. Synthesizes a deterministic set
/// of chats (varied recency), filters by `config.search` (name), paginates,
/// and returns the contract-shaped `ResponseEntity<ChatsWireEntity>` page
/// `{chats, has_more}` (contract v0 §4). The seed stays model-shaped and is
/// mapped to wire at the boundary; device-local seed state (unread badges)
/// lives in `ChatSeedMockData` and is overlaid by the repository — the wire
/// carries no unread counter (§8.3).
@lazySingleton
class GetChatsApi {
  GetChatsApi(this._wireMapper);

  final ChatWireMapper _wireMapper;

  Future<ResponseEntity<ChatsWireEntity>> execute({required GetChatsConfig config}) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));

    final all = _mockChats();
    final search = config.search?.trim().toLowerCase() ?? '';
    final filtered = search.isEmpty ? all : all.where((c) => c.name.toLowerCase().contains(search)).toList();

    const pageSize = GetChatsConfig.pageSize;
    final start = (config.page - 1) * pageSize;
    final slice = filtered.skip(start).take(pageSize).toList();
    return ResponseEntity<ChatsWireEntity>(
      success: true,
      data: ChatsWireEntity(
        chats: _wireMapper.toListEntity(models: slice),
        hasMore: start + pageSize < filtered.length,
      ),
    );
  }

  /// 28 deterministic chats, newest first. Timestamps are relative to "now" so the
  /// relative-time ladder (now / N min / N h / Yesterday / date) reads consistently.
  /// Unread badges are NOT here - they are device-local (`ChatSeedMockData`).
  List<ChatModel> _mockChats() {
    final now = AppClock.now();
    const seed = <(String, String, Duration)>[
      ('Design crit', 'Aria: pushed the new spacing tokens', Duration(seconds: 20)),
      ('Random thoughts', 'Mox: anyone up for a walk?', Duration(minutes: 5)),
      ('NOX core', 'Kit: merged the shell PR 🎉', Duration(minutes: 18)),
      ('Weekend plans', 'Lee: trailhead at 8?', Duration(hours: 2)),
      ('Bug triage', 'Sam: repro on Android only', Duration(hours: 5)),
      ('Coffee club', 'Dana: new beans arrived', Duration(hours: 9)),
      ('Release 1.0', 'Robin: cutting the branch tonight', Duration(hours: 20)),
      ('Book swap', 'Toni: finished it, your turn', Duration(days: 1, hours: 1)),
      ('Garden', 'Pat: tomatoes are in', Duration(days: 1, hours: 6)),
      ('Music', 'Ezra: added 12 tracks', Duration(days: 2)),
      ('Photography', 'Nico: golden hour shots', Duration(days: 2, hours: 4)),
      ('Run club', 'Quinn: 5k Saturday', Duration(days: 3)),
      ('Recipes', 'Sky: the dough needs more time', Duration(days: 4)),
      ('Board games', 'Val: bring the dice', Duration(days: 5)),
      ('Travel', 'Remy: visas sorted', Duration(days: 6)),
      ('Movies', 'Ari: midnight showing?', Duration(days: 8)),
      ('Hardware', 'Jules: soldering iron died', Duration(days: 11)),
      ('Languages', 'Mika: 30-day streak', Duration(days: 14)),
      ('Climbing', 'Soren: new route at the gym', Duration(days: 19)),
      ('投資', 'Yuki: rebalanced the index', Duration(days: 23)),
      ('Cycling', 'Bo: flat tire again', Duration(days: 27)),
      ('Pottery', 'Wren: kiln is fired', Duration(days: 33)),
      ('Astronomy', 'Cleo: clear skies tonight', Duration(days: 41)),
      ('Chess', 'Idris: rematch?', Duration(days: 52)),
      ('Woodwork', 'Hana: sanded the table', Duration(days: 66)),
      ('History', 'Otto: archive day', Duration(days: 80)),
      ('Gardening 2', 'Pip: seedlings up', Duration(days: 120)),
      ('Archive', 'System: thread created', Duration(days: 400)),
    ];
    return [
      for (final (index, (name, preview, ago)) in seed.indexed)
        ChatModel(
          id: 'chat_$index',
          name: name,
          lastMessagePreview: preview,
          lastMessageAt: now.subtract(ago),
          // Deterministic wire metadata: every seeded chat was "created" a
          // month before its last activity, by the seed persona.
          createdAt: now.subtract(ago + const Duration(days: 30)),
          createdByLabel: ChatSeedMockData.genesisAuthorLabel,
        ),
    ];
  }
}
