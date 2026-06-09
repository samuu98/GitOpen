import 'package:file_selector/file_selector.dart';
import 'package:gitopen/application/launcher/folder_picker.dart';

/// [FolderPicker] over the `file_selector` platform plugin.
class SystemFolderPicker implements FolderPicker {
  const SystemFolderPicker();

  @override
  Future<String?> pickFolder(String title) async {
    final path = await getDirectoryPath(
        confirmButtonText: 'Open');
    return path;
  }
}
