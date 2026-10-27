import 'package:plc_core/plc_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  late LadderBuilder b;
  setUp(() => b = LadderBuilder());

  void pulse(PlcRuntime plc, String tag, [int times = 1]) {
    for (var i = 0; i < times; i++) {
      plc.press(tag);
      plc.scans(2);
      plc.release(tag);
      plc.scans(2);
    }
  }

  test('CTU counts rising edges, Q at PV, R clears', () {
    final plc = runtimeFor([
      b.network([b.no('Sensor'), b.ctu('C1', '3', reset: 'Reset'), b.coil('Lamp')]),
    ]);
    final c1 = plc.counter('C1')!;
    pulse(plc, 'Sensor', 2);
    expect(c1.cv, 2);
    expect(plc.out('Lamp'), isFalse);
    pulse(plc, 'Sensor');
    expect(c1.cv, 3);
    expect(c1.pv, 3);
    expect(plc.out('Lamp'), isTrue);
    pulse(plc, 'Sensor');
    expect(c1.cv, 4, reason: 'keeps counting past PV');

    plc.press('Reset');
    plc.press('Sensor');
    plc.scan();
    expect(c1.cv, 0, reason: 'R has priority over CU');
    expect(plc.out('Lamp'), isFalse);
    plc.release('Reset');
    plc.scan();
    expect(c1.cv, 0, reason: 'CU held during reset is not counted afterwards');
  });

  test('CTD loads PV and counts down, Q at CV <= 0', () {
    final plc = runtimeFor([
      b.network([b.no('Sensor'), b.ctd('C1', '2', load: 'Reset'), b.coil('Lamp')]),
    ]);
    final c1 = plc.counter('C1')!;
    pulse(plc, 'Reset');
    expect(c1.cv, 2);
    expect(plc.out('Lamp'), isFalse);
    pulse(plc, 'Sensor', 2);
    expect(c1.cv, 0);
    expect(plc.out('Lamp'), isTrue);
    pulse(plc, 'Sensor');
    expect(c1.cv, -1);
  });

  test('CTUD counts both ways with QU and QD', () {
    final plc = runtimeFor([
      b.network([
        b.no('Start'),
        b.ctud('C1', '2', countDown: 'Stop', reset: 'Reset', load: 'Sensor'),
        b.coil('Lamp'),
      ]),
      b.network([b.no('C1.QD'), b.coil('Horn')]),
    ]);
    final c1 = plc.counter('C1')!;
    pulse(plc, 'Start', 2);
    expect(c1.cv, 2);
    expect(plc.out('Lamp'), isTrue, reason: 'box output is QU');
    pulse(plc, 'Stop', 3);
    expect(c1.cv, -1);
    expect(plc.out('Lamp'), isFalse);
    expect(plc.out('Horn'), isTrue);
    pulse(plc, 'Sensor');
    expect(c1.cv, 2, reason: 'LD loads PV');

    plc
      ..press('Reset')
      ..press('Sensor')
      ..scan();
    expect(c1.cv, 0, reason: 'R has priority over LD');
  });

  test('counter saturates at the INT limit', () {
    final plc = runtimeFor([
      b.network([b.no('Start'), b.ctud('C1', '32767', load: 'Sensor')]),
    ]);
    pulse(plc, 'Sensor');
    expect(plc.counter('C1')!.cv, intMax);
    pulse(plc, 'Start');
    expect(plc.counter('C1')!.cv, intMax);
  });

  test('stop after N cycles: CTU + comparator on CV', () {
    final plc = runtimeFor([
      b.network([b.no('Sensor'), b.ctu('Parts', '5', reset: 'Reset')]),
      b.network([b.compare('Parts.CV', CompareOp.greaterOrEqual, '3'), b.coil('Lamp')]),
      b.network([b.no('Start'), b.nc('Parts.Q'), b.coil('Motor')]),
    ]);
    plc.press('Start');
    plc.scan();
    expect(plc.out('Motor'), isTrue);
    pulse(plc, 'Sensor', 3);
    expect(plc.out('Lamp'), isTrue);
    expect(plc.out('Motor'), isTrue);
    pulse(plc, 'Sensor', 2);
    expect(plc.out('Motor'), isFalse);
  });
}
