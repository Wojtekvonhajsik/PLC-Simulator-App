import 'model.dart';

/// Concise construction of plant models — used by tests and built-in templates.
///
/// ```dart
/// final p = PlantBuilder()
///   ..element('S', 'air_supply')
///   ..element('1V1', 'valve_5_2', io: {'14': '%Q0.0'})
///   ..element('1A', 'cylinder_double')
///   ..connect('S.P', '1V1.1')
///   ..connect('1V1.4', '1A.A')
///   ..connect('1V1.2', '1A.B');
/// final model = p.build();
/// ```
final class PlantBuilder {
  final _elements = <PlantElement>[];
  final _connections = <Connection>[];
  final _mounts = <SensorMount>[];

  void element(
    String id,
    String type, {
    String label = '',
    Map<String, Object?> params = const {},
    Map<String, String> io = const {},
  }) =>
      _elements.add(PlantElement(id: id, type: type, label: label, params: params, io: io));

  /// Connects two ports given as `element.port`.
  void connect(String from, String to) =>
      _connections.add(Connection('c${_connections.length}', _port(from), _port(to)));

  void mount(String sensorId, String cylinderId, double position) =>
      _mounts.add(SensorMount(sensorId: sensorId, cylinderId: cylinderId, position: position));

  PlantModel build() => PlantModel(
        elements: List.unmodifiable(_elements),
        connections: List.unmodifiable(_connections),
        mounts: List.unmodifiable(_mounts),
      );

  static PortRef _port(String text) {
    final dot = text.lastIndexOf('.');
    if (dot <= 0 || dot == text.length - 1) throw FormatException('Expected element.port', text);
    return PortRef(text.substring(0, dot), text.substring(dot + 1));
  }
}
