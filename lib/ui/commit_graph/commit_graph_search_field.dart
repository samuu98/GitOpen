import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/commit_search_provider.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// The commit-graph search field. Owns its text controller and debounce so a
/// keystroke doesn't fire a `git log` per character; an empty field restores
/// the unfiltered graph via [commitSearchProvider].
class CommitGraphSearchField extends ConsumerStatefulWidget {
  const CommitGraphSearchField({super.key});

  @override
  ConsumerState<CommitGraphSearchField> createState() =>
      _CommitGraphSearchFieldState();
}

class _CommitGraphSearchFieldState
    extends ConsumerState<CommitGraphSearchField> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Debounce search input so typing doesn't fire a `git log` per keystroke.
  /// An empty field resolves to [CommitSearch.none], restoring the unfiltered
  /// graph.
  void _onSearchChanged(String raw) {
    // Rebuild now so the clear (x) affordance toggles with the field content;
    // the expensive provider update (which triggers `git log`) is debounced.
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      final parsed = CommitSearch.parse(raw);
      if (ref.read(commitSearchProvider) != parsed) {
        ref.read(commitSearchProvider.notifier).state = parsed;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final hasText = _searchController.text.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: SizedBox(
        height: 30,
        child: TextField(
          controller: _searchController,
          style: TextStyle(color: palette.fg0, fontSize: 12),
          onChanged: _onSearchChanged,
          decoration:
              appInputDecoration(
                context,
                label: 'Search commits',
                hint: 'message · author:name · touches:text',
              ).copyWith(
                prefixIcon: Icon(Icons.search, size: 16, color: palette.fg2),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 30,
                ),
                suffixIcon: hasText
                    ? IconButton(
                        icon: Icon(Icons.close, size: 16, color: palette.fg2),
                        splashRadius: 14,
                        tooltip: 'Clear search',
                        onPressed: () {
                          _searchDebounce?.cancel();
                          _searchController.clear();
                          ref.read(commitSearchProvider.notifier).state =
                              CommitSearch.none;
                          setState(() {});
                        },
                      )
                    : null,
              ),
        ),
      ),
    );
  }
}
