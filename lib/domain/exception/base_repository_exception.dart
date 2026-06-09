/// Marker for every domain-level repository error. `RepositoryResult.error`
/// carries a subtype of this — never a raw Exception or framework error.
abstract class BaseRepositoryException {}
