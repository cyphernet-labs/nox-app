/// Item status — a rich domain enum. On the JSON boundary it is encoded as
/// `.name` String; all coercion happens in the mapper (data layer).
enum ItemStatus { draft, active, archived }
