import 'package:plc_core/plc_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  late LadderBuilder b;
  setUp(() => b = LadderBuilder());

  List<DiagnosticCode> codes(CompileResult r, {bool errors = true}) =>
      [for (final d in errors ? r.errors : r.warnings) d.code];

  void expectError(List<Network> networks, DiagnosticCode code, {List<Tag> tags = standardTags}) {
    final result = compileNetworks(networks, tags: tags);
    expect(codes(result), contains(code), reason: result.diagnostics.join('\n'));
    expect(result.program, isNull);
  }

  void expectWarning(List<Network> networks, DiagnosticCode code) {
    final result = compileNetworks(networks);
    expect(result.errors, isEmpty, reason: result.diagnostics.join('\n'));
    expect(codes(result, errors: false), contains(code));
    expect(result.program, isNotNull, reason: 'warnings do not block the download');
  }

  test('valid program compiles without diagnostics', () {
    final result = compileNetworks([
      b.network([b.no('Start'), b.coil('Motor')]),
      b.network([]), // empty networks are allowed
    ]);
    expect(result.diagnostics, isEmpty);
    expect(result.program!.networks, hasLength(1));
    expect(result.program!.addressOf('START'), BitAddress.parse('%I0.0'));
  });

  group('tag table', () {
    test('invalid, duplicate and out-of-range tags', () {
      final result = compile(const Program([]), tags: const [
        Tag(name: '1A', address: '%I0.0'),
        Tag(name: 'A', address: '%I0.0'),
        Tag(name: 'a', address: '%I0.1'),
        Tag(name: 'B', address: '%IW0'),
        Tag(name: 'C', address: '%M999.0'),
        Tag(name: 'D', address: '%I0.0'),
      ]);
      expect(codes(result), [
        DiagnosticCode.invalidTagName,
        DiagnosticCode.duplicateTagName,
        DiagnosticCode.invalidAddress,
        DiagnosticCode.addressOutOfRange,
      ]);
      expect(codes(result, errors: false), [DiagnosticCode.duplicateTagAddress]);
      expect(result.errors.first.tagName, '1A');
    });
  });

  group('operands', () {
    test(
        'unknown tag',
        () => expectError([
              b.network([b.no('Nope'), b.coil('Motor')])
            ], DiagnosticCode.unknownOperand));
    test(
        'empty operand',
        () => expectError([
              b.network([b.no(' '), b.coil('Motor')])
            ], DiagnosticCode.emptyOperand));
    test(
        'malformed address',
        () => expectError([
              b.network([b.no('%I0.9'), b.coil('Motor')])
            ], DiagnosticCode.invalidAddress));
    test(
        'address out of range',
        () => expectError([
              b.network([b.no('%I100.0'), b.coil('Motor')])
            ], DiagnosticCode.addressOutOfRange));
    test(
        'coil on an input',
        () => expectError([
              b.network([b.no('Start'), b.coil('Stop')])
            ], DiagnosticCode.writeToInput));
    test(
        'coil on a constant',
        () => expectError([
              b.network([b.no('Start'), b.coil('TRUE')])
            ], DiagnosticCode.readOnlyOperand));
    test('coil on a timer member', () {
      expectError([
        b.network([b.no('Start'), b.ton('T1', 'T#1s')]),
        b.network([b.no('Start'), b.coil('T1.Q')]),
      ], DiagnosticCode.readOnlyOperand);
    });
    test(
        'INT used as a contact',
        () => expectError([
              b.network([b.no('5'), b.coil('Motor')])
            ], DiagnosticCode.typeMismatch));
    test('INT out of range', () {
      expectError([
        b.network([b.no('Start'), b.ctu('C1', '40000')])
      ], DiagnosticCode.invalidLiteral);
    });
    test('malformed time', () {
      expectError([
        b.network([b.no('Start'), b.ton('T1', 'T#5x')])
      ], DiagnosticCode.invalidLiteral);
    });
  });

  group('instances', () {
    test('PT must be TIME, PV must be INT', () {
      expectError([
        b.network([b.no('Start'), b.ton('T1', '5')])
      ], DiagnosticCode.typeMismatch);
      expectError([
        b.network([b.no('Start'), b.ctu('C1', 'T#5s')])
      ], DiagnosticCode.typeMismatch);
      expectError([
        b.network([b.no('Start'), b.ctu('C1', 'Stop')])
      ], DiagnosticCode.typeMismatch);
    });

    test('negative PT', () {
      expectError([
        b.network([b.no('Start'), b.ton('T1', '-T#1s')])
      ], DiagnosticCode.negativeTime);
    });

    test('unknown instance and member', () {
      expectError([
        b.network([b.no('T9.Q'), b.coil('Motor')])
      ], DiagnosticCode.unknownInstance);
      expectError([
        b.network([b.no('Start'), b.ton('T1', 'T#1s')]),
        b.network([b.no('T1.CV'), b.coil('Motor')]),
      ], DiagnosticCode.unknownMember);
      expectError([
        b.network([b.no('Start'), b.ctud('C1', '1')]),
        b.network([b.no('C1.Q'), b.coil('Motor')]),
      ], DiagnosticCode.unknownMember);
    });

    test('member used with the wrong type', () {
      expectError([
        b.network([b.no('Start'), b.ton('T1', 'T#1s')]),
        b.network([b.no('T1.ET'), b.coil('Motor')]),
      ], DiagnosticCode.typeMismatch);
    });

    test('invalid instance name and collision with a tag', () {
      expectError([
        b.network([b.no('Start'), b.ton('1T', 'T#1s')])
      ], DiagnosticCode.invalidInstanceName);
      expectError([
        b.network([b.no('Start'), b.ton('Motor', 'T#1s')])
      ], DiagnosticCode.instanceNameCollision);
    });

    test('one instance used by different box types', () {
      expectError([
        b.network([b.no('Start'), b.ton('X', 'T#1s')]),
        b.network([b.no('Start'), b.ctu('X', '1')]),
      ], DiagnosticCode.instanceKindConflict);
    });

    test('inputs not available on the box', () {
      expectError([
        b.network([b.no('Start'), TimerBox('t', TimerKind.ton, 'T1', 'T#1s', reset: 'Reset')]),
      ], DiagnosticCode.unsupportedInput);
      expectError([
        b.network([b.no('Start'), CounterBox('c', CounterKind.ctu, 'C1', '1', load: 'Reset')]),
      ], DiagnosticCode.unsupportedInput);
    });

    test('instance called twice is a warning', () {
      expectWarning([
        b.network([b.no('Start'), b.ton('T1', 'T#1s')]),
        b.network([b.no('Stop'), b.ton('T1', 'T#1s')]),
      ], DiagnosticCode.instanceCalledTwice);
    });
  });

  group('comparators', () {
    test('operands must have the same type', () {
      expectError([
        b.network([b.compare('5', CompareOp.equal, 'T#5s'), b.coil('Motor')]),
      ], DiagnosticCode.typeMismatch);
      expectError([
        b.network([b.inRange('1', 'T#5s', '3'), b.coil('Motor')]),
      ], DiagnosticCode.typeMismatch);
    });

    test('BOOL operand is rejected', () {
      expectError([
        b.network([b.compare('Start', CompareOp.equal, '1'), b.coil('Motor')]),
      ], DiagnosticCode.typeMismatch);
    });
  });

  group('edges', () {
    test('memory bit must be in %M', () {
      expectError([
        b.network([b.posEdge('Start', '%Q5.0'), b.coil('Motor')]),
      ], DiagnosticCode.edgeMemoryNotMarker);
      expectError([
        b.network([b.posEdge('Start', 'Stop'), b.coil('Motor')]),
      ], DiagnosticCode.writeToInput);
    });

    test('reused memory bit is a warning', () {
      expectWarning([
        b.network([b.posEdge('Start', '%M5.0'), b.coil('Motor')]),
        b.network([b.no('Stop'), b.pTrig('%M5.0'), b.coil('Lamp')]),
      ], DiagnosticCode.edgeMemoryReused);
    });
  });

  group('structure', () {
    test('network must end with a coil or box', () {
      expectError([
        b.network([b.no('Start')])
      ], DiagnosticCode.networkIncomplete);
      expectError([
        b.network([b.no('Start'), b.coil('Motor'), b.no('Stop')]),
      ], DiagnosticCode.networkIncomplete);
      expectError([
        b.network([
          b.no('Start'),
          b.parallel([
            [b.coil('Motor')],
            [b.no('Stop')],
          ]),
        ]),
      ], DiagnosticCode.networkIncomplete);
    });

    test('box at the end is a complete network', () {
      final result = compileNetworks([
        b.network([b.no('Start'), b.ton('T1', 'T#1s')])
      ]);
      expect(result.errors, isEmpty);
    });

    test('duplicate element ids', () {
      expectError([
        Network(
            id: 'n1',
            rung: Series('s1', [
              Contact('x', ContactKind.normallyOpen, 'Start'),
              Coil('x', CoilKind.assign, 'Motor'),
            ])),
      ], DiagnosticCode.duplicateId);
    });

    test('single and empty branches are warnings', () {
      expectWarning([
        b.network([
          b.parallel([
            [b.no('Start')],
          ]),
          b.coil('Motor'),
        ]),
      ], DiagnosticCode.singleBranch);
      expectWarning([
        b.network([
          b.parallel([
            [b.no('Start')],
            [],
          ]),
          b.coil('Motor'),
        ]),
      ], DiagnosticCode.emptyBranch);
    });

    test('diagnostics point to network and element', () {
      final contact = b.no('Nope');
      final network = b.network([contact, b.coil('Motor')]);
      final error = compileNetworks([network]).errors.single;
      expect(error.networkId, network.id);
      expect(error.elementId, contact.id);
      expect(error.message, contains('Nope'));
    });
  });
}
