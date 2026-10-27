/// Plant document: elements, pneumatic connections and sensor mounts.
/// Shared by the pictorial and symbolic views — layouts are stored elsewhere.
library;

final class PlantElement {
  const PlantElement({
    required this.id,
    required this.type,
    this.label = '',
    this.params = const {},
    this.io = const {},
  });

  final String id;

  /// Element type id from the catalog, e.g. `valve_5_2`.
  final String type;

  /// User label, e.g. `1A` or `1V1`.
  final String label;
  final Map<String, Object?> params;

  /// Electrical signal → PLC address as entered by the user, e.g. `{'14': '%Q0.0'}`.
  /// Addresses are validated together with the PLC program.
  final Map<String, String> io;
}

/// A pneumatic port of an element, e.g. `1V1.4`.
final class PortRef {
  const PortRef(this.elementId, this.port);

  final String elementId;
  final String port;

  @override
  bool operator ==(Object other) => other is PortRef && other.elementId == elementId && other.port == port;

  @override
  int get hashCode => Object.hash(elementId, port);

  @override
  String toString() => '$elementId.$port';
}

/// Pneumatic tube between two ports. A port may have several tubes (branching).
final class Connection {
  const Connection(this.id, this.from, this.to);

  final String id;
  final PortRef from;
  final PortRef to;
}

/// Sensor attached to a cylinder body at [position] of the stroke
/// (0 = fully retracted, 1 = fully extended).
final class SensorMount {
  const SensorMount({required this.sensorId, required this.cylinderId, required this.position});

  final String sensorId;
  final String cylinderId;
  final double position;
}

final class PlantModel {
  const PlantModel({this.elements = const [], this.connections = const [], this.mounts = const []});

  final List<PlantElement> elements;
  final List<Connection> connections;
  final List<SensorMount> mounts;
}
