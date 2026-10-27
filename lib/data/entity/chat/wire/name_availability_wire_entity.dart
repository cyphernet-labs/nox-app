import 'package:freezed_annotation/freezed_annotation.dart';

part 'name_availability_wire_entity.freezed.dart';
part 'name_availability_wire_entity.g.dart';

/// Reply of `chat.nameAvailable` (contract §4): `{available: bool}`.
@freezed
abstract class NameAvailabilityWireEntity with _$NameAvailabilityWireEntity {
  const factory NameAvailabilityWireEntity({@JsonKey(name: 'available') required bool available}) = _NameAvailabilityWireEntity;

  factory NameAvailabilityWireEntity.fromJson(Map<String, dynamic> json) => _$NameAvailabilityWireEntityFromJson(json);
}
