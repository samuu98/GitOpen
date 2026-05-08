import 'package:equatable/equatable.dart';

final class LaneSegment extends Equatable {
  final int fromLane;
  final int toLane;
  final int color;
  const LaneSegment(this.fromLane, this.toLane, this.color);
  @override
  List<Object?> get props => [fromLane, toLane, color];
}
