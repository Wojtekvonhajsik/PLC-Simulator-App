import 'package:plc_core/plc_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  late LadderBuilder b;
  setUp(() => b = LadderBuilder());

  /// Lamp states over consecutive scans while [Start] follows [pattern].
  List<bool> trace(PlcRuntime plc, List<bool> pattern) => [
        for (final value in pattern) ...[
          () {
            plc
              ..setInputByTag('Start', value)
              ..scan();
            return plc.out('Lamp');
          }(),
        ],
      ];

  test('-|P|- passes power for exactly one scan on a rising edge', () {
    final plc = runtimeFor([
      b.network([b.posEdge('Start', '%M10.0'), b.coil('Lamp')]),
    ]);
    expect(trace(plc, [false, true, true, true, false, true]), [false, true, false, false, false, true]);
  });

  test('-|N|- passes power for exactly one scan on a falling edge', () {
    final plc = runtimeFor([
      b.network([b.negEdge('Start', '%M10.0'), b.coil('Lamp')]),
    ]);
    expect(trace(plc, [false, true, true, false, false, true, false]), [false, false, false, true, false, false, true]);
  });

  test('edge contact evaluates its operand even without power flow', () {
    final plc = runtimeFor([
      b.network([b.no('Sensor'), b.posEdge('Start', '%M10.0'), b.coil('Lamp')]),
    ]);
    plc.press('Start');
    plc.scan(); // edge consumed while Sensor = 0
    plc.press('Sensor');
    plc.scan();
    expect(plc.out('Lamp'), isFalse);
  });

  test('-(P)- and -(N)- coils set the operand for one scan', () {
    final plc = runtimeFor([
      b.network([
        b.no('Start'),
        b.parallel([
          [b.posEdgeCoil('Lamp', '%M10.0')],
          [b.negEdgeCoil('Horn', '%M10.1')],
        ]),
      ]),
    ]);
    final lamp = <bool>[];
    final horn = <bool>[];
    for (final value in [true, true, false, false]) {
      plc
        ..setInputByTag('Start', value)
        ..scan();
      lamp.add(plc.out('Lamp'));
      horn.add(plc.out('Horn'));
    }
    expect(lamp, [true, false, false, false]);
    expect(horn, [false, false, true, false]);
  });

  test('P_TRIG and N_TRIG detect edges of the power flow', () {
    final plc = runtimeFor([
      b.network([b.no('Start'), b.pTrig('%M10.0'), b.coil('Lamp')]),
      b.network([b.no('Start'), b.nTrig('%M10.1'), b.coil('Horn')]),
    ]);
    expect(trace(plc, [true, true, false]), [true, false, false]);
    expect(plc.out('Horn'), isTrue);
  });

  test('pulse toggles a flip-flop (one button on/off)', () {
    // Motor toggles on each press: classic edge + SR/RS pattern.
    final plc = runtimeFor([
      b.network([
        b.posEdge('Start', '%M10.0'),
        b.parallel([
          [b.nc('Motor'), b.setCoil('Flag')],
          [b.no('Motor'), b.resetCoil('Flag')],
        ]),
      ]),
      b.network([b.no('Flag'), b.coil('Motor')]),
    ]);
    final states = <bool>[];
    for (var press = 0; press < 4; press++) {
      plc.press('Start');
      plc.scans(3);
      plc.release('Start');
      plc.scans(3);
      states.add(plc.out('Motor'));
    }
    expect(states, [true, false, true, false]);
  });
}
