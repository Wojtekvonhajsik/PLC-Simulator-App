import 'dart:math';

import 'simulation.dart';

/// Converts real elapsed time (from the UI ticker) into simulation cycles.
///
/// The simulation always advances in whole, fixed cycles, so results do not
/// depend on the frame rate or on [speed] — only on simulated time.
final class SimulationClock {
  SimulationClock(this.simulation, {this.maxStepsPerTick = 200});

  final Simulation simulation;

  /// Upper bound of cycles per [tick]; a slower device drops the backlog
  /// instead of freezing while it catches up.
  final int maxStepsPerTick;

  double _speed = 1;
  bool paused = false;
  double _pendingMs = 0;

  double get speed => _speed;

  /// Simulated time per real time, from 0.05 (slow motion) to 20.
  set speed(double value) {
    if (value < 0.05 || value > 20) throw ArgumentError.value(value, 'speed', 'must be between 0.05 and 20');
    _speed = value;
  }

  /// Call on every frame with the real time elapsed since the previous call.
  /// Returns the number of cycles executed.
  int tick(int realElapsedMs) {
    if (realElapsedMs < 0) throw ArgumentError.value(realElapsedMs, 'realElapsedMs', 'must not be negative');
    if (paused) return 0;
    _pendingMs += realElapsedMs * _speed;
    final cycle = simulation.cycleMs;
    var steps = 0;
    while (_pendingMs >= cycle && steps < maxStepsPerTick) {
      simulation.step();
      _pendingMs -= cycle;
      steps++;
    }
    if (steps == maxStepsPerTick) _pendingMs = min(_pendingMs, cycle.toDouble());
    return steps;
  }

  /// Executes exactly one cycle — for step-by-step debugging while paused.
  void stepOnce() => simulation.step();
}
