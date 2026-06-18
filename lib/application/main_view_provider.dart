import 'package:flutter_riverpod/legacy.dart';

enum MainView { graph, changes, github, lfs }

final mainViewProvider = StateProvider<MainView>((_) => MainView.graph);
