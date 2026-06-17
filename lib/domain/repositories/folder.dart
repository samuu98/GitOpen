import 'package:equatable/equatable.dart';
import 'package:gitopen/domain/repositories/folder_id.dart';

final class Folder extends Equatable {
  const Folder({
    required this.id,
    required this.name,
    required this.parentId,
    required this.sortOrder,
    required this.collapsed,
  });

  final FolderId id;
  final String name;
  final FolderId? parentId;
  final int sortOrder;
  final bool collapsed;

  Folder copyWith({
    String? name,
    FolderId? parentId,
    bool clearParent = false,
    int? sortOrder,
    bool? collapsed,
  }) {
    return Folder(
      id: id,
      name: name ?? this.name,
      parentId: clearParent ? null : (parentId ?? this.parentId),
      sortOrder: sortOrder ?? this.sortOrder,
      collapsed: collapsed ?? this.collapsed,
    );
  }

  @override
  List<Object?> get props => [id, name, parentId, sortOrder, collapsed];
}
