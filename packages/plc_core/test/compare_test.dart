import 'package:plc_core/plc_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  late LadderBuilder b;
  setUp(() => b = LadderBuilder());

  test('all comparison operators on INT values', () {
    final ops = CompareOp.values;
    final tags = [
      ...standardTags,
      for (var i = 0; i < ops.length; i++) Tag(name: 'Out${ops[i].name}', address: '%Q1.$i'),
    ];
    // C1.CV takes values 0..4 and is compared with 2.
    final plc = runtimeFor([
      b.network([b.no('Sensor'), b.ctu('C1', '100')]),
      for (final op in ops) b.network([b.compare('C1.CV', op, '2'), b.coil('Out${op.name}')]),
    ], tags: tags);

    for (var cv = 0; cv <= 4; cv++) {
      expect(plc.counter('C1')?.cv ?? 0, cv);
      plc.scan();
      final expected = {
        CompareOp.equal: cv == 2,
        CompareOp.notEqual: cv != 2,
        CompareOp.greater: cv > 2,
        CompareOp.less: cv < 2,
        CompareOp.greaterOrEqual: cv >= 2,
        CompareOp.lessOrEqual: cv <= 2,
      };
      for (final op in ops) {
        expect(plc.outputByTag('Out${op.name}'), expected[op], reason: 'CV=$cv ${op.symbol} 2');
      }
      plc.press('Sensor');
      plc.scan();
      plc.release('Sensor');
    }
  });

  test('comparator is ANDed with the power flow', () {
    final plc = runtimeFor([
      b.network([b.no('Start'), b.compare('5', CompareOp.greater, '3'), b.coil('Lamp')]),
    ]);
    plc.scan();
    expect(plc.out('Lamp'), isFalse);
    plc.press('Start');
    plc.scan();
    expect(plc.out('Lamp'), isTrue);
  });

  test('IN_RANGE and OUT_RANGE', () {
    final plc = runtimeFor([
      b.network([b.no('Sensor'), b.ctu('C1', '100')]),
      b.network([b.inRange('2', 'C1.CV', '3'), b.coil('Lamp')]),
      b.network([b.outRange('2', 'C1.CV', '3'), b.coil('Horn')]),
    ]);
    final inside = <bool>[];
    final outside = <bool>[];
    for (var cv = 0; cv <= 4; cv++) {
      plc.scan();
      inside.add(plc.out('Lamp'));
      outside.add(plc.out('Horn'));
      plc.press('Sensor');
      plc.scan();
      plc.release('Sensor');
    }
    expect(inside, [false, false, true, true, false]);
    expect(outside, [true, true, false, false, true]);
  });

  test('TIME comparison with ranges', () {
    final plc = runtimeFor([
      b.network([b.no('Start'), b.ton('T1', 'T#10s')]),
      b.network([b.inRange('T#1s', 'T1.ET', 'T#2s'), b.coil('Lamp')]),
    ]);
    plc.press('Start');
    plc.scan(cycleMs: 500); // ET 0
    plc.scan(cycleMs: 500); // ET 500
    expect(plc.out('Lamp'), isFalse);
    plc.scan(cycleMs: 500); // ET 1000
    expect(plc.out('Lamp'), isTrue);
    plc.scans(3, cycleMs: 500); // ET 2500
    expect(plc.out('Lamp'), isFalse);
  });
}
