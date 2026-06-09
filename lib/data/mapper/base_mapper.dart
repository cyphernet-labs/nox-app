/// Base entity<->model mapper. Concrete mappers put all primitive<->rich-type
/// coercion (enum.name, DateTime<->ISO) in their toModel/toEntity overrides.
abstract class BaseMapper<E, M, AdResult, AdParam> {
  M toModel({required E entity, AdResult Function(AdParam entity)? ad});

  E toEntity({required M model, AdResult Function(AdParam entity)? ad});

  List<M> toListModel({required List<E> entities, AdResult Function(AdParam entity)? ad}) {
    if (ad == null) {
      return List.from(entities.map((e) => toModel(entity: e)));
    } else {
      return List.from(entities.map((e) => toModel(entity: e, ad: ad)));
    }
  }

  List<E> toListEntity({required List<M> models, AdResult Function(AdParam entity)? ad}) {
    if (ad == null) {
      return List.from(models.map((e) => toEntity(model: e)));
    } else {
      return List.from(models.map((e) => toEntity(model: e, ad: ad)));
    }
  }
}
