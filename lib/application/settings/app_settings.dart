import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:gitopen/application/auth/auth_resolver.dart' show AuthResolver;
import 'package:gitopen/application/git_identity/git_identity.dart';

enum AppTheme { dark, light }

enum DefaultPullStrategy { ffOnly, merge, rebase }

final class AppSettingsState extends Equatable {
  const AppSettingsState({
    this.theme = AppTheme.dark,
    this.externalEditorPath,
    this.defaultPullStrategy = DefaultPullStrategy.merge,
    this.commitSignoffDefault = false,
    this.gpgSignByDefault = false,
    this.fontSize = 12,
    this.fontFamily,
    this.githubClientId,
    this.autoUpdateCheck = true,
    this.autoRefresh = true,
    this.fileListsAsTree = false,
    this.keybindings = const {},
    this.gitIdentities = const [],
    this.authRepoBindings = const {},
    this.pinnedBranches = const {},
  });
  final AppTheme theme;
  final String? externalEditorPath;
  final DefaultPullStrategy defaultPullStrategy;
  final bool commitSignoffDefault;

  /// When true, the commit compose panel defaults its "Sign (GPG)" toggle on,
  /// so new commits are GPG-signed unless the user turns it off per-commit.
  final bool gpgSignByDefault;
  final int fontSize;
  final String? fontFamily;
  final String? githubClientId;
  final bool autoUpdateCheck;

  /// When true, the open repo is watched for outside changes (`.git`
  /// bookkeeping) and refreshed automatically — plus a refresh whenever the
  /// window regains focus.
  final bool autoRefresh;

  /// When true, the working-copy file list and the commit file list render
  /// as a folder tree instead of flat paths. Shared by both lists.
  final bool fileListsAsTree;
  final Map<String, LogicalKeySet> keybindings;
  final List<GitIdentity> gitIdentities;

  /// Per-repository binding from `RepoLocation.id` → `AuthProfile.id`.
  /// Used so that a workspace with two GitHub accounts on the same host
  /// always uses the right one — overrides the implicit "single profile
  /// per host" fallback in [AuthResolver].
  final Map<String, String> authRepoBindings;

  /// Per-repository pinned (favourite) local branches: `RepoLocation.id` →
  /// list of branch `fullName`s, surfaced in a "PINNED" sidebar section.
  final Map<String, List<String>> pinnedBranches;

  AppSettingsState copyWith({
    AppTheme? theme,
    String? externalEditorPath,
    DefaultPullStrategy? defaultPullStrategy,
    bool? commitSignoffDefault,
    bool? gpgSignByDefault,
    int? fontSize,
    String? fontFamily,
    String? githubClientId,
    bool? autoUpdateCheck,
    bool? autoRefresh,
    bool? fileListsAsTree,
    Map<String, LogicalKeySet>? keybindings,
    List<GitIdentity>? gitIdentities,
    Map<String, String>? authRepoBindings,
    Map<String, List<String>>? pinnedBranches,
  }) {
    return AppSettingsState(
      theme: theme ?? this.theme,
      externalEditorPath: externalEditorPath ?? this.externalEditorPath,
      defaultPullStrategy: defaultPullStrategy ?? this.defaultPullStrategy,
      commitSignoffDefault: commitSignoffDefault ?? this.commitSignoffDefault,
      gpgSignByDefault: gpgSignByDefault ?? this.gpgSignByDefault,
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      githubClientId: githubClientId ?? this.githubClientId,
      autoUpdateCheck: autoUpdateCheck ?? this.autoUpdateCheck,
      autoRefresh: autoRefresh ?? this.autoRefresh,
      fileListsAsTree: fileListsAsTree ?? this.fileListsAsTree,
      keybindings: keybindings ?? this.keybindings,
      gitIdentities: gitIdentities ?? this.gitIdentities,
      authRepoBindings: authRepoBindings ?? this.authRepoBindings,
      pinnedBranches: pinnedBranches ?? this.pinnedBranches,
    );
  }

  @override
  List<Object?> get props => [
    theme,
    externalEditorPath,
    defaultPullStrategy,
    commitSignoffDefault,
    gpgSignByDefault,
    fontSize,
    fontFamily,
    githubClientId,
    autoUpdateCheck,
    autoRefresh,
    fileListsAsTree,
    keybindings,
    gitIdentities,
    authRepoBindings,
    pinnedBranches,
  ];
}
