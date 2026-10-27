import 'package:plant_core/plant_core.dart';
import 'package:test/test.dart';

/// Builds without errors.
PlantSimulator simulatorFor(PlantBuilder plant) {
  final result = buildPlant(plant.build());
  expect(result.errors, isEmpty, reason: result.diagnostics.join('\n'));
  return result.simulator!;
}

PortRef port(String text) {
  final dot = text.lastIndexOf('.');
  return PortRef(text.substring(0, dot), text.substring(dot + 1));
}

/// Supply → valve 1V1 → double-acting cylinder 1A (1 s each way) with reed
/// switches 1B1 (retracted) and 1B2 (extended).
PlantBuilder cylinderCircuit({String valve = 'valve_5_2', Map<String, Object?> valveParams = const {}}) =>
    PlantBuilder()
      ..element('S', 'air_supply')
      ..element('1V1', valve, params: valveParams)
      ..element('1A', 'cylinder_double')
      ..element('1B1', 'reed_switch')
      ..element('1B2', 'reed_switch')
      ..connect('S.P', '1V1.1')
      ..connect('1V1.4', '1A.A')
      ..connect('1V1.2', '1A.B')
      ..mount('1B1', '1A', 0)
      ..mount('1B2', '1A', 1);

extension PlantTestX on PlantSimulator {
  void run(int ms, {int dt = 10}) {
    for (var t = 0; t < ms; t += dt) {
      step(dt);
    }
  }

  double pos(String cylinder) => this.cylinder(cylinder)!.position;
  LineState at(String ref) => line(port(ref));
  bool out(String sensor) => signal(sensor, 'out');
}
