# sim_engine

Łączy silnik PLC (`plc_core`) ze schematem obiektu (`plant_core`) i prowadzi wspólną symulację.
Re-eksportuje oba pakiety, więc aplikacji wystarczy `import 'package:sim_engine/sim_engine.dart';`.

## Budowanie

`buildSimulation(SimulationProject(...))` kompiluje program, waliduje schemat i rozwiązuje
powiązania sygnałów z adresami. Wynik zawiera osobne listy diagnostyk dla edytora LAD, edytora
schematu i powiązań I/O; symulacja powstaje tylko bez błędów.

Powiązanie sygnału (`PlantElement.io`) może być adresem (`%I0.0`) albo nazwą zmiennej (`Start`).
Błędy powiązań:

- nieprawidłowy adres, nieznana zmienna, adres poza zakresem,
- czujnik/przycisk podpięty pod coś innego niż `%I`, cewka/lampka pod coś innego niż `%Q`,
- dwa elementy na tym samym wejściu (jedno wyjście może sterować kilkoma elementami).

## Cykl

Każdy `step()` trwa `cycleMs` (domyślnie 10 ms):

1. obiekt przesuwa się o krok, używając wyjść PLC z poprzedniego cyklu,
2. sygnały czujników i przycisków trafiają na wejścia PLC,
3. PLC wykonuje jeden cykl skanowania,
4. wyjścia PLC trafiają do cewek zaworów, lampek i brzęczyków.

STOP sterownika zeruje wyjścia, ale obiekt działa dalej (sprężyny cofają zawory). START to zimny
restart PLC — obiekt zachowuje swój stan fizyczny.

## Zegar

`SimulationClock.tick(realElapsedMs)` zamienia czas rzeczywisty z UI na całe cykle symulacji:
tempo (`speed` 0.05…20), pauza, `stepOnce()`. Wynik symulacji zależy tylko od czasu
symulowanego, nie od liczby klatek na sekundę.

## Uwaga o czujnikach

Kontaktron ze strefą ±3 mm na skoku 100 mm zgłasza krańcówkę już przy 97 mm, więc następny
krok sekwencji startuje, zanim siłownik dojedzie do końca — tak jak na prawdziwym stanowisku.
