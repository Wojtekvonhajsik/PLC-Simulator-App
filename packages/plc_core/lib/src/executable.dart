// Executable form of a compiled ladder program. Internal to the package.

import 'address.dart';
import 'instances.dart';
import 'ladder.dart';
import 'memory.dart';

/// Power flow into and out of an element during the last scan.
final class ElementStatus {
  const ElementStatus(this.powerIn, this.powerOut);

  final bool powerIn;
  final bool powerOut;
}

final class ExecContext {
  ExecContext(this.memory, this.timers, this.counters);

  final ProcessMemory memory;
  final List<TimerState> timers;
  final List<CounterState> counters;
  int now = 0;
  Map<String, ElementStatus>? monitor;
}

abstract interface class BitSource {
  bool read(ExecContext ctx);
}

abstract interface class ValueSource {
  int read(ExecContext ctx);
}

final class AreaBit implements BitSource {
  const AreaBit(this.address);

  final BitAddress address;

  @override
  bool read(ExecContext ctx) => ctx.memory.read(address);

  void write(ExecContext ctx, bool value) => ctx.memory.write(address, value);
}

final class ConstBit implements BitSource {
  const ConstBit(this.value);

  final bool value;

  @override
  bool read(ExecContext ctx) => value;
}

final class MemberBit implements BitSource {
  const MemberBit(this._read);

  final bool Function(ExecContext ctx) _read;

  @override
  bool read(ExecContext ctx) => _read(ctx);
}

final class ConstValue implements ValueSource {
  const ConstValue(this.value);

  final int value;

  @override
  int read(ExecContext ctx) => value;
}

final class MemberValue implements ValueSource {
  const MemberValue(this._read);

  final int Function(ExecContext ctx) _read;

  @override
  int read(ExecContext ctx) => _read(ctx);
}

abstract base class ExecNode {
  ExecNode(this.id);

  final String id;

  bool run(bool power, ExecContext ctx) {
    final out = evaluate(power, ctx);
    ctx.monitor?[id] = ElementStatus(power, out);
    return out;
  }

  bool evaluate(bool power, ExecContext ctx);
}

final class SeriesExec extends ExecNode {
  SeriesExec(super.id, this.children);

  final List<ExecNode> children;

  @override
  bool evaluate(bool power, ExecContext ctx) {
    var flow = power;
    // Every element runs even without power, so timers, counters and edge
    // memories see IN = 0 exactly as in a real PLC.
    for (final child in children) {
      flow = child.run(flow, ctx);
    }
    return flow;
  }
}

final class ParallelExec extends ExecNode {
  ParallelExec(super.id, this.branches);

  final List<ExecNode> branches;

  @override
  bool evaluate(bool power, ExecContext ctx) {
    var out = false;
    for (final branch in branches) {
      final flow = branch.run(power, ctx);
      out = out || flow;
    }
    return out;
  }
}

final class ContactExec extends ExecNode {
  ContactExec(super.id, this.operand, {required this.normallyClosed});

  final BitSource operand;
  final bool normallyClosed;

  @override
  bool evaluate(bool power, ExecContext ctx) => power && (operand.read(ctx) != normallyClosed);
}

final class NotExec extends ExecNode {
  NotExec(super.id);

  @override
  bool evaluate(bool power, ExecContext ctx) => !power;
}

bool _edge(EdgeKind kind, bool current, AreaBit memory, ExecContext ctx) {
  final previous = memory.read(ctx);
  memory.write(ctx, current);
  return kind == EdgeKind.positive ? current && !previous : !current && previous;
}

final class EdgeContactExec extends ExecNode {
  EdgeContactExec(super.id, this.kind, this.operand, this.memory);

  final EdgeKind kind;
  final BitSource operand;
  final AreaBit memory;

  @override
  bool evaluate(bool power, ExecContext ctx) {
    final edge = _edge(kind, operand.read(ctx), memory, ctx);
    return power && edge;
  }
}

final class CompareExec extends ExecNode {
  CompareExec(super.id, this.op, this.in1, this.in2);

  final CompareOp op;
  final ValueSource in1;
  final ValueSource in2;

  @override
  bool evaluate(bool power, ExecContext ctx) {
    final a = in1.read(ctx);
    final b = in2.read(ctx);
    final result = switch (op) {
      CompareOp.equal => a == b,
      CompareOp.notEqual => a != b,
      CompareOp.greater => a > b,
      CompareOp.less => a < b,
      CompareOp.greaterOrEqual => a >= b,
      CompareOp.lessOrEqual => a <= b,
    };
    return power && result;
  }
}

final class RangeExec extends ExecNode {
  RangeExec(super.id, this.kind, this.min, this.value, this.max);

  final RangeKind kind;
  final ValueSource min;
  final ValueSource value;
  final ValueSource max;

  @override
  bool evaluate(bool power, ExecContext ctx) {
    final v = value.read(ctx);
    final inside = v >= min.read(ctx) && v <= max.read(ctx);
    return power && (kind == RangeKind.inRange ? inside : !inside);
  }
}

final class CoilExec extends ExecNode {
  CoilExec(super.id, this.kind, this.target);

  final CoilKind kind;
  final AreaBit target;

  @override
  bool evaluate(bool power, ExecContext ctx) {
    switch (kind) {
      case CoilKind.assign:
        target.write(ctx, power);
      case CoilKind.negated:
        target.write(ctx, !power);
      case CoilKind.set:
        if (power) target.write(ctx, true);
      case CoilKind.reset:
        if (power) target.write(ctx, false);
    }
    return power;
  }
}

final class EdgeCoilExec extends ExecNode {
  EdgeCoilExec(super.id, this.kind, this.target, this.memory);

  final EdgeKind kind;
  final AreaBit target;
  final AreaBit memory;

  @override
  bool evaluate(bool power, ExecContext ctx) {
    target.write(ctx, _edge(kind, power, memory, ctx));
    return power;
  }
}

final class FlipFlopExec extends ExecNode {
  FlipFlopExec(super.id, this.kind, this.target, this.secondInput);

  final FlipFlopKind kind;
  final AreaBit target;
  final BitSource secondInput;

  @override
  bool evaluate(bool power, ExecContext ctx) {
    final second = secondInput.read(ctx);
    switch (kind) {
      case FlipFlopKind.sr:
        if (second) {
          target.write(ctx, false);
        } else if (power) {
          target.write(ctx, true);
        }
      case FlipFlopKind.rs:
        if (second) {
          target.write(ctx, true);
        } else if (power) {
          target.write(ctx, false);
        }
    }
    return target.read(ctx);
  }
}

final class TriggerExec extends ExecNode {
  TriggerExec(super.id, this.kind, this.memory);

  final EdgeKind kind;
  final AreaBit memory;

  @override
  bool evaluate(bool power, ExecContext ctx) => _edge(kind, power, memory, ctx);
}

final class TimerExec extends ExecNode {
  TimerExec(super.id, this.index, this.preset, this.reset);

  final int index;
  final ValueSource preset;
  final BitSource? reset;

  @override
  bool evaluate(bool power, ExecContext ctx) {
    final state = ctx.timers[index];
    state.update(
      input: power,
      preset: preset.read(ctx),
      now: ctx.now,
      reset: reset?.read(ctx) ?? false,
    );
    return state.q;
  }
}

final class CounterExec extends ExecNode {
  CounterExec(super.id, this.index, this.preset, {this.countDown, this.reset, this.load});

  final int index;
  final ValueSource preset;
  final BitSource? countDown;
  final BitSource? reset;
  final BitSource? load;

  @override
  bool evaluate(bool power, ExecContext ctx) {
    final state = ctx.counters[index];
    final isCtd = state.kind == CounterKind.ctd;
    state.update(
      preset: preset.read(ctx),
      countUp: !isCtd && power,
      countDown: isCtd ? power : countDown?.read(ctx) ?? false,
      reset: reset?.read(ctx) ?? false,
      load: load?.read(ctx) ?? false,
    );
    return state.q;
  }
}
