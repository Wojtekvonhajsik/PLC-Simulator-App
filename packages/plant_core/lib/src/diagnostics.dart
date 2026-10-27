enum Severity { error, warning }

enum PlantDiagnosticCode {
  duplicateId,
  unknownType,
  invalidParam,
  unknownElement,
  unknownPort,
  selfConnection,
  duplicateConnection,
  unconnectedPort,
  unknownSignal,
  unboundSignal,
  mountTargetNotCylinder,
  sensorNotMountable,
  sensorMountedTwice,
  mountPositionOutOfRange,
  unmountedSensor,
  reedWithoutMagnet,
  noAirSupply,
}

/// Schematic validation message. [message] is user-facing text (Polish).
final class PlantDiagnostic {
  const PlantDiagnostic(this.severity, this.code, this.message, {this.elementId, this.connectionId});

  final Severity severity;
  final PlantDiagnosticCode code;
  final String message;
  final String? elementId;
  final String? connectionId;

  bool get isError => severity == Severity.error;

  @override
  String toString() {
    final where = [
      if (elementId != null) 'element=$elementId',
      if (connectionId != null) 'connection=$connectionId',
    ].join(' ');
    return '${severity.name} ${code.name}: $message${where.isEmpty ? '' : ' ($where)'}';
  }
}
