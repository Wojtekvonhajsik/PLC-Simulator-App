enum Severity { error, warning }

enum DiagnosticCode {
  invalidTagName,
  duplicateTagName,
  invalidAddress,
  addressOutOfRange,
  duplicateTagAddress,
  duplicateId,
  emptyOperand,
  unknownOperand,
  invalidLiteral,
  typeMismatch,
  writeToInput,
  readOnlyOperand,
  edgeMemoryNotMarker,
  edgeMemoryReused,
  doubleCoil,
  invalidInstanceName,
  instanceKindConflict,
  instanceNameCollision,
  instanceCalledTwice,
  unknownInstance,
  unknownMember,
  negativeTime,
  unsupportedInput,
  singleBranch,
  emptyBranch,
  networkIncomplete,
}

/// Compiler message. [message] is user-facing text (Polish).
final class Diagnostic {
  const Diagnostic(
    this.severity,
    this.code,
    this.message, {
    this.networkId,
    this.elementId,
    this.tagName,
  });

  final Severity severity;
  final DiagnosticCode code;
  final String message;
  final String? networkId;
  final String? elementId;
  final String? tagName;

  bool get isError => severity == Severity.error;

  @override
  String toString() {
    final where = [
      if (networkId != null) 'network=$networkId',
      if (elementId != null) 'element=$elementId',
      if (tagName != null) 'tag=$tagName',
    ].join(' ');
    return '${severity.name} ${code.name}: $message${where.isEmpty ? '' : ' ($where)'}';
  }
}
