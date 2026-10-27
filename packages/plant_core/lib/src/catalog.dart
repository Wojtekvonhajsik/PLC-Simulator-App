import 'dart:math';

import 'element_type.dart';
import 'model.dart';
import 'params.dart';

const _contactParam =
    ChoiceParam('contact', 'Styk', options: {'no': 'NO (zwierny)', 'nc': 'NC (rozwierny)'}, defaultValue: 'no');

bool _contact(ParamValues params, bool active) => params.choice('contact') == 'no' ? active : !active;

const _out = SignalDef('out', SignalDirection.toPlc, 'Wyjście');
const _in = SignalDef('in', SignalDirection.fromPlc, 'Wejście');

// ------------------------------------------------------------------ supply

final class AirSupplyType extends ElementType {
  const AirSupplyType();

  @override
  String get id => 'air_supply';
  @override
  String get label => 'Źródło sprężonego powietrza';
  @override
  ElementCategory get category => ElementCategory.supply;
  @override
  List<PortDef> get ports => const [PortDef('P', ventsWhenOpen: false)];

  @override
  ElementBehavior createBehavior(ElementRuntime element) => _SourceBehavior(element);
}

final class _SourceBehavior extends ElementBehavior {
  _SourceBehavior(super.element);

  @override
  bool isSource(String port) => true;
}

/// Pass-through element with two ports (service unit, tube fittings).
final class ServiceUnitType extends ElementType {
  const ServiceUnitType();

  @override
  String get id => 'service_unit';
  @override
  String get label => 'Zespół przygotowania powietrza';
  @override
  ElementCategory get category => ElementCategory.supply;
  @override
  List<PortDef> get ports => const [PortDef('1'), PortDef('2')];

  @override
  ElementBehavior createBehavior(ElementRuntime element) => _PassThroughBehavior(element);
}

final class _PassThroughBehavior extends ElementBehavior {
  _PassThroughBehavior(super.element);

  @override
  void passages(void Function(String a, String b) connect) => connect('1', '2');
}

// ------------------------------------------------------------------ valves

typedef Passage = (String, String);

/// Directional control valve described by its switching positions.
final class ValveSpec {
  const ValveSpec({
    required this.id,
    required this.label,
    required this.ports,
    required this.positions,
    required this.sideA,
    required this.sideB,
  });

  final String id;
  final String label;
  final List<String> ports;

  /// Two positions: `[rest (side B), actuated (side A)]`.
  /// Three positions: `[center, side A, side B]`.
  final List<List<Passage>> positions;

  /// ISO 5599 designation of the actuator that selects position A, e.g. `14`.
  final String sideA;

  /// Designation of the actuator (or spring) that selects the rest/B position, e.g. `12`.
  final String sideB;

  bool get threePosition => positions.length == 3;
}

const valve32nc = ValveSpec(
  id: 'valve_3_2_nc',
  label: 'Zawór 3/2 normalnie zamknięty',
  ports: ['1', '2', '3'],
  positions: [
    [('2', '3')],
    [('1', '2')],
  ],
  sideA: '12',
  sideB: '10',
);

const valve32no = ValveSpec(
  id: 'valve_3_2_no',
  label: 'Zawór 3/2 normalnie otwarty',
  ports: ['1', '2', '3'],
  positions: [
    [('1', '2')],
    [('2', '3')],
  ],
  sideA: '10',
  sideB: '12',
);

const valve52 = ValveSpec(
  id: 'valve_5_2',
  label: 'Zawór 5/2',
  ports: ['1', '2', '3', '4', '5'],
  positions: [
    [('1', '2'), ('4', '5')],
    [('1', '4'), ('2', '3')],
  ],
  sideA: '14',
  sideB: '12',
);

const _sideA53 = [('1', '4'), ('2', '3')];
const _sideB53 = [('1', '2'), ('4', '5')];

const valve53closed = ValveSpec(
  id: 'valve_5_3_closed',
  label: 'Zawór 5/3, środek zamknięty',
  ports: ['1', '2', '3', '4', '5'],
  positions: [[], _sideA53, _sideB53],
  sideA: '14',
  sideB: '12',
);

const valve53exhausted = ValveSpec(
  id: 'valve_5_3_exhausted',
  label: 'Zawór 5/3, środek odpowietrzony',
  ports: ['1', '2', '3', '4', '5'],
  positions: [
    [('2', '3'), ('4', '5')],
    _sideA53,
    _sideB53,
  ],
  sideA: '14',
  sideB: '12',
);

const valve53pressurized = ValveSpec(
  id: 'valve_5_3_pressurized',
  label: 'Zawór 5/3, środek zasilony',
  ports: ['1', '2', '3', '4', '5'],
  positions: [
    [('1', '2'), ('1', '4')],
    _sideA53,
    _sideB53,
  ],
  sideA: '14',
  sideB: '12',
);

/// How a two-position valve is actuated.
abstract final class Actuation {
  /// Solenoid on side A, spring return. Manual override on the solenoid.
  static const monostable = 'solenoid_spring';

  /// Solenoids on both sides, keeps its position when both are off.
  static const bistable = 'solenoid_solenoid';

  /// Manual push button with spring return.
  static const button = 'button_spring';

  /// Manual lever with detent — stays where it was put.
  static const lever = 'lever_detent';
}

const _actuationParam = ChoiceParam(
  'actuation',
  'Sterowanie',
  options: {
    Actuation.monostable: 'Elektrozawór monostabilny (cewka + sprężyna)',
    Actuation.bistable: 'Elektrozawór bistabilny (dwie cewki)',
    Actuation.button: 'Przycisk ręczny ze sprężyną',
    Actuation.lever: 'Dźwignia z zatrzaskiem',
  },
  defaultValue: Actuation.monostable,
);

final class ValveType extends ElementType {
  const ValveType(this.spec);

  final ValveSpec spec;

  @override
  String get id => spec.id;
  @override
  String get label => spec.label;
  @override
  ElementCategory get category => ElementCategory.valve;
  @override
  List<ParamDef> get params => spec.threePosition ? const [] : const [_actuationParam];
  @override
  List<PortDef> get ports => [for (final p in spec.ports) PortDef(p, exhaust: p == '3' || p == '5')];

  String _actuation(ParamValues params) => spec.threePosition ? Actuation.bistable : params.choice('actuation');

  @override
  List<SignalDef> signals(ParamValues params) {
    final a = SignalDef(spec.sideA, SignalDirection.fromPlc, 'Cewka ${spec.sideA}');
    final b = SignalDef(spec.sideB, SignalDirection.fromPlc, 'Cewka ${spec.sideB}');
    return switch (_actuation(params)) {
      Actuation.monostable => [a],
      Actuation.bistable => [a, b],
      _ => const [],
    };
  }

  @override
  List<ControlDef> controls(ParamValues params) => switch (_actuation(params)) {
        Actuation.monostable => [ControlDef('manual_a', 'Ręczne przesterowanie ${spec.sideA}')],
        Actuation.bistable => [
            ControlDef('manual_a', 'Ręczne przesterowanie ${spec.sideA}'),
            ControlDef('manual_b', 'Ręczne przesterowanie ${spec.sideB}'),
          ],
        Actuation.button => const [ControlDef('button', 'Przycisk')],
        _ => const [ControlDef('lever', 'Dźwignia', latching: true)],
      };

  @override
  ElementBehavior createBehavior(ElementRuntime element) => ValveBehavior(element, spec, _actuation(element.params));
}

final class ValveBehavior extends ElementBehavior {
  ValveBehavior(super.element, this.spec, this.actuation);

  final ValveSpec spec;
  final String actuation;

  /// Index into [ValveSpec.positions].
  int position = 0;

  @override
  void actuate() {
    final e = element;
    switch (actuation) {
      case Actuation.monostable:
        position = e.signal(spec.sideA) || e.control('manual_a') ? 1 : 0;
      case Actuation.button:
        position = e.control('button') ? 1 : 0;
      case Actuation.lever:
        position = e.control('lever') ? 1 : 0;
      default:
        final a = e.signal(spec.sideA) || e.control('manual_a');
        final b = e.signal(spec.sideB) || e.control('manual_b');
        if (spec.threePosition) {
          // Spring centered.
          position = a == b ? 0 : (a ? 1 : 2);
        } else if (a != b) {
          // Bistable: both or none keeps the last position.
          position = a ? 1 : 0;
        }
    }
  }

  @override
  void passages(void Function(String a, String b) connect) {
    for (final (a, b) in spec.positions[position]) {
      connect(a, b);
    }
  }
}

/// One-way flow control valve: flow from port 1 to port 2 is throttled,
/// the check valve lets flow from 2 to 1 pass freely.
final class FlowControlType extends ElementType {
  const FlowControlType();

  @override
  String get id => 'flow_control';
  @override
  String get label => 'Zawór dławiąco-zwrotny';
  @override
  ElementCategory get category => ElementCategory.flowControl;
  @override
  List<PortDef> get ports => const [PortDef('1'), PortDef('2')];
  @override
  List<ParamDef> get params => const [
        NumberParam('opening', 'Otwarcie dławika', defaultValue: 0.5, min: 0.05, max: 1),
        BoolParam('check_valve', 'Zawór zwrotny', defaultValue: true),
      ];

  @override
  ElementBehavior createBehavior(ElementRuntime element) => _PassThroughBehavior(element);
}

// --------------------------------------------------------------- cylinders

final class CylinderType extends ElementType {
  const CylinderType({required this.doubleActing});

  final bool doubleActing;

  @override
  String get id => doubleActing ? 'cylinder_double' : 'cylinder_single';
  @override
  String get label => doubleActing ? 'Siłownik dwustronnego działania' : 'Siłownik jednostronnego działania';
  @override
  ElementCategory get category => ElementCategory.actuator;
  @override
  List<PortDef> get ports => doubleActing ? const [PortDef('A'), PortDef('B')] : const [PortDef('A')];
  @override
  List<ParamDef> get params => const [
        NumberParam('stroke_mm', 'Skok', defaultValue: 100, min: 10, max: 2000, unit: 'mm'),
        NumberParam('extend_ms', 'Czas wysuwu', defaultValue: 1000, min: 50, max: 60000, unit: 'ms'),
        NumberParam('retract_ms', 'Czas wsuwu', defaultValue: 1000, min: 50, max: 60000, unit: 'ms'),
        BoolParam('magnetic_piston', 'Tłok magnetyczny', defaultValue: true),
      ];

  @override
  ElementBehavior createBehavior(ElementRuntime element) => CylinderBehavior(element, doubleActing: doubleActing);
}

enum Motion { stopped, extending, retracting }

/// Clamps to the stroke and removes floating-point residue at the end positions.
double _snap(double position) => position >= 1 - 1e-9
    ? 1
    : position <= 1e-9
        ? 0
        : position;

/// Qualitative cylinder model: constant speed, moves only when the driving
/// chamber is supplied and the opposite one can exhaust. Pressure on both
/// sides holds the piston (differential area effects are not modelled).
final class CylinderBehavior extends ElementBehavior implements CylinderView {
  CylinderBehavior(super.element, {required this.doubleActing});

  final bool doubleActing;

  @override
  double position = 0;
  Motion motion = Motion.stopped;

  @override
  double get strokeMm => element.params.number('stroke_mm');
  @override
  bool get magneticPiston => element.params.boolean('magnetic_piston');

  @override
  void move(SimView sim, int dtMs) {
    final id = element.id;
    final a = sim.line(PortRef(id, 'A'));
    double extendRate = 0;
    double retractRate = 0;
    if (doubleActing) {
      final b = sim.line(PortRef(id, 'B'));
      if (a.canDrive && b.canExhaust) {
        extendRate = min(sim.flowFactor(id, 'A', filling: true), sim.flowFactor(id, 'B', filling: false));
      } else if (b.canDrive && a.canExhaust) {
        retractRate = min(sim.flowFactor(id, 'B', filling: true), sim.flowFactor(id, 'A', filling: false));
      }
    } else if (a.canDrive) {
      extendRate = sim.flowFactor(id, 'A', filling: true);
    } else if (a.canExhaust) {
      retractRate = sim.flowFactor(id, 'A', filling: false); // spring return
    }

    if (extendRate > 0 && position < 1) {
      position = _snap(position + extendRate * dtMs / element.params.number('extend_ms'));
      motion = Motion.extending;
    } else if (retractRate > 0 && position > 0) {
      position = _snap(position - retractRate * dtMs / element.params.number('retract_ms'));
      motion = Motion.retracting;
    } else {
      motion = Motion.stopped;
    }
  }
}

// ----------------------------------------------------------------- sensors

/// Sensor mounted on a cylinder body; switches when the piston (magnet or
/// rod cam) is within [defaultRangeMm] of the mounting position.
final class MountedSensorType extends ElementType {
  const MountedSensorType({
    required this.id,
    required this.label,
    required this.requiresMagnet,
    required this.defaultRangeMm,
  });

  @override
  final String id;
  @override
  final String label;

  /// Reed switches react only to a magnetic piston.
  final bool requiresMagnet;
  final double defaultRangeMm;

  @override
  ElementCategory get category => ElementCategory.sensor;
  @override
  bool get mountable => true;
  @override
  List<ParamDef> get params => [
        _contactParam,
        NumberParam('range_mm', 'Strefa zadziałania (±)', defaultValue: defaultRangeMm, min: 0.5, max: 50, unit: 'mm'),
      ];
  @override
  List<SignalDef> signals(ParamValues params) => const [_out];

  @override
  ElementBehavior createBehavior(ElementRuntime element) => MountedSensorBehavior(element, requiresMagnet);
}

const reedSwitch = MountedSensorType(
  id: 'reed_switch',
  label: 'Kontaktron',
  requiresMagnet: true,
  defaultRangeMm: 3,
);

const inductiveSensor = MountedSensorType(
  id: 'inductive_sensor',
  label: 'Czujnik indukcyjny',
  requiresMagnet: false,
  defaultRangeMm: 2,
);

const limitSwitch = MountedSensorType(
  id: 'limit_switch',
  label: 'Wyłącznik krańcowy',
  requiresMagnet: false,
  defaultRangeMm: 1,
);

abstract base class SensorBehavior extends ElementBehavior {
  SensorBehavior(super.element);

  /// The physical quantity is detected (sensor LED on), regardless of NO/NC.
  bool active = false;

  void setActive(bool value) {
    active = value;
    element.signals['out'] = _contact(element.params, value);
  }
}

final class MountedSensorBehavior extends SensorBehavior {
  MountedSensorBehavior(super.element, this.requiresMagnet);

  final bool requiresMagnet;

  @override
  void sense(SimView sim) {
    final mount = sim.mountOf(element.id);
    final cylinder = mount == null ? null : sim.cylinder(mount.cylinderId);
    if (mount == null || cylinder == null || (requiresMagnet && !cylinder.magneticPiston)) {
      setActive(false);
      return;
    }
    final distanceMm = (cylinder.position - mount.position).abs() * cylinder.strokeMm;
    setActive(distanceMm <= element.params.number('range_mm') + 1e-9);
  }
}

final class PressureSwitchType extends ElementType {
  const PressureSwitchType();

  @override
  String get id => 'pressure_switch';
  @override
  String get label => 'Presostat';
  @override
  ElementCategory get category => ElementCategory.sensor;
  @override
  List<PortDef> get ports => const [PortDef('1')];
  @override
  List<ParamDef> get params => const [_contactParam];
  @override
  List<SignalDef> signals(ParamValues params) => const [_out];

  @override
  ElementBehavior createBehavior(ElementRuntime element) => _PressureSwitchBehavior(element);
}

final class _PressureSwitchBehavior extends SensorBehavior {
  _PressureSwitchBehavior(super.element);

  @override
  void sense(SimView sim) => setActive(sim.line(PortRef(element.id, '1')).hasPressure);
}

// ------------------------------------------------------- operator controls

final class PushButtonType extends ElementType {
  const PushButtonType();

  @override
  String get id => 'push_button';
  @override
  String get label => 'Przycisk';
  @override
  ElementCategory get category => ElementCategory.operatorControl;
  @override
  List<ParamDef> get params => const [
        _contactParam,
        ChoiceParam('color', 'Kolor',
            options: {'green': 'zielony', 'red': 'czerwony', 'black': 'czarny', 'yellow': 'żółty', 'blue': 'niebieski'},
            defaultValue: 'green'),
      ];
  @override
  List<SignalDef> signals(ParamValues params) => const [_out];
  @override
  List<ControlDef> controls(ParamValues params) => const [ControlDef('press', 'Naciśnij')];

  @override
  ElementBehavior createBehavior(ElementRuntime element) => _ContactBehavior(element, 'press');
}

final class SelectorSwitchType extends ElementType {
  const SelectorSwitchType();

  @override
  String get id => 'selector_switch';
  @override
  String get label => 'Przełącznik';
  @override
  ElementCategory get category => ElementCategory.operatorControl;
  @override
  List<ParamDef> get params => const [_contactParam];
  @override
  List<SignalDef> signals(ParamValues params) => const [_out];
  @override
  List<ControlDef> controls(ParamValues params) => const [ControlDef('on', 'Załącz', latching: true)];

  @override
  ElementBehavior createBehavior(ElementRuntime element) => _ContactBehavior(element, 'on');
}

/// Emergency stop: latching, always an NC contact (signal 1 = not pressed).
final class EmergencyStopType extends ElementType {
  const EmergencyStopType();

  @override
  String get id => 'emergency_stop';
  @override
  String get label => 'Wyłącznik bezpieczeństwa';
  @override
  ElementCategory get category => ElementCategory.operatorControl;
  @override
  List<SignalDef> signals(ParamValues params) => const [_out];
  @override
  List<ControlDef> controls(ParamValues params) => const [ControlDef('pressed', 'Wciśnięty', latching: true)];

  @override
  ElementBehavior createBehavior(ElementRuntime element) => _EmergencyStopBehavior(element);
}

final class _ContactBehavior extends ElementBehavior {
  _ContactBehavior(super.element, this.control);

  final String control;

  @override
  void sense(SimView sim) => element.signals['out'] = _contact(element.params, element.control(control));
}

final class _EmergencyStopBehavior extends ElementBehavior {
  _EmergencyStopBehavior(super.element);

  @override
  void sense(SimView sim) => element.signals['out'] = !element.control('pressed');
}

// -------------------------------------------------------------- indicators

final class LampType extends ElementType {
  const LampType();

  @override
  String get id => 'lamp';
  @override
  String get label => 'Lampka';
  @override
  ElementCategory get category => ElementCategory.indicator;
  @override
  List<ParamDef> get params => const [
        ChoiceParam('color', 'Kolor',
            options: {'green': 'zielona', 'red': 'czerwona', 'yellow': 'żółta', 'white': 'biała', 'blue': 'niebieska'},
            defaultValue: 'green'),
      ];
  @override
  List<SignalDef> signals(ParamValues params) => const [_in];

  @override
  ElementBehavior createBehavior(ElementRuntime element) => IndicatorBehavior(element);
}

final class BuzzerType extends ElementType {
  const BuzzerType();

  @override
  String get id => 'buzzer';
  @override
  String get label => 'Brzęczyk';
  @override
  ElementCategory get category => ElementCategory.indicator;
  @override
  List<SignalDef> signals(ParamValues params) => const [_in];

  @override
  ElementBehavior createBehavior(ElementRuntime element) => IndicatorBehavior(element);
}

final class IndicatorBehavior extends ElementBehavior {
  IndicatorBehavior(super.element);

  bool get isOn => element.signal('in');
}

// ----------------------------------------------------------------- catalog

final class ElementCatalog {
  ElementCatalog(Iterable<ElementType> types) : _types = {for (final t in types) t.id: t};

  final Map<String, ElementType> _types;

  ElementType? operator [](String id) => _types[id];
  Iterable<ElementType> get types => _types.values;

  static final standard = ElementCatalog(const [
    AirSupplyType(),
    ServiceUnitType(),
    ValveType(valve32nc),
    ValveType(valve32no),
    ValveType(valve52),
    ValveType(valve53closed),
    ValveType(valve53exhausted),
    ValveType(valve53pressurized),
    FlowControlType(),
    CylinderType(doubleActing: false),
    CylinderType(doubleActing: true),
    reedSwitch,
    inductiveSensor,
    limitSwitch,
    PressureSwitchType(),
    PushButtonType(),
    SelectorSwitchType(),
    EmergencyStopType(),
    LampType(),
    BuzzerType(),
  ]);
}
