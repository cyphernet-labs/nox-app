import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/domain/model/item/item_model.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/presentation/pages/item_list_page/bloc/item_list_bloc.dart';

/// Scaffold-DEMO verification harness on MOCK data (NOT a product feature — FR-013).
/// Proves the layered vertical (page → BLoC → repository) compiles end-to-end.
/// Not currently mounted: the app starts at `SplashPage` (the app-state spine); this
/// and AppShell are kept as the Feature-001 skeleton until real chat features land.
class ItemListPage extends StatefulWidget {
  const ItemListPage({super.key});

  @override
  State<ItemListPage> createState() => _ItemListPageState();
}

class _ItemListPageState extends State<ItemListPage> {
  late final ItemListBloc _bloc;

  @override
  void initState() {
    super.initState();
    _bloc = ItemListBloc()..add(const ItemListEvent.initialize());
  }

  @override
  void dispose() {
    _bloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ItemListBloc>.value(
      value: _bloc,
      child: BlocBuilder<ItemListBloc, ItemListState>(
        builder: (context, state) {
          return switch (state) {
            Initializing() => const Center(child: CircularProgressIndicator()),
            Error() => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(context.l10n.errorGeneralTitle),
                  TextButton(onPressed: () => _bloc.add(const ItemListEvent.initialize()), child: Text(context.l10n.actionTryAgain)),
                ],
              ),
            ),
            Initialized() => PagedListView<String, ItemModel>.separated(
              state: state.pagingState,
              fetchNextPage: () => _bloc.add(const ItemListEvent.loadItems()),
              builderDelegate: PagedChildBuilderDelegate<ItemModel>(
                itemBuilder: (context, item, index) => ListTile(key: ValueKey(item.id), title: Text(item.name), subtitle: Text(item.id)),
                firstPageProgressIndicatorBuilder: (_) => const Center(child: CircularProgressIndicator()),
                newPageProgressIndicatorBuilder: (_) => const Center(child: CircularProgressIndicator()),
                noItemsFoundIndicatorBuilder: (_) => Center(child: Text(context.l10n.noData)),
              ),
              separatorBuilder: (context, index) => Divider(height: AppDimensionTokens.border.hairline),
            ),
          };
        },
      ),
    );
  }
}
