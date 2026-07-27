import 'package:gitopen/domain/diff/file_diff.dart';

/// How many diff lines a multi-file diff may render up front.
///
/// `kDiffLineCap` already bounds each *file* at 2 000 lines, but nothing
/// bounded the whole view: a commit touching 200 files could ask the renderer
/// for 400 000 line widgets in a single frame — every one of them built and
/// laid out eagerly, because the file list is a `SingleChildScrollView` with
/// no laziness (it has to be, so "reveal this file" can scroll to an
/// off-screen target). The app froze for seconds and looked hung.
///
/// Matching the per-file cap keeps the worst case for a many-file commit the
/// same as the worst case for one huge file, which is a size the view is
/// already known to handle.
const int kDiffRenderLineBudget = 2000;

/// Upper bound on files expanded up front, independent of the line budget.
/// Guards the shape the budget cannot see: a commit of hundreds of one-line
/// changes (or of binaries, which report zero hunk lines but still decode an
/// image each).
const int kDiffRenderFileCap = 25;

/// Cost charged for a binary file, which has no hunk lines but still renders
/// an image preview or a placeholder.
const int kBinaryFileRenderCost = 100;

/// Paths of the files a multi-file diff should render expanded on first paint.
///
/// Files are taken in the order git reported them and kept whole, so the top
/// of the diff — where the user starts reading — is complete rather than a
/// mixture of expanded and collapsed files. The first file is always expanded
/// even if it alone blows the budget, so a single huge file never shows an
/// empty view. Everything past the budget renders as a header the user can
/// click to expand, which costs one cheap row per file.
Set<String> initiallyExpandedPaths(
  List<FileDiff> files, {
  int lineBudget = kDiffRenderLineBudget,
  int fileCap = kDiffRenderFileCap,
}) {
  final expanded = <String>{};
  var spent = 0;
  for (final f in files) {
    final cost = f.isBinary
        ? kBinaryFileRenderCost
        : f.hunks.fold<int>(0, (sum, h) => sum + h.lines.length);
    final isFirst = expanded.isEmpty;
    if (!isFirst && (expanded.length >= fileCap || spent + cost > lineBudget)) {
      break;
    }
    expanded.add(f.path);
    spent += cost;
  }
  return expanded;
}
