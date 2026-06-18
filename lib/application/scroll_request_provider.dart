import 'package:flutter_riverpod/legacy.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';

/// Set to a commit SHA to request the commit graph to scroll that commit
/// into view. The graph panel consumes and clears it; the value carries no
/// long-term state so consumers should not rely on its current value.
final scrollRequestProvider = StateProvider<CommitSha?>((_) => null);
