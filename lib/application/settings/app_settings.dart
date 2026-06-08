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
    this.keybindings = const {},
    this.gitIdentities = const [],
    this.authRepoBindings = const {},
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
  final Map<String, LogicalKeySet> keybindings;
  final List<GitIdentity> gitIdentities;

  /// Per-repository binding from `RepoLocation.id` → `AuthProfile.id`.
  /// Used so that a workspace with two GitHub accounts on the same host
  /// always uses the right one — overrides the implicit "single profile
  /// per host" fallback in [AuthResolver].
  final Map<String, String> authRepoBindings;

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
    Map<String, LogicalKeySet>? keybindings,
    List<GitIdentity>? gitIdentities,
    Map<String, String>? authRepoBindings,
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
      keybindings: keybindings ?? this.keybindings,
      gitIdentities: gitIdentities ?? this.gitIdentities,
      authRepoBindings: authRepoBindings ?? this.authRepoBindings,
    );
  }

  @override
  List<Object?> get props => [
    theme, externalEditorPath, defaultPullStrategy, commitSignoffDefault,
    gpgSignByDefault, fontSize, fontFamily, githubClientId, autoUpdateCheck,
    keybindings, gitIdentities, authRepoBindings,
  ];
}
