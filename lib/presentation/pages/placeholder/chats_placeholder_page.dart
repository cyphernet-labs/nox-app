import 'package:flutter/material.dart';
import 'package:nox_app/general/text_constants.dart';

/// Skeleton placeholder for the Chats tab. US2 wires the Chats tab body to the
/// Item verification-harness (ItemListPage); the real chat list is a later feature.
class ChatsPlaceholderPage extends StatelessWidget {
  const ChatsPlaceholderPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(child: Text(TextConstants.chats));
  }
}
