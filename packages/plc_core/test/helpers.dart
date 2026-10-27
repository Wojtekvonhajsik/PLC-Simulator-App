import 'package:plc_core/plc_core.dart';
import 'package:test/test.dart';

const standardTags = [
  Tag(name: 'Start', address: '%I0.0'),
  Tag(name: 'Stop', address: '%I0.1'),
  Tag(name: 'Sensor', address: '%I0.2'),
  Tag(name: 'Reset', address: '%I0.3'),
  Tag(name: 'Motor', address: '%Q0.0'),
  Tag(name: 'Lamp', address: '%Q0.1'),
  Tag(name: 'Horn', address: '%Q0.2'),
  Tag(name: 'Flag', address: '%M0.0'),
];

CompileResult compileNetworks(List<Network> networks, {List<Tag> tags = standardTags}) =>
    compile(Program(networks), tags: tags);

/// Compiles without errors and starts the runtime.
PlcRuntime runtimeFor(List<Network> networks, {List<Tag> tags = standardTags}) {
  final result = compileNetworks(networks, tags: tags);
  expect(result.errors, isEmpty, reason: result.diagnostics.join('\n'));
  return PlcRuntime(result.program!)..start();
}

extension RuntimeTestX on PlcRuntime {
  void scans(int count, {int cycleMs = 10}) {
    for (var i = 0; i < count; i++) {
      scan(cycleMs: cycleMs);
    }
  }

  void press(String tag) => setInputByTag(tag, true);
  void release(String tag) => setInputByTag(tag, false);
  bool out(String tag) => outputByTag(tag);
}
