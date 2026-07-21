# Contract: DI binding + the flip recipe

## Binding (this phase)

Each mock data source is registered against its interface for every environment the system uses:

```dart
@LazySingleton(as: ChatRemoteDataSource, env: [Environment.dev, Environment.prod, Environment.test])
class MockChatRemoteDataSource implements ChatRemoteDataSource { ... }
```

- The generators (`GetChatsApi`, …) keep plain `@lazySingleton` and are injected into the mock data sources.
- Repositories resolve the **interface** through get_it; they never name a concrete data source.
- `build_runner` regenerates `lib/di/configure_dependencies.config.dart`; the generated graph wires each repo to the mock impl via the interface.

### Why all three environments (not `[dev, test]`)

`lib/main.dart`: `env = flavor == AppFlavorType.prod ? Environment.prod : Environment.dev`. The prod flavor boots `Environment.prod`, so a `prod`-scoped binding must exist. With no real impl, the mock occupies `prod` too (FR-007). Scoping the mock to `[dev, test]` now would fail DI on a prod build.

## The flip recipe (≤3 localized steps — SC-006)

To route one feature to a real backend later:

1. **Add** `RealChatRemoteDataSource implements ChatRemoteDataSource` (real HTTP) annotated `@LazySingleton(as: ChatRemoteDataSource, env: [Environment.prod])`.
2. **Scope** the mock away from prod: change `MockChatRemoteDataSource`'s env to `[Environment.dev, Environment.test]`.
3. **Regenerate** DI (`make generate`).

Untouched by the flip: the repository, its cache/DAO/mapper, `RepositoryResult`/`PageMetadata`, the error mapping, and all UI/BLoC. Same recipe per feature.

## Seam verification (SC-002) — rebinding test

Prove the repository is decoupled from the concrete mock without a real backend:

```dart
// register a fake interface impl, then assert the repo routes through it
getIt.allowReassignment = true;
getIt.registerSingleton<ChatRemoteDataSource>(_FakeChatRemoteDataSource(sentinelPage));
final chats = (await getIt<ChatRepository>().getChats(config: GetChatsConfig.firstPage())).data!;
expect(chats.$1.first.name, 'SENTINEL'); // repo used the rebound interface, not MockChatRemoteDataSource
```

Because `ChatRepositoryImpl` depends only on `ChatRemoteDataSource`, swapping the binding swaps the source with zero repo edits — exactly what the production flip does.
