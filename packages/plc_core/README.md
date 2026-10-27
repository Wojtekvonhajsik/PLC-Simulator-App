# plc_core

Silnik PLC symulatora: model programu LAD, kompilator i runtime z cyklem skanowania.
Czysty Dart, bez zależności od Fluttera.

## Co zawiera

- **Model LAD** (`ladder.dart`): sieci jako drzewo szeregowo-równoległe; operandy jako tekst
  wpisany przez użytkownika (`Start`, `%I0.0`, `T1.Q`, `T#5s`, `10`).
- **Instrukcje:** styki NO/NC/NOT, cewki `( )`, `(/)`, `(S)`, `(R)`, zbocza `|P|`, `|N|`, `(P)`, `(N)`,
  P_TRIG/N_TRIG, SR/RS, timery TON/TOF/TP/TONR, liczniki CTU/CTD/CTUD, komparatory
  `== <> > < >= <=`, IN_RANGE/OUT_RANGE.
- **Kompilator** (`compile`): rozwiązuje operandy, sprawdza typy i strukturę, zwraca listę
  diagnostyk (błędy blokują uruchomienie, ostrzeżenia nie).
- **Runtime** (`PlcRuntime`): STOP/RUN, cykl skanowania z obrazem procesu, czas symulowany,
  wymuszanie (force) wejść/wyjść, modyfikacja bitów, monitoring przepływu prądu.

## Przykład

```dart
final b = LadderBuilder();
final result = compile(
  Program([
    b.network([
      b.parallel([[b.no('Start')], [b.no('Motor')]]),
      b.nc('Stop'),
      b.coil('Motor'),
    ]),
  ]),
  tags: const [
    Tag(name: 'Start', address: '%I0.0'),
    Tag(name: 'Stop', address: '%I0.1'),
    Tag(name: 'Motor', address: '%Q0.0'),
  ],
);

final plc = PlcRuntime(result.program!)..start();
plc.setInputByTag('Start', true);
plc.scan(cycleMs: 10);
print(plc.outputByTag('Motor')); // true
```

## Semantyka (świadome uproszczenia względem TIA Portal)

- Typy: BOOL; INT (wartości liczników i stałe) i TIME (czasy timerów i stałe) tylko do porównań.
  Brak arytmetyki i MOVE.
- Instancje timerów i liczników powstają z bloków (odpowiednik instancyjnego DB); pola dostępne
  jako `Nazwa.Q`, `.ET`, `.PT`, `.CV`, `.PV`, `.QU`, `.QD`.
- Wartości timerów aktualizowane są przy wywołaniu bloku (jak w S7-1200), nie przy odczycie pola.
- Każdy element sieci jest wykonywany w każdym cyklu, także bez przepływu prądu — timery,
  liczniki i bity zboczy widzą wtedy wejście 0.
- START wykonuje zimny restart: zeruje obrazy procesu, pamięć %M, timery i liczniki.

## Testy

```
dart pub get
dart test
```
