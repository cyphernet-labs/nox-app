import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/data/entity/base/entity_converter.dart';
import 'package:nox_app/data/entity/base/error_wire_entity.dart';

part 'response_entity.freezed.dart';
part 'response_entity.g.dart';

/// Unified data-source envelope over contract v0 replies: success mirrors the
/// wire `ok`, [error] carries the contract `{code, message}` object of a
/// failed reply, and the generic `T?` payload is resolved by EntityConverter.
@freezed
abstract class ResponseEntity<T> with _$ResponseEntity<T> {
  const factory ResponseEntity({@Default(false) bool success, ErrorWireEntity? error, @EntityConverter() T? data}) = _ResponseEntity<T>;

  factory ResponseEntity.fromJson(Map<String, dynamic> json) => _$ResponseEntityFromJson(json);
}
