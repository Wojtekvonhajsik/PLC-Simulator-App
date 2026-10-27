# plant_core

Model schematu elektropneumatycznego i jego jakościowa symulacja. Czysty Dart, bez zależności
od Fluttera i od `plc_core` — z PLC łączy się przez adresy w `PlantElement.io`
(sprzężenie zrobi pakiet `sim_engine`).

## Model

- `PlantElement` — element z katalogu (`type`), parametry, powiązania sygnałów z adresami PLC.
- `Connection` — przewód pneumatyczny między portami (`1V1.4` → `1A.A`). Do portu można
  podłączyć kilka przewodów (rozgałęzienie).
- `SensorMount` — czujnik zamontowany na siłowniku w pozycji 0…1 skoku.
- Model jest wspólny dla widoku obrazkowego i symbolowego; rozmieszczenie trzyma aplikacja.

## Katalog elementów

| Grupa | Typy |
|---|---|
| Zasilanie | `air_supply`, `service_unit` |
| Zawory | `valve_3_2_nc`, `valve_3_2_no`, `valve_5_2` (sterowanie: monostabilny, bistabilny, przycisk, dźwignia), `valve_5_3_closed`, `valve_5_3_exhausted`, `valve_5_3_pressurized` |
| Dławienie | `flow_control` (dławiony kierunek 1→2, zwrotny 2→1) |
| Siłowniki | `cylinder_single`, `cylinder_double` (skok, czasy ruchu, tłok magnetyczny) |
| Czujniki | `reed_switch` (wymaga tłoka magnetycznego), `inductive_sensor`, `limit_switch`, `pressure_switch` |
| Obsługa | `push_button`, `selector_switch`, `emergency_stop` |
| Sygnalizacja | `lamp`, `buzzer` |

Sygnały cewek zaworów mają oznaczenia ISO 5599 (`14`, `12`, `10`), wyjście czujników to `out`,
wejście lampki/brzęczyka to `in`.

## Symulacja (świadome uproszczenia)

Krok czasu (`step(dtMs)`): zawory przełączają się wg cewek i sterowania ręcznego → wyliczane są
stany linii → siłowniki się ruszają → czujniki ustawiają wyjścia.

- Linia (zbiór połączonych portów) jest: zasilona, odpowietrzona, zwarta (zasilanie połączone
  z atmosferą — wyciek) lub zamknięta z ciśnieniem / bez ciśnienia.
- Niepodłączony port jest otwarty do atmosfery (jak w rzeczywistości bez zaślepki); wyjątkiem
  jest port źródła.
- Siłownik porusza się ze stałą prędkością, gdy komora napędzająca jest zasilona, a przeciwna
  może się odpowietrzyć. Ciśnienie po obu stronach trzyma tłok (bez efektu różnicy powierzchni).
- Zawór dławiąco-zwrotny wydłuża czas ruchu proporcjonalnie do otwarcia, tylko w dławionym
  kierunku przepływu (działa dławienie na zasilaniu i na wylocie).
- Nie są modelowane ciśnienia, siły, masy ani obciążenia.

## Przykład

```dart
final plant = PlantBuilder()
  ..element('S', 'air_supply')
  ..element('1V1', 'valve_5_2', io: {'14': '%Q0.0'})
  ..element('1A', 'cylinder_double')
  ..element('1B2', 'reed_switch', io: {'out': '%I0.1'})
  ..connect('S.P', '1V1.1')
  ..connect('1V1.4', '1A.A')
  ..connect('1V1.2', '1A.B')
  ..mount('1B2', '1A', 1);

final sim = buildPlant(plant.build()).simulator!;
sim.setSignal('1V1', '14', true);
for (var i = 0; i < 100; i++) {
  sim.step(10);
}
print(sim.signal('1B2', 'out')); // true
```
