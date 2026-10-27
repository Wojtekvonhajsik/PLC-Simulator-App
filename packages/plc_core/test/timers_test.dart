import 'package:plc_core/plc_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  late LadderBuilder b;
  setUp(() => b = LadderBuilder());

  group('TON', () {
    test('Q after PT while IN stays on, resets when IN drops', () {
      final plc = runtimeFor([
        b.network([b.no('Start'), b.ton('T1', 'T#100ms'), b.coil('Lamp')]),
      ]);
      final t1 = plc.timer('T1')!;
      plc.press('Start');
      plc.scan();
      expect(t1.et, 0, reason: 'starts in the scan with the rising edge');
      plc.scans(9);
      expect(t1.et, 90);
      expect(plc.out('Lamp'), isFalse);
      plc.scan();
      expect(t1.et, 100);
      expect(t1.pt, 100);
      expect(plc.out('Lamp'), isTrue);
      plc.scans(5);
      expect(t1.et, 100, reason: 'ET stops at PT');

      plc.release('Start');
      plc.scan();
      expect(t1.et, 0);
      expect(plc.out('Lamp'), isFalse);
    });

    test('interrupted IN restarts the timer', () {
      final plc = runtimeFor([
        b.network([b.no('Start'), b.ton('T1', 'T#50ms'), b.coil('Lamp')]),
      ]);
      plc.press('Start');
      plc.scans(4);
      plc.release('Start');
      plc.scan();
      plc.press('Start');
      plc.scans(5);
      expect(plc.out('Lamp'), isFalse);
      plc.scan();
      expect(plc.out('Lamp'), isTrue);
    });

    test('PT = 0 switches on immediately', () {
      final plc = runtimeFor([
        b.network([b.no('Start'), b.ton('T1', 'T#0ms'), b.coil('Lamp')]),
      ]);
      plc.press('Start');
      plc.scan();
      expect(plc.out('Lamp'), isTrue);
    });
  });

  test('TOF keeps Q for PT after IN drops, retriggers when IN returns', () {
    final plc = runtimeFor([
      b.network([b.no('Start'), b.tof('T1', 'T#50ms'), b.coil('Lamp')]),
    ]);
    final t1 = plc.timer('T1')!;
    plc.scan();
    expect(plc.out('Lamp'), isFalse);
    plc.press('Start');
    plc.scan();
    expect(plc.out('Lamp'), isTrue);

    plc.release('Start');
    plc.scans(3);
    expect(plc.out('Lamp'), isTrue);
    plc.press('Start');
    plc.scan();
    expect(t1.et, 0, reason: 'IN back on resets ET');

    plc.release('Start');
    plc.scans(5);
    expect(plc.out('Lamp'), isTrue);
    expect(t1.et, 40);
    plc.scan();
    expect(plc.out('Lamp'), isFalse);
    expect(t1.et, 50, reason: 'ET stays at PT after expiry');
  });

  test('TP gives a fixed pulse, ignores IN during the pulse', () {
    final plc = runtimeFor([
      b.network([b.no('Start'), b.tp('T1', 'T#50ms'), b.coil('Lamp')]),
    ]);
    final t1 = plc.timer('T1')!;
    plc.press('Start');
    plc.scan();
    expect(plc.out('Lamp'), isTrue);
    plc.release('Start');
    plc.scan();
    plc.press('Start'); // retrigger is ignored
    plc.scans(3);
    expect(plc.out('Lamp'), isTrue);
    plc.scan();
    expect(plc.out('Lamp'), isFalse, reason: 'pulse ends after 50 ms');
    expect(t1.et, 50, reason: 'ET holds PT while IN stays on');
    plc.scans(3);
    expect(plc.out('Lamp'), isFalse, reason: 'held IN does not start a new pulse');

    plc.release('Start');
    plc.scan();
    expect(t1.et, 0);
    plc.press('Start');
    plc.scan();
    expect(plc.out('Lamp'), isTrue, reason: 'new rising edge, new pulse');
  });

  test('TONR accumulates time across interruptions until reset', () {
    final plc = runtimeFor([
      b.network([b.no('Start'), b.tonr('T1', 'T#100ms', reset: 'Reset'), b.coil('Lamp')]),
    ]);
    final t1 = plc.timer('T1')!;
    plc.press('Start');
    plc.scans(7); // 0..60 ms
    plc.release('Start');
    plc.scans(10);
    expect(t1.et, 60, reason: 'ET is retained while IN is off');

    plc.press('Start');
    plc.scans(4); // 60 + 0..30
    expect(t1.et, 90);
    expect(plc.out('Lamp'), isFalse);
    plc.scan();
    expect(t1.et, 100);
    expect(plc.out('Lamp'), isTrue);

    plc.release('Start');
    plc.scans(3);
    expect(plc.out('Lamp'), isTrue, reason: 'Q stays on until R');

    plc.press('Reset');
    plc.scan();
    expect(t1.et, 0);
    expect(plc.out('Lamp'), isFalse);
  });

  test('timer members are usable in other networks', () {
    final plc = runtimeFor([
      b.network([b.no('Start'), b.ton('T_Cycle', 'T#1s')]),
      b.network([b.no('T_Cycle.Q'), b.coil('Lamp')]),
      b.network([b.compare('T_Cycle.ET', CompareOp.greaterOrEqual, 'T#500ms'), b.coil('Horn')]),
      b.network([b.compare('t_cycle.pt', CompareOp.equal, 'T#1s'), b.coil('Motor')]),
    ]);
    plc.press('Start');
    plc.scans(50);
    expect(plc.out('Horn'), isFalse);
    plc.scan();
    expect(plc.out('Horn'), isTrue);
    expect(plc.out('Lamp'), isFalse);
    expect(plc.out('Motor'), isTrue);
    plc.scans(50);
    expect(plc.out('Lamp'), isTrue);
  });

  test('blinker built from two TON timers', () {
    // Lamp blinks with 200 ms on / 200 ms off.
    final plc = runtimeFor([
      b.network([b.nc('T_Off.Q'), b.ton('T_On', 'T#200ms')]),
      b.network([b.no('T_On.Q'), b.ton('T_Off', 'T#200ms')]),
      b.network([b.no('Start'), b.no('T_On.Q'), b.coil('Lamp')]),
    ]);
    plc.press('Start');
    final samples = <bool>[];
    for (var i = 0; i < 8; i++) {
      plc.scans(10);
      samples.add(plc.out('Lamp'));
    }
    expect(samples, [false, false, true, true, false, false, true, true]);
  });

  test('timing follows simulated time, not wall clock', () {
    final plc = runtimeFor([
      b.network([b.no('Start'), b.ton('T1', 'T#5s'), b.coil('Lamp')]),
    ]);
    plc.press('Start');
    plc.scan(cycleMs: 1000);
    plc.scans(4, cycleMs: 1000);
    expect(plc.out('Lamp'), isFalse);
    plc.scan(cycleMs: 1000);
    expect(plc.out('Lamp'), isTrue);
    expect(plc.timeMs, 6000);
  });
}
