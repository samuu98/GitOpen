import 'package:flutter_riverpod/flutter_riverpod.dart';

enum MainView { graph, changes, github }

final mainViewProvider = StateProvider<MainView>((_) => MainView.graph);
