import 'package:flutter/material.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/gen/assets.gen.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/presentation/helpers/app_feedback_helper.dart';
import 'package:nox_app/presentation/widgets/chat/app_chat_item_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_composer_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_file_chip_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_message_bubble_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_search_bar_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_segmented_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_avatar_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_file_glyph_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_spinner_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/file_type.dart';
import 'package:nox_app/presentation/widgets/shell/app_bottom_bar_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_create_fab_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_splash_hairline_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_wordmark_widget.dart';
import 'package:nox_app/presentation/widgets/state/app_empty_content_widget.dart';
import 'package:nox_app/presentation/widgets/state/app_error_widget.dart';
import 'package:nox_app/presentation/widgets/state/app_progress_widget.dart';

/// Dev-only catalog of every UI-kit widget in the current theme. Not part of the
/// product app — reached only via `lib/main_gallery.dart`. Toggle the app-bar
/// action to switch light/dark.
class GalleryPage extends StatelessWidget {
  const GalleryPage({super.key, required this.onToggleTheme, required this.isDark});

  final VoidCallback onToggleTheme;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const AppWordmarkWidget(),
        bottom: const AppSplashHairlineWidget(),
        actions: [
          IconButton(
            tooltip: 'Toggle theme',
            onPressed: onToggleTheme,
            icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.all(AppSpacingTokens.s16),
        children: [
          _section('Primitives', [
            Row(
              children: [
                AppIconWidget(NoxIcons.forum),
                SizedBox(width: AppSpacingTokens.s12),
                AppIconWidget(NoxIcons.forumFill),
                SizedBox(width: AppSpacingTokens.s12),
                AppIconWidget(NoxIcons.search, size: 32),
                SizedBox(width: AppSpacingTokens.s16),
                const AppSpinnerWidget(),
              ],
            ),
            SizedBox(height: AppSpacingTokens.s12),
            Row(
              children: [
                const AppAvatarWidget(name: 'Ann Lee'),
                SizedBox(width: AppSpacingTokens.s12),
                const AppAvatarWidget(name: '   '),
                SizedBox(width: AppSpacingTokens.s16),
                const AppFileGlyphWidget(type: FileType.pdf),
                SizedBox(width: AppSpacingTokens.s12),
                const AppFileGlyphWidget(type: FileType.image),
              ],
            ),
          ]),
          _section('Chat & messaging', [
            const AppSearchBarWidget(),
            SizedBox(height: AppSpacingTokens.s8),
            const AppChatItemWidget(name: 'Cyphernet Labs', preview: 'Build is green', time: '09:24'),
            const AppChatItemWidget(name: 'Ann Lee', preview: 'See you tomorrow', time: '08:10', unread: 5),
            const AppChatItemWidget(name: 'Releases', preview: 'v26.1 shipped', time: 'Mon', unread: 120),
            SizedBox(height: AppSpacingTokens.s8),
            const AppFileChipWidget(type: FileType.archive, name: 'logs.zip', size: '512 KB', removable: true),
            SizedBox(height: AppSpacingTokens.s8),
            const AppMessageBubbleWidget(isOwn: true, text: 'Sent this', time: '09:00', status: MessageStatus.sent),
            const AppMessageBubbleWidget(isOwn: false, text: 'Got it!', time: '09:01'),
            SizedBox(height: AppSpacingTokens.s8),
            AppSegmentedWidget<int>(options: const {0: 'System', 1: 'Light', 2: 'Dark'}, selected: isDark ? 2 : 1, onChanged: (_) {}),
            SizedBox(height: AppSpacingTokens.s8),
            const AppComposerWidget(value: 'Draft message', sendActive: true),
          ]),
          _section('State', [
            SizedBox(height: AppSpacingTokens.s32, child: const AppProgressWidget()),
            SizedBox(height: AppSpacingTokens.s16),
            AppErrorWidget(message: 'Could not load chats', onTryAgain: () {}),
            SizedBox(height: AppSpacingTokens.s16),
            SizedBox(
              height: 280,
              child: AppEmptyContentWidget(
                illustration: Assets.svg.illustrations.emptyChats,
                title: 'No chats yet',
                message: 'Create the first chat to get the conversation going.',
              ),
            ),
          ]),
          _section('Feedback & stock', [
            Wrap(
              spacing: AppSpacingTokens.s12,
              runSpacing: AppSpacingTokens.s8,
              children: [
                FilledButton(onPressed: () {}, child: const Text('Filled')),
                TextButton(onPressed: () {}, child: const Text('Text')),
                Builder(
                  builder: (context) => FilledButton(
                    onPressed: () => showAppSnackBar(context, text: 'Saved', actionLabel: 'Undo'),
                    child: const Text('SnackBar'),
                  ),
                ),
                Builder(
                  builder: (context) => FilledButton(
                    onPressed: () => showAppBanner(context, text: 'No connection'),
                    child: const Text('Banner'),
                  ),
                ),
              ],
            ),
          ]),
        ],
      ),
      bottomNavigationBar: AppBottomBarWidget(active: AppTab.chats, onSelect: (_) {}),
      floatingActionButton: const AppCreateFabWidget(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Builder(
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacingTokens.s16),
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          ...children,
          SizedBox(height: AppSpacingTokens.s16),
        ],
      ),
    );
  }
}
