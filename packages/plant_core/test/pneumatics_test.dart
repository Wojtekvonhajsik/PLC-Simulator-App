import 'package:plant_core/plant_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('5/2 monostable + double-acting cylinder', () {
    test('rest position keeps the cylinder retracted', () {
      final sim = simulatorFor(cylinderCircuit());
      expect(sim.at('S.P'), LineState.supplied);
      expect(sim.at('1A.B'), LineState.supplied);
      expect(sim.at('1A.A'), LineState.vented, reason: 'A exhausts through 4→5');
      sim.run(500);
      expect(sim.pos('1A'), 0);
      expect(sim.out('1B1'), isTrue);
      expect(sim.out('1B2'), isFalse);
    });

    test('solenoid 14 extends, spring returns', () {
      final sim = simulatorFor(cylinderCircuit());
      sim.setSignal('1V1', '14', true);
      sim.run(500);
      expect(sim.valve('1V1')!.position, 1);
      expect(sim.at('1A.A'), LineState.supplied);
      expect(sim.at('1A.B'), LineState.vented);
      expect(sim.pos('1A'), closeTo(0.5, 1e-9));
      expect(sim.cylinder('1A')!.motion, Motion.extending);
      expect(sim.out('1B1'), isFalse);
      expect(sim.out('1B2'), isFalse);

      sim.run(500);
      expect(sim.pos('1A'), closeTo(1, 1e-9));
      expect(sim.out('1B2'), isTrue);
      sim.step(10);
      expect(sim.cylinder('1A')!.motion, Motion.stopped, reason: 'end of stroke');

      sim.setSignal('1V1', '14', false);
      sim.step(10);
      expect(sim.cylinder('1A')!.motion, Motion.retracting);
      sim.run(1000);
      expect(sim.pos('1A'), 0);
      expect(sim.out('1B1'), isTrue);
    });

    test('signal takes effect at the next step', () {
      final sim = simulatorFor(cylinderCircuit());
      sim.setSignal('1V1', '14', true);
      expect(sim.valve('1V1')!.position, 0);
      sim.step(10);
      expect(sim.valve('1V1')!.position, 1);
      expect(sim.pos('1A'), closeTo(0.01, 1e-9), reason: 'moves already in the switching step');
    });

    test('manual override on the solenoid', () {
      final sim = simulatorFor(cylinderCircuit());
      sim.setControl('1V1', 'manual_a', true);
      sim.run(1000);
      expect(sim.pos('1A'), closeTo(1, 1e-9));
    });
  });

  group('two-position actuation', () {
    test('bistable valve keeps its position', () {
      final sim = simulatorFor(cylinderCircuit(valveParams: {'actuation': Actuation.bistable}));
      final valve = sim.valve('1V1')!;
      sim.setSignal('1V1', '14', true);
      sim.step(10);
      sim.setSignal('1V1', '14', false);
      sim.step(10);
      expect(valve.position, 1, reason: 'stays after the pulse');

      sim.setSignal('1V1', '12', true);
      sim.setSignal('1V1', '14', true);
      sim.step(10);
      expect(valve.position, 1, reason: 'both solenoids: no change');

      sim.setSignal('1V1', '14', false);
      sim.step(10);
      expect(valve.position, 0);
    });

    test('manual button with spring and lever with detent', () {
      final button = simulatorFor(cylinderCircuit(valveParams: {'actuation': Actuation.button}));
      button.setControl('1V1', 'button', true);
      button.step(10);
      expect(button.valve('1V1')!.position, 1);
      button.setControl('1V1', 'button', false);
      button.step(10);
      expect(button.valve('1V1')!.position, 0);

      final lever = simulatorFor(cylinderCircuit(valveParams: {'actuation': Actuation.lever}));
      lever.setControl('1V1', 'lever', true);
      lever.run(100);
      expect(lever.valve('1V1')!.position, 1);
      expect(lever.control('1V1', 'lever'), isTrue);
    });
  });

  group('5/3 valves', () {
    PlantSimulator halfExtended(String valve) {
      final sim = simulatorFor(cylinderCircuit(valve: valve)
        ..element('PS', 'pressure_switch')
        ..connect('PS.1', '1A.A'));
      sim.setSignal('1V1', '14', true);
      sim.run(500);
      expect(sim.pos('1A'), closeTo(0.5, 1e-9));
      sim.setSignal('1V1', '14', false);
      sim.run(500);
      expect(sim.valve('1V1')!.position, 0, reason: 'spring centered');
      return sim;
    }

    test('closed center holds the piston with trapped air', () {
      final sim = halfExtended('valve_5_3_closed');
      expect(sim.pos('1A'), closeTo(0.5, 1e-9));
      expect(sim.at('1A.A'), LineState.trappedPressure);
      expect(sim.at('1A.B'), LineState.trappedEmpty);
      expect(sim.out('PS'), isTrue, reason: 'pressure stays in the closed line');
      expect(sim.at('S.P'), LineState.supplied);
    });

    test('exhausted center vents both chambers', () {
      final sim = halfExtended('valve_5_3_exhausted');
      expect(sim.pos('1A'), closeTo(0.5, 1e-9));
      expect(sim.at('1A.A'), LineState.vented);
      expect(sim.at('1A.B'), LineState.vented);
      expect(sim.out('PS'), isFalse);
    });

    test('pressurized center supplies both chambers', () {
      final sim = halfExtended('valve_5_3_pressurized');
      expect(sim.pos('1A'), closeTo(0.5, 1e-9));
      expect(sim.at('1A.A'), LineState.supplied);
      expect(sim.at('1A.B'), LineState.supplied);
    });

    test('solenoid 12 retracts', () {
      final sim = halfExtended('valve_5_3_closed');
      sim.setSignal('1V1', '12', true);
      sim.run(500);
      expect(sim.valve('1V1')!.position, 2);
      expect(sim.pos('1A'), 0);
    });
  });

  group('single-acting cylinder with 3/2 valves', () {
    PlantBuilder circuit(String valve) => PlantBuilder()
      ..element('S', 'air_supply')
      ..element('V', valve)
      ..element('A1', 'cylinder_single', params: {'extend_ms': 400, 'retract_ms': 800})
      ..connect('S.P', 'V.1')
      ..connect('V.2', 'A1.A');

    test('3/2 NC extends while energized, spring returns', () {
      final sim = simulatorFor(circuit('valve_3_2_nc'));
      sim.run(100);
      expect(sim.pos('A1'), 0);
      sim.setSignal('V', '12', true);
      sim.run(400);
      expect(sim.pos('A1'), closeTo(1, 1e-9));
      sim.setSignal('V', '12', false);
      sim.run(400);
      expect(sim.pos('A1'), closeTo(0.5, 1e-9), reason: 'retract time 800 ms');
      sim.run(400);
      expect(sim.pos('A1'), 0);
    });

    test('3/2 NO extends at rest', () {
      final sim = simulatorFor(circuit('valve_3_2_no'));
      sim.run(400);
      expect(sim.pos('A1'), closeTo(1, 1e-9));
      sim.setSignal('V', '10', true);
      sim.run(800);
      expect(sim.pos('A1'), 0);
    });
  });

  group('flow control', () {
    /// Flow control valve FC between valve port [valvePort] and cylinder port
    /// [cylinderPort]; [facing] is the FC port connected to the cylinder.
    PlantSimulator throttled({
      required String cylinderPort,
      required String facing,
      bool checkValve = true,
    }) {
      final valvePort = cylinderPort == 'A' ? '4' : '2';
      final other = cylinderPort == 'A' ? 'B' : 'A';
      final otherValvePort = cylinderPort == 'A' ? '2' : '4';
      final far = facing == '1' ? '2' : '1';
      return simulatorFor(PlantBuilder()
        ..element('S', 'air_supply')
        ..element('V', 'valve_5_2')
        ..element('C', 'cylinder_double')
        ..element('FC', 'flow_control', params: {'opening': 0.5, 'check_valve': checkValve})
        ..connect('S.P', 'V.1')
        ..connect('V.$valvePort', 'FC.$far')
        ..connect('FC.$facing', 'C.$cylinderPort')
        ..connect('V.$otherValvePort', 'C.$other'));
    }

    int extendTime(PlantSimulator sim) {
      sim.setSignal('V', '14', true);
      var t = 0;
      while (sim.pos('C') < 1 - 1e-9) {
        sim.step(10);
        t += 10;
      }
      return t;
    }

    int retractTime(PlantSimulator sim) {
      sim.setSignal('V', '14', false);
      var t = 0;
      while (sim.pos('C') > 0) {
        sim.step(10);
        t += 10;
      }
      return t;
    }

    test('meter-out on B slows extension only', () {
      final sim = throttled(cylinderPort: 'B', facing: '1');
      expect(extendTime(sim), 2000);
      expect(retractTime(sim), 1000);
    });

    test('meter-in on A slows extension only', () {
      final sim = throttled(cylinderPort: 'A', facing: '2');
      expect(extendTime(sim), 2000);
      expect(retractTime(sim), 1000);
    });

    test('reversed flow control throttles the other direction', () {
      final sim = throttled(cylinderPort: 'A', facing: '1');
      expect(extendTime(sim), 1000);
      expect(retractTime(sim), 2000);
    });

    test('without check valve both directions are throttled', () {
      final sim = throttled(cylinderPort: 'A', facing: '2', checkValve: false);
      expect(extendTime(sim), 2000);
      expect(retractTime(sim), 2000);
    });
  });

  group('lines', () {
    test('open working port short-circuits the supply (leak)', () {
      final sim = simulatorFor(PlantBuilder()
        ..element('S', 'air_supply')
        ..element('V', 'valve_5_2')
        ..element('C', 'cylinder_double')
        ..connect('S.P', 'V.1')
        ..connect('V.4', 'C.A'));
      // Rest position: 1→2 with port 2 open to atmosphere.
      expect(sim.at('S.P'), LineState.shorted);
      sim.setSignal('V', '14', true);
      sim.run(100);
      expect(sim.at('C.A'), LineState.supplied, reason: 'now 2 exhausts through 3');
      expect(sim.at('C.B'), LineState.vented, reason: 'open cylinder port');
      expect(sim.pos('C'), greaterThan(0));
    });

    test('unconnected supply port does not leak', () {
      final sim = simulatorFor(PlantBuilder()..element('S', 'air_supply'));
      expect(sim.at('S.P'), LineState.supplied);
    });

    test('service unit passes air through', () {
      final sim = simulatorFor(PlantBuilder()
        ..element('S', 'air_supply')
        ..element('SU', 'service_unit')
        ..element('PS', 'pressure_switch')
        ..connect('S.P', 'SU.1')
        ..connect('SU.2', 'PS.1'));
      sim.step(10);
      expect(sim.out('PS'), isTrue);
    });

    test('one valve drives two cylinders through branched tubes', () {
      final sim = simulatorFor(cylinderCircuit()
        ..element('2A', 'cylinder_double', params: {'extend_ms': 500})
        ..connect('1V1.4', '2A.A')
        ..connect('1V1.2', '2A.B'));
      sim.setSignal('1V1', '14', true);
      sim.run(500);
      expect(sim.pos('2A'), closeTo(1, 1e-9));
      expect(sim.pos('1A'), closeTo(0.5, 1e-9));
    });
  });
}
