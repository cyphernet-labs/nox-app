import 'package:injectable/injectable.dart';
import 'package:nox_app/domain/model/file/attachment_transfer.dart';
import 'package:nox_app/domain/service/attachment_transfer_service.dart';
import 'package:rxdart/rxdart.dart';

/// The transfers in memory. Nothing here is persisted: see [AttachmentTransfer].
@LazySingleton(as: AttachmentTransferService, env: [Environment.dev, Environment.prod, Environment.test])
class AttachmentTransferServiceImpl implements AttachmentTransferService {
  final BehaviorSubject<Map<String, AttachmentTransfer>> _transfers = BehaviorSubject<Map<String, AttachmentTransfer>>.seeded(
    const <String, AttachmentTransfer>{},
  );

  @override
  Map<String, AttachmentTransfer> get current => _transfers.value;

  @override
  Stream<Map<String, AttachmentTransfer>> watch() => _transfers.stream;

  @override
  void begin(String messageId, TransferDirection direction) {
    _publish({...current, messageId: AttachmentTransfer(direction: direction)});
  }

  @override
  void report(String messageId, double fraction) {
    final running = current[messageId];
    // A late progress callback from a transfer that already ended must not
    // bring it back: the ring would come back over a message already sent.
    if (running == null) return;
    final next = running.copyWith(fraction: fraction.clamp(0.0, 1.0).toDouble());
    if (next.percent == running.percent) return;
    _publish({...current, messageId: next});
  }

  @override
  void end(String messageId) {
    if (!current.containsKey(messageId)) return;
    _publish(Map<String, AttachmentTransfer>.of(current)..remove(messageId));
  }

  void _publish(Map<String, AttachmentTransfer> next) => _transfers.add(Map<String, AttachmentTransfer>.unmodifiable(next));
}
