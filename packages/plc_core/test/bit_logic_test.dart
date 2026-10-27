import 'package:plc_core/plc_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  late LadderBuilder b;
  setUp(() => b = LadderBuilder());

  test('start-stop with self-holding', () {
    final plc = runtimeFor([
      b.network([
        b.parallel([
          [b.no('Start')],
          [b.no('Motor')],
        ]),
        b.nc('Stop'),
        b.coil('Motor'),
      ]),
    ]);

    plc.scan();
    expect(plc.out('Motor'), isFalse);

    plc.press('Start');
    plc.scan();
    expect(plc.out('Motor'), isTrue);

    plc.release('Start');
    plc.scans(5);
    expect(plc.out('Motor'), isTrue, reason: 'self-holding');

    plc.press('Stop');
    plc.scan();
    expect(plc.out('Motor'), isFalse);

    plc.release('Stop');
    plc.scan();
    expect(plc.out('Motor'), isFalse);
  });

  test('NC contact, NOT, negated coil', () {
    final plc = runtimeFor([
      b.network([b.nc('Start'), b.coil('Motor')]),
      b.network([b.no('Start'), b.not(), b.coil('Lamp')]),
      b.network([b.no('Start'), b.negatedCoil('Horn')]),
    ]);
    plc.scan();
    expect([plc.out('Motor'), plc.out('Lamp'), plc.out('Horn')], [true, true, true]);
    plc.press('Start');
    plc.scan();
    expect([plc.out('Motor'), plc.out('Lamp'), plc.out('Horn')], [false, false, false]);
  });

  test('set and reset coils keep their state', () {
    final plc = runtimeFor([
      b.network([b.no('Start'), b.setCoil('Motor')]),
      b.network([b.no('Stop'), b.resetCoil('Motor')]),
    ]);
    plc.press('Start');
    plc.scan();
    plc.release('Start');
    plc.scan();
    expect(plc.out('Motor'), isTrue);
    plc.press('Stop');
    plc.scan();
    expect(plc.out('Motor'), isFalse);
  });

  test('series-parallel logic', () {
    // Lamp = Start AND (Stop OR (Sensor AND NOT Reset))
    final plc = runtimeFor([
      b.network([
        b.no('Start'),
        b.parallel([
          [b.no('Stop')],
          [b.no('Sensor'), b.nc('Reset')],
        ]),
        b.coil('Lamp'),
      ]),
    ]);
    void check(bool start, bool stop, bool sensor, bool reset) {
      plc
        ..setInputByTag('Start', start)
        ..setInputByTag('Stop', stop)
        ..setInputByTag('Sensor', sensor)
        ..setInputByTag('Reset', reset)
        ..scan();
      expect(plc.out('Lamp'), start && (stop || (sensor && !reset)), reason: '$start $stop $sensor $reset');
    }

    for (var i = 0; i < 16; i++) {
      check(i & 1 != 0, i & 2 != 0, i & 4 != 0, i & 8 != 0);
    }
  });

  test('parallel outputs at the end of a rung', () {
    final plc = runtimeFor([
      b.network([
        b.no('Start'),
        b.parallel([
          [b.coil('Motor')],
          [b.nc('Sensor'), b.coil('Lamp')],
        ]),
      ]),
    ]);
    plc.press('Start');
    plc.scan();
    expect(plc.out('Motor'), isTrue);
    expect(plc.out('Lamp'), isTrue);
    plc.press('Sensor');
    plc.scan();
    expect(plc.out('Lamp'), isFalse);
  });

  test('TRUE and FALSE constants, absolute addresses, quoted tags', () {
    final plc = runtimeFor([
      b.network([b.no('TRUE'), b.coil('%Q0.5')]),
      b.network([b.no('false'), b.coil('%Q0.6')]),
      b.network([b.no('"Start"'), b.coil('%M1.0')]),
      b.network([b.no('%M1.0'), b.coil('lamp')]),
    ]);
    plc.press('Start');
    plc.scan();
    expect(plc.output(BitAddress.parse('%Q0.5')), isTrue);
    expect(plc.output(BitAddress.parse('%Q0.6')), isFalse);
    expect(plc.out('Lamp'), isTrue);
  });

  group('process image', () {
    test('input changes are seen only at the next scan', () {
      final plc = runtimeFor([
        b.network([b.no('Start'), b.coil('Motor')]),
      ]);
      plc.scan();
      plc.press('Start');
      expect(plc.readTag('Start'), isFalse, reason: 'PII not updated yet');
      expect(plc.out('Motor'), isFalse);
      plc.scan();
      expect(plc.readTag('Start'), isTrue);
      expect(plc.out('Motor'), isTrue);
    });

    test('networks execute top to bottom within one scan', () {
      final forward = runtimeFor([
        b.network([b.no('Start'), b.coil('Motor')]),
        b.network([b.no('Motor'), b.coil('Lamp')]),
      ]);
      forward.press('Start');
      forward.scan();
      expect(forward.out('Lamp'), isTrue);

      final reversed = runtimeFor([
        b.network([b.no('Motor'), b.coil('Lamp')]),
        b.network([b.no('Start'), b.coil('Motor')]),
      ]);
      reversed.press('Start');
      reversed.scan();
      expect(reversed.out('Motor'), isTrue);
      expect(reversed.out('Lamp'), isFalse, reason: 'Motor written after Lamp network');
      reversed.scan();
      expect(reversed.out('Lamp'), isTrue);
    });

    test('double coil: the last assignment wins', () {
      final networks = [
        b.network([b.no('Start'), b.coil('Motor')]),
        b.network([b.no('Sensor'), b.coil('Motor')]),
      ];
      final result = compileNetworks(networks);
      expect(result.warnings.map((d) => d.code), contains(DiagnosticCode.doubleCoil));

      final plc = PlcRuntime(result.program!)..start();
      plc.press('Start');
      plc.scan();
      expect(plc.out('Motor'), isFalse);
    });
  });

  group('flip-flops', () {
    test('SR is reset dominant', () {
      final plc = runtimeFor([
        b.network([b.no('Start'), b.sr('Flag', 'Stop'), b.coil('Lamp')]),
      ]);
      plc.press('Start');
      plc.scan();
      expect(plc.readTag('Flag'), isTrue);
      expect(plc.out('Lamp'), isTrue, reason: 'Q passes the flip-flop state');
      plc.release('Start');
      plc.scan();
      expect(plc.readTag('Flag'), isTrue);
      plc
        ..press('Start')
        ..press('Stop')
        ..scan();
      expect(plc.readTag('Flag'), isFalse);
    });

    test('RS is set dominant', () {
      final plc = runtimeFor([
        b.network([b.no('Stop'), b.rs('Flag', 'Start')]),
      ]);
      plc
        ..press('Start')
        ..press('Stop')
        ..scan();
      expect(plc.readTag('Flag'), isTrue);
      plc.release('Start');
      plc.scan();
      expect(plc.readTag('Flag'), isFalse);
    });
  });

  group('operating mode', () {
    test('STOP switches outputs off, START clears memory', () {
      final plc = runtimeFor([
        b.network([b.no('Start'), b.setCoil('Motor')]),
        b.network([b.no('Start'), b.setCoil('Flag')]),
      ]);
      plc.press('Start');
      plc.scan();
      expect(plc.out('Motor'), isTrue);

      plc.stop();
      expect(plc.mode, PlcMode.stop);
      expect(plc.out('Motor'), isFalse);
      plc.scan();
      expect(plc.scanCount, 1, reason: 'no scans in STOP');

      plc.release('Start');
      plc.start();
      plc.scan();
      expect(plc.out('Motor'), isFalse);
      expect(plc.readTag('Flag'), isFalse);
      expect(plc.timeMs, 10);
    });

    test('scan requires a positive cycle time', () {
      final plc = runtimeFor([]);
      expect(() => plc.scan(cycleMs: 0), throwsArgumentError);
    });
  });

  group('force and modify', () {
    test('forced input overrides the physical signal', () {
      final plc = runtimeFor([
        b.network([b.no('Start'), b.coil('Motor')]),
      ]);
      plc.force(BitAddress.parse('%I0.0'), true);
      plc.scan();
      expect(plc.out('Motor'), isTrue);
      expect(plc.inputSignal(BitAddress.parse('%I0.0')), isFalse);
      plc.force(BitAddress.parse('%I0.0'), null);
      plc.scan();
      expect(plc.out('Motor'), isFalse);
    });

    test('forced output overrides the program, also in STOP', () {
      final plc = runtimeFor([
        b.network([b.no('Start'), b.coil('Motor')]),
      ]);
      plc.force(BitAddress.parse('%Q0.0'), true);
      plc.scan();
      expect(plc.out('Motor'), isTrue);
      expect(plc.readTag('Motor'), isFalse, reason: 'PIQ still holds the program result');
      plc.stop();
      expect(plc.out('Motor'), isTrue);
      plc.clearForces();
      expect(plc.out('Motor'), isFalse);
    });

    test('markers cannot be forced, inputs cannot be modified', () {
      final plc = runtimeFor([]);
      expect(() => plc.force(BitAddress.parse('%M0.0'), true), throwsArgumentError);
      expect(() => plc.modify(BitAddress.parse('%I0.0'), true), throwsArgumentError);
      expect(() => plc.setInput(BitAddress.parse('%Q0.0'), true), throwsArgumentError);
      expect(() => plc.readBit(BitAddress.parse('%I99.0')), throwsRangeError);
      expect(() => plc.setInputByTag('Nope', true), throwsArgumentError);
    });

    test('modify writes bit memory once', () {
      final plc = runtimeFor([
        b.network([b.no('Flag'), b.coil('Lamp')]),
      ]);
      plc.modify(BitAddress.parse('%M0.0'), true);
      plc.scan();
      expect(plc.out('Lamp'), isTrue);
    });
  });

  test('monitoring records power flow per element', () {
    final start = b.no('Start');
    final stop = b.nc('Stop');
    final coil = b.coil('Motor');
    final plc = runtimeFor([
      b.network([start, stop, coil]),
    ]);
    plc.scan();
    expect(plc.monitor, isEmpty);

    plc.monitoring = true;
    plc.press('Stop');
    plc.press('Start');
    plc.scan();
    expect(plc.monitor[start.id]!.powerOut, isTrue);
    expect(plc.monitor[stop.id]!.powerIn, isTrue);
    expect(plc.monitor[stop.id]!.powerOut, isFalse);
    expect(plc.monitor[coil.id]!.powerIn, isFalse);
  });

  test('compiled program can run in several independent runtimes', () {
    final program = compileNetworks([
      b.network([b.no('Start'), b.coil('Motor')]),
    ]).program!;
    final a = PlcRuntime(program)..start();
    final c = PlcRuntime(program)..start();
    a.press('Start');
    a.scan();
    c.scan();
    expect(a.out('Motor'), isTrue);
    expect(c.out('Motor'), isFalse);
  });
}
