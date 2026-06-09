import 'package:freezed_annotation/freezed_annotation.dart';

bool _isType<E, T>() => <E>[] is List<T>;

/// Maintained-by-hand registry: resolves the generic `T` of `ResponseEntity<T>`
/// to a concrete entity fromJson/toJson. Every entity reachable via
/// `ResponseEntity<T>` MUST be registered in BOTH chains.
/// Skeleton: empty registry — feature entities (ItemEntity / ItemsEntity) are
/// registered with their feature (see US2).
class EntityConverter<E> implements JsonConverter<E?, dynamic> {
  const EntityConverter();

  @override
  E? fromJson(dynamic json) {
    if (json == null) return null;
    if ((json is bool && _isType<E, bool>()) || _isType<E, bool?>()) {
      return json as E;
    }
    if (json is Map<String, dynamic>) {
      // Entity branches registered per feature (see US2: ItemEntity / ItemsEntity).
    }
    throw ArgumentError('No converter found for type $E');
  }

  @override
  dynamic toJson(E? object) {
    if (object == null) return null;
    // Entity branches registered per feature (see US2).
    throw ArgumentError('No converter found for type $E');
  }
}
