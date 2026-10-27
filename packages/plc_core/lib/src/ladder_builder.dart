import 'ladder.dart';

/// Concise construction of ladder programs with generated ids — used by tests
/// and by built-in templates.
///
/// ```dart
/// final b = LadderBuilder();
/// final net = b.network([
///   b.parallel([[b.no('Start')], [b.no('Motor')]]),
///   b.nc('Stop'),
///   b.coil('Motor'),
/// ]);
/// ```
final class LadderBuilder {
  LadderBuilder({this.prefix = 'e'});

  final String prefix;
  int _next = 0;

  String _id() => '$prefix${_next++}';

  Network network(List<LadNode> elements, {String title = '', String comment = ''}) =>
      Network(id: _id(), title: title, comment: comment, rung: Series(_id(), elements));

  Series series(List<LadNode> elements) => Series(_id(), elements);

  Parallel parallel(List<List<LadNode>> branches) =>
      Parallel(_id(), [for (final branch in branches) Series(_id(), branch)]);

  Contact no(String operand) => Contact(_id(), ContactKind.normallyOpen, operand);
  Contact nc(String operand) => Contact(_id(), ContactKind.normallyClosed, operand);
  NotContact not() => NotContact(_id());

  EdgeContact posEdge(String operand, String memoryBit) => EdgeContact(_id(), EdgeKind.positive, operand, memoryBit);
  EdgeContact negEdge(String operand, String memoryBit) => EdgeContact(_id(), EdgeKind.negative, operand, memoryBit);

  CompareContact compare(String in1, CompareOp op, String in2) => CompareContact(_id(), op, in1, in2);
  RangeContact inRange(String min, String value, String max) => RangeContact(_id(), RangeKind.inRange, min, value, max);
  RangeContact outRange(String min, String value, String max) =>
      RangeContact(_id(), RangeKind.outRange, min, value, max);

  Coil coil(String operand) => Coil(_id(), CoilKind.assign, operand);
  Coil negatedCoil(String operand) => Coil(_id(), CoilKind.negated, operand);
  Coil setCoil(String operand) => Coil(_id(), CoilKind.set, operand);
  Coil resetCoil(String operand) => Coil(_id(), CoilKind.reset, operand);

  EdgeCoil posEdgeCoil(String operand, String memoryBit) => EdgeCoil(_id(), EdgeKind.positive, operand, memoryBit);
  EdgeCoil negEdgeCoil(String operand, String memoryBit) => EdgeCoil(_id(), EdgeKind.negative, operand, memoryBit);

  FlipFlopBox sr(String operand, String resetInput) => FlipFlopBox(_id(), FlipFlopKind.sr, operand, resetInput);
  FlipFlopBox rs(String operand, String setInput) => FlipFlopBox(_id(), FlipFlopKind.rs, operand, setInput);

  TriggerBox pTrig(String memoryBit) => TriggerBox(_id(), EdgeKind.positive, memoryBit);
  TriggerBox nTrig(String memoryBit) => TriggerBox(_id(), EdgeKind.negative, memoryBit);

  TimerBox ton(String instance, String presetTime) => TimerBox(_id(), TimerKind.ton, instance, presetTime);
  TimerBox tof(String instance, String presetTime) => TimerBox(_id(), TimerKind.tof, instance, presetTime);
  TimerBox tp(String instance, String presetTime) => TimerBox(_id(), TimerKind.tp, instance, presetTime);
  TimerBox tonr(String instance, String presetTime, {String? reset}) =>
      TimerBox(_id(), TimerKind.tonr, instance, presetTime, reset: reset);

  CounterBox ctu(String instance, String presetValue, {String? reset}) =>
      CounterBox(_id(), CounterKind.ctu, instance, presetValue, reset: reset);
  CounterBox ctd(String instance, String presetValue, {String? load}) =>
      CounterBox(_id(), CounterKind.ctd, instance, presetValue, load: load);
  CounterBox ctud(String instance, String presetValue, {String? countDown, String? reset, String? load}) =>
      CounterBox(_id(), CounterKind.ctud, instance, presetValue, countDown: countDown, reset: reset, load: load);
}
