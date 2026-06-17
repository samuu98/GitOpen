import 'package:gitopen/domain/repositories/folder_id.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';

/// What is being dragged in the repo tree.
sealed class DragRef {
  const DragRef();
}

final class RepoDragRef extends DragRef {
  const RepoDragRef(this.id);
  final RepoId id;
}

final class FolderDragRef extends DragRef {
  const FolderDragRef(this.id);
  final FolderId id;
}

/// Where, within a hovered row, a drop will land.
enum DropZone { before, into, after }

/// Which zone a pointer at vertical [fraction] (0 = top, 1 = bottom) hits.
/// Folder rows expose a central [DropZone.into] band (drop *inside* the
/// folder); repo rows split 50/50 into before/after.
DropZone zoneFor({required double fraction, required bool isFolder}) {
  if (!isFolder) return fraction < 0.5 ? DropZone.before : DropZone.after;
  if (fraction < 0.28) return DropZone.before;
  if (fraction > 0.72) return DropZone.after;
  return DropZone.into;
}

/// Index within a parent's child list where a node dropped over
/// [hoveredIndex] should land: before it (top half) or after it (bottom half).
int resolveDropIndex({required int hoveredIndex, required bool isTopHalf}) {
  return isTopHalf ? hoveredIndex : hoveredIndex + 1;
}

/// Adjusts a same-parent target index for the removal of the dragged item:
/// the store removes the moved node before re-inserting, so a target that sat
/// below the moved node shifts left by one.
int adjustForSameParent({required int rawIndex, required int movedIndex}) {
  return movedIndex < rawIndex ? rawIndex - 1 : rawIndex;
}
