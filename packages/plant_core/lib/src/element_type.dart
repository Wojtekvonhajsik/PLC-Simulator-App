import 'model.dart';
import 'params.dart';

final class PortDef {
  const PortDef(this.id, {this.exhaust = false, this.ventsWhenOpen = true});

  /// ISO 5599 port designation: `1`, `2`, `3`, `4`, `5`, or `A`/`B`/`P` for
  /// cylinders and supply.
  final String id;

  /// Exhaust ports (3, 5) are normally left open with a silencer, so an
  /// unconnected exhaust port is not reported.
  final bool exhaust;

  /// An unconnected port is open to atmosphere unless this is false.
  final bool ventsWhenOpen;
}

enum SignalDirection {
  /// Sensor or button contact → PLC input (%I).
  toPlc,

  /// PLC output (%Q) → valve solenoid, lamp, buzzer.
  fromPlc,
}

final class SignalDef {
  const SignalDef(this.id, this.direction, this.label);

  final String id;
  final SignalDirection direction;
  final String label;
}

/// Operator control on an element: button, switch, manual override.
final class ControlDef {
  const ControlDef(this.id, this.label, {this.latching = false});

  final String id;
  final String label;

  /// Latching controls keep their state (switch, lever, emergency stop);
  /// momentary ones are active only while held.
  final bool latching;
}

enum ElementCategory { supply, valve, actuator, flowControl, sensor, operatorControl, indicator }

/// State of a pneumatic line as seen from a port.
enum LineState {
  /// Connected to the air supply.
  supplied,

  /// Open to atmosphere.
  vented,

  /// Supply connected directly to atmosphere — a leak. Has no usable pressure.
  shorted,

  /// Closed on all sides, compressed air trapped inside.
  trappedPressure,

  /// Closed on all sides, no pressure.
  trappedEmpty;

  bool get hasPressure => this == supplied || this == trappedPressure;
  bool get canDrive => this == supplied;
  bool get canExhaust => this == vented || this == shorted;
}

/// Read access to a cylinder for mounted sensors.
abstract interface class CylinderView {
  /// 0 = fully retracted, 1 = fully extended.
  double get position;
  double get strokeMm;
  bool get magneticPiston;
}

/// What a behavior may read from the running simulation.
abstract interface class SimView {
  LineState line(PortRef port);
  CylinderView? cylinder(String elementId);
  SensorMount? mountOf(String sensorId);

  /// Speed factor (0…1] caused by flow control valves in the line of a
  /// cylinder port, for air flowing into ([filling]) or out of the chamber.
  double flowFactor(String cylinderId, String port, {required bool filling});
}

/// Element instance in a running simulation: resolved params and current
/// signal and control values.
final class ElementRuntime {
  ElementRuntime(this.element, this.type, this.params)
      : signals = {for (final s in type.signals(params)) s.id: false},
        controls = {for (final c in type.controls(params)) c.id: false};

  final PlantElement element;
  final ElementType type;
  final ParamValues params;
  final Map<String, bool> signals;
  final Map<String, bool> controls;
  late final ElementBehavior behavior = type.createBehavior(this);

  String get id => element.id;

  bool signal(String id) => signals[id] ?? false;
  bool control(String id) => controls[id] ?? false;
}

/// Simulation logic of one element. A step runs in phases for all elements:
/// [actuate] → line solving (uses [passages], [isSource]) → [move] → [sense].
abstract base class ElementBehavior {
  ElementBehavior(this.element);

  final ElementRuntime element;

  /// Update switching state (valve position) from signals and controls.
  void actuate() {}

  /// Internal pneumatic connections in the current state.
  void passages(void Function(String a, String b) connect) {}

  bool isSource(String port) => false;

  /// Update motion (cylinders) from line states.
  void move(SimView sim, int dtMs) {}

  /// Update output signals (sensors, buttons).
  void sense(SimView sim) {}
}

/// Type of element available in the palette. One type, two renderers in the app.
abstract base class ElementType {
  const ElementType();

  String get id;

  /// Palette label (Polish).
  String get label;
  ElementCategory get category;
  List<ParamDef> get params => const [];
  List<PortDef> get ports => const [];
  List<SignalDef> signals(ParamValues params) => const [];
  List<ControlDef> controls(ParamValues params) => const [];

  /// True for sensors that are mounted on a cylinder body.
  bool get mountable => false;

  ElementBehavior createBehavior(ElementRuntime element);
}
