import 'package:plant_core/plant_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  List<PlantDiagnosticCode> errors(PlantBuilder p) => [for (final d in buildPlant(p.build()).errors) d.code];
  List<PlantDiagnosticCode> warnings(PlantBuilder p) => [for (final d in buildPlant(p.build()).warnings) d.code];

  test('complete, bound circuit has no diagnostics', () {
    final result = buildPlant((PlantBuilder()
          ..element('S', 'air_supply')
          ..element('V', 'valve_5_2', io: {'14': '%Q0.0'})
          ..element('C', 'cylinder_double')
          ..element('B1', 'reed_switch', io: {'out': '%I0.0'})
          ..connect('S.P', 'V.1')
          ..connect('V.4', 'C.A')
          ..connect('V.2', 'C.B')
          ..mount('B1', 'C', 0))
        .build());
    expect(result.diagnostics, isEmpty);
    expect(result.simulator, isNotNull);
  });

  group('elements', () {
    test('duplicate id and unknown type', () {
      expect(
          errors(PlantBuilder()
            ..element('X', 'lamp')
            ..element('X', 'lamp')
            ..element('Y', 'teleporter')),
          [PlantDiagnosticCode.duplicateId, PlantDiagnosticCode.unknownType]);
    });

    test('invalid parameters', () {
      final p = PlantBuilder()
        ..element('C', 'cylinder_double', params: {'stroke_mm': 5, 'magnetic_piston': 'yes', 'color': 'red'})
        ..element('V', 'valve_5_2', params: {'actuation': 'telepathy'});
      expect(errors(p), List.filled(4, PlantDiagnosticCode.invalidParam));
      expect(buildPlant(p.build()).simulator, isNull);
    });

    test('io bindings must name existing signals', () {
      expect(errors(PlantBuilder()..element('H', 'lamp', io: {'out': '%Q0.0'})), [PlantDiagnosticCode.unknownSignal]);
      expect(warnings(PlantBuilder()..element('H', 'lamp')), [PlantDiagnosticCode.unboundSignal]);
      expect(warnings(PlantBuilder()..element('H', 'lamp', io: {'in': ''})), [PlantDiagnosticCode.unboundSignal]);
    });
  });

  group('connections', () {
    PlantBuilder base() => PlantBuilder()
      ..element('S', 'air_supply')
      ..element('PS', 'pressure_switch', io: {'out': '%I0.0'});

    test('unknown element and port', () {
      expect(errors(base()..connect('S.P', 'Q.1')), [PlantDiagnosticCode.unknownElement]);
      expect(errors(base()..connect('S.P', 'PS.7')), [PlantDiagnosticCode.unknownPort]);
    });

    test('connection to an invalid element is reported only once', () {
      expect(
          errors(base()
            ..element('Z', 'teleporter')
            ..connect('S.P', 'Z.1')),
          [PlantDiagnosticCode.unknownType]);
    });

    test('self connection', () {
      expect(errors(base()..connect('PS.1', 'PS.1')), contains(PlantDiagnosticCode.selfConnection));
    });

    test('duplicate connection is a warning', () {
      expect(
          warnings(base()
            ..connect('S.P', 'PS.1')
            ..connect('PS.1', 'S.P')),
          [PlantDiagnosticCode.duplicateConnection]);
    });

    test('unconnected ports are reported, open exhausts are not', () {
      final w = buildPlant((base()..element('V', 'valve_3_2_nc', params: {'actuation': Actuation.button})).build())
          .warnings
          .where((d) => d.code == PlantDiagnosticCode.unconnectedPort)
          .map((d) => d.message)
          .toList();
      expect(w, hasLength(4)); // S.P, PS.1, V.1, V.2 — not V.3
      expect(w.any((m) => m.contains('Port 3')), isFalse);
    });

    test('no air supply', () {
      expect(warnings(PlantBuilder()..element('C', 'cylinder_single')),
          containsAll([PlantDiagnosticCode.noAirSupply, PlantDiagnosticCode.unconnectedPort]));
      expect(warnings(PlantBuilder()..element('H', 'lamp', io: {'in': '%Q0.0'})), isEmpty);
    });
  });

  group('mounts', () {
    PlantBuilder base() => PlantBuilder()
      ..element('C', 'cylinder_double')
      ..element('B', 'reed_switch')
      ..element('H', 'lamp');

    test('only mountable sensors on cylinders', () {
      expect(errors(base()..mount('H', 'C', 0)), [PlantDiagnosticCode.sensorNotMountable]);
      expect(errors(base()..mount('B', 'H', 0)), [PlantDiagnosticCode.mountTargetNotCylinder]);
      expect(errors(base()..mount('B', 'Nope', 0)), [PlantDiagnosticCode.unknownElement]);
    });

    test('position within the stroke, one mount per sensor', () {
      expect(errors(base()..mount('B', 'C', 1.2)), [PlantDiagnosticCode.mountPositionOutOfRange]);
      expect(
          errors(base()
            ..mount('B', 'C', 0)
            ..mount('B', 'C', 1)),
          [PlantDiagnosticCode.sensorMountedTwice]);
    });

    test('unmounted sensor is a warning and stays inactive', () {
      final p = base();
      expect(warnings(p), contains(PlantDiagnosticCode.unmountedSensor));
      final sim = buildPlant(p.build()).simulator!;
      sim.step(10);
      expect(sim.sensor('B')!.active, isFalse);
    });
  });

  test('messages use element labels', () {
    final d = buildPlant((PlantBuilder()..element('x1', 'reed_switch', label: '1B1', io: {'out': '%I0.0'})).build())
        .warnings
        .single;
    expect(d.message, contains('1B1'));
    expect(d.elementId, 'x1');
  });

  test('catalog lists every type with unique ids', () {
    final ids = ElementCatalog.standard.types.map((t) => t.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
    expect(ids, containsAll(['valve_5_2', 'cylinder_double', 'reed_switch', 'inductive_sensor', 'lamp']));
    expect(port('a.b.c'), const PortRef('a.b', 'c'));
  });
}
