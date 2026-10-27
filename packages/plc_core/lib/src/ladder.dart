/// Ladder (LAD) program model.
///
/// A network is a series-parallel tree: [Series] holds elements evaluated left
/// to right, [Parallel] holds branches (each a [Series]) evaluated top to bottom
/// and OR-ed together. Operands are kept as text exactly as the user typed them
/// (`Start`, `%I0.0`, `T1.Q`, `T#5s`, `10`); the compiler resolves and validates them.
library;

sealed class LadNode {
  const LadNode(this.id);

  /// Unique within the program; used by the editor and by online monitoring.
  final String id;
}

final class Series extends LadNode {
  const Series(super.id, this.children);

  final List<LadNode> children;
}

final class Parallel extends LadNode {
  const Parallel(super.id, this.branches);

  final List<Series> branches;
}

enum ContactKind { normallyOpen, normallyClosed }

/// `-| |-` / `-|/|-`
final class Contact extends LadNode {
  const Contact(super.id, this.kind, this.operand);

  final ContactKind kind;
  final String operand;
}

/// `-|NOT|-` — inverts the power flow.
final class NotContact extends LadNode {
  const NotContact(super.id);
}

enum EdgeKind { positive, negative }

/// `-|P|-` / `-|N|-` — passes power for one scan when [operand] changes.
/// [memoryBit] stores the previous state of the operand.
final class EdgeContact extends LadNode {
  const EdgeContact(super.id, this.kind, this.operand, this.memoryBit);

  final EdgeKind kind;
  final String operand;
  final String memoryBit;
}

enum CompareOp {
  equal('=='),
  notEqual('<>'),
  greater('>'),
  less('<'),
  greaterOrEqual('>='),
  lessOrEqual('<=');

  const CompareOp(this.symbol);

  final String symbol;
}

/// Comparator box placed like a contact: power AND (in1 op in2).
final class CompareContact extends LadNode {
  const CompareContact(super.id, this.op, this.in1, this.in2);

  final CompareOp op;
  final String in1;
  final String in2;
}

enum RangeKind { inRange, outRange }

/// IN_RANGE (`min <= value <= max`) / OUT_RANGE (`value < min || value > max`).
final class RangeContact extends LadNode {
  const RangeContact(super.id, this.kind, this.min, this.value, this.max);

  final RangeKind kind;
  final String min;
  final String value;
  final String max;
}

enum CoilKind { assign, negated, set, reset }

/// `-( )-`, `-(/)-`, `-(S)-`, `-(R)-`. Passes power through.
final class Coil extends LadNode {
  const Coil(super.id, this.kind, this.operand);

  final CoilKind kind;
  final String operand;
}

/// `-(P)-` / `-(N)-` — sets [operand] for one scan on an edge of the power flow.
final class EdgeCoil extends LadNode {
  const EdgeCoil(super.id, this.kind, this.operand, this.memoryBit);

  final EdgeKind kind;
  final String operand;
  final String memoryBit;
}

enum FlipFlopKind {
  /// Reset dominant. Power flow drives S, [FlipFlopBox.secondInput] is R1.
  sr,

  /// Set dominant. Power flow drives R, [FlipFlopBox.secondInput] is S1.
  rs,
}

final class FlipFlopBox extends LadNode {
  const FlipFlopBox(super.id, this.kind, this.operand, this.secondInput);

  final FlipFlopKind kind;
  final String operand;
  final String secondInput;
}

/// P_TRIG / N_TRIG — output is the edge of the power flow (CLK).
final class TriggerBox extends LadNode {
  const TriggerBox(super.id, this.kind, this.memoryBit);

  final EdgeKind kind;
  final String memoryBit;
}

enum TimerKind { ton, tof, tp, tonr }

/// IEC timer. Power flow drives IN, output is Q.
final class TimerBox extends LadNode {
  const TimerBox(super.id, this.kind, this.instance, this.presetTime, {this.reset});

  final TimerKind kind;

  /// Instance name, e.g. `T_Wysuw`. Members are readable as `T_Wysuw.Q`, `.ET`, `.PT`.
  final String instance;
  final String presetTime;

  /// R input — TONR only.
  final String? reset;
}

enum CounterKind { ctu, ctd, ctud }

/// IEC counter. Power flow drives CU (CTU, CTUD) or CD (CTD). Output is Q (CTU, CTD) or QU (CTUD).
final class CounterBox extends LadNode {
  const CounterBox(
    super.id,
    this.kind,
    this.instance,
    this.presetValue, {
    this.countDown,
    this.reset,
    this.load,
  });

  final CounterKind kind;

  /// Instance name. Members: `.CV`, `.PV`, `.Q` (CTU, CTD), `.QU`, `.QD` (CTUD).
  final String instance;
  final String presetValue;

  /// CD input — CTUD only.
  final String? countDown;

  /// R input — CTU and CTUD.
  final String? reset;

  /// LD input — CTD and CTUD.
  final String? load;
}

final class Network {
  const Network({required this.id, required this.rung, this.title = '', this.comment = ''});

  final String id;
  final String title;
  final String comment;
  final Series rung;
}

final class Program {
  const Program(this.networks);

  final List<Network> networks;
}
