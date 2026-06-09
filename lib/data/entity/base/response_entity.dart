import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/data/entity/base/entity_converter.dart';

part 'response_entity.freezed.dart';
part 'response_entity.g.dart';

/// Unified backend envelope (example — backend/protocol not chosen; replace with
/// the real contract). The load-bearing mechanism is the generic `T?` resolved
/// by EntityConverter.
@freezed
abstract class ResponseEntity<T> with _$ResponseEntity<T> {
  const factory ResponseEntity({@Default(false) bool success, String? error, @EntityConverter() T? data}) = _ResponseEntity<T>;

  factory ResponseEntity.fromJson(Map<String, dynamic> json) => _$ResponseEntityFromJson(json);
}
