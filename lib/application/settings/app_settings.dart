import 'package:flutter/widgets.dart';
import 'package:equatable/equatable.dart';

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
  final Map<String, LogicalKeySet> keybindings;

  const AppSettingsState({
    this.theme = AppTheme.dark,
    this.externalEditorPath,
    this.defaultPullStrategy = DefaultPullStrategy.merge,
    this.commitSignoffDefault = false,
    this.fontSize = 12,
    this.fontFamily,
    this.githubClientId,
    this.autoUpdateCheck = true,
    this.keybindings = const {},
  });

  AppSettingsState copyWith({
    AppTheme? theme,
    String? externalEditorPath,
    DefaultPullStrategy? defaultPullStrategy,
    bool? commitSignoffDefault,
    int? fontSize,
    String? fontFamily,
    String? githubClientId,
    bool? autoUpdateCheck,
    Map<String, LogicalKeySet>? keybindings,
  }) {
    return AppSettingsState(
      theme: theme ?? this.theme,
      externalEditorPath: externalEditorPath ?? this.externalEditorPath,
      defaultPullStrategy: defaultPullStrategy ?? this.defaultPullStrategy,
      commitSignoffDefault: commitSignoffDefault ?? this.commitSignoffDefault,
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      githubClientId: githubClientId ?? this.githubClientId,
      autoUpdateCheck: autoUpdateCheck ?? this.autoUpdateCheck,
      keybindings: keybindings ?? this.keybindings,
    );
  }

  @override
  List<Object?> get props => [
    theme, externalEditorPath, defaultPullStrategy, commitSignoffDefault,
    fontSize, fontFamily, githubClientId, autoUpdateCheck, keybindings,
  ];
}
