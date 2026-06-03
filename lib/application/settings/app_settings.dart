import 'package:flutter/widgets.dart';
import 'package:equatable/equatable.dart';
import '../git_identity/git_identity.dart';

enum AppTheme { dark, light }
enum DefaultPullStrategy { ffOnly, merge, rebase }

final class AppSettingsState extends Equatable {
  final AppTheme theme;
  final String? externalEditorPath;
  final DefaultPullStrategy defaultPullStrategy;
  final bool commitSignoffDefault;
  final int fontSize;
  final String? fontFamily;
  final String? githubClientId;
  final bool autoUpdateCheck;

  /// Periodically fetch the active repository in the background. Off by
  /// default — the user opts in explicitly.
  final bool autoFetchEnabled;

  /// Interval, in minutes, between background fetches when [autoFetchEnabled].
  final int autoFetchIntervalMinutes;

  final double sidebarWidth;
  final double bottomPanelHeight;

  /// Pinned (favourite) branch `fullName`s per repository id.
  final Map<String, List<String>> pinnedBranches;

  /// Sidebar section titles the user has collapsed (persisted across sessions).
  final Set<String> collapsedSections;

  final Map<String, LogicalKeySet> keybindings;
  final List<GitIdentity> gitIdentities;

  /// Per-repository binding from `RepoLocation.id` → `AuthProfile.id`.
  /// Used so that a workspace with two GitHub accounts on the same host
  /// always uses the right one — overrides the implicit "single profile
  /// per host" fallback in [AuthResolver].
  final Map<String, String> authRepoBindings;

  const AppSettingsState({
    this.theme = AppTheme.dark,
    this.externalEditorPath,
    this.defaultPullStrategy = DefaultPullStrategy.merge,
    this.commitSignoffDefault = false,
    this.fontSize = 12,
    this.fontFamily,
    this.githubClientId,
    this.autoUpdateCheck = true,
    this.autoFetchEnabled = false,
    this.autoFetchIntervalMinutes = 10,
    this.sidebarWidth = 260,
    this.bottomPanelHeight = 320,
    this.pinnedBranches = const {},
    this.collapsedSections = const {},
    this.keybindings = const {},
    this.gitIdentities = const [],
    this.authRepoBindings = const {},
  });

  /// Sentinel distinguishing "argument omitted" from "explicitly set to null"
  /// for the nullable fields below.  Without it, `copyWith(field: null)` is
  /// indistinguishable from not passing the field, so clearing (e.g. removing
  /// the configured external editor) would silently keep the old value.
  static const Object _unset = Object();

  AppSettingsState copyWith({
    AppTheme? theme,
    Object? externalEditorPath = _unset,
    DefaultPullStrategy? defaultPullStrategy,
    bool? commitSignoffDefault,
    int? fontSize,
    Object? fontFamily = _unset,
    Object? githubClientId = _unset,
    bool? autoUpdateCheck,
    bool? autoFetchEnabled,
    int? autoFetchIntervalMinutes,
    double? sidebarWidth,
    double? bottomPanelHeight,
    Map<String, List<String>>? pinnedBranches,
    Set<String>? collapsedSections,
    Map<String, LogicalKeySet>? keybindings,
    List<GitIdentity>? gitIdentities,
    Map<String, String>? authRepoBindings,
  }) {
    return AppSettingsState(
      theme: theme ?? this.theme,
      externalEditorPath: identical(externalEditorPath, _unset)
          ? this.externalEditorPath
          : externalEditorPath as String?,
      defaultPullStrategy: defaultPullStrategy ?? this.defaultPullStrategy,
      commitSignoffDefault: commitSignoffDefault ?? this.commitSignoffDefault,
      fontSize: fontSize ?? this.fontSize,
      fontFamily: identical(fontFamily, _unset)
          ? this.fontFamily
          : fontFamily as String?,
      githubClientId: identical(githubClientId, _unset)
          ? this.githubClientId
          : githubClientId as String?,
      autoUpdateCheck: autoUpdateCheck ?? this.autoUpdateCheck,
      autoFetchEnabled: autoFetchEnabled ?? this.autoFetchEnabled,
      autoFetchIntervalMinutes:
          autoFetchIntervalMinutes ?? this.autoFetchIntervalMinutes,
      sidebarWidth: sidebarWidth ?? this.sidebarWidth,
      bottomPanelHeight: bottomPanelHeight ?? this.bottomPanelHeight,
      pinnedBranches: pinnedBranches ?? this.pinnedBranches,
      collapsedSections: collapsedSections ?? this.collapsedSections,
      keybindings: keybindings ?? this.keybindings,
      gitIdentities: gitIdentities ?? this.gitIdentities,
      authRepoBindings: authRepoBindings ?? this.authRepoBindings,
    );
  }

  @override
  List<Object?> get props => [
    theme, externalEditorPath, defaultPullStrategy, commitSignoffDefault,
    fontSize, fontFamily, githubClientId, autoUpdateCheck,
    autoFetchEnabled, autoFetchIntervalMinutes, sidebarWidth,
    bottomPanelHeight, pinnedBranches, collapsedSections, keybindings,
    gitIdentities, authRepoBindings,
  ];
}
