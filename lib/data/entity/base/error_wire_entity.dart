import 'package:freezed_annotation/freezed_annotation.dart';

part 'error_wire_entity.freezed.dart';
part 'error_wire_entity.g.dart';

/// Wire error object of contract v0 §2: `{"code": "...", "message": "..."}`.
/// The code is one of §2.1; an unknown code maps to `internal` downstream
/// (RepositoryException.fromWireCode) per the evolution rule.
@freezed
abstract class ErrorWireEntity with _$ErrorWireEntity {
  const factory ErrorWireEntity({required String code, required String message}) = _ErrorWireEntity;

  factory ErrorWireEntity.fromJson(Map<String, dynamic> json) => _$ErrorWireEntityFromJson(json);
}
