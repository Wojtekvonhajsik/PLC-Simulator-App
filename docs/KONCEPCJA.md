# Koncepcja: mobilny symulator PLC (LAD + symulacja obiektu)

Status: szkic do dyskusji, przed implementacją.

## 1. Cel i założenia

Aplikacja na telefon/tablet do nauki programowania sterowników PLC w języku drabinkowym (LAD),
w stylu zbliżonym do edytora LAD z TIA Portal, z wbudowanym modułem symulacji obiektu
(przyciski, czujniki, lampki, siłowniki itd.), który jest sterowany przez napisany program.

Założenia:
- działa w pełni offline, bez prawdziwego sterownika,
- semantyka wykonania wiernie odwzorowuje PLC (cykl skanowania, obraz procesu),
- edytor projektowany pod ekran dotykowy, nie przeniesiony 1:1 z desktopu,
- **nie** używamy nazw, logo ani ikon Siemens/TIA Portal — mówimy o „LAD wg IEC 61131-3,
  w stylu znanym z popularnych środowisk”. Adresacja `%I0.0`, `%Q0.0`, `%M0.0`, `%MW10` jest
  ogólnie przyjęta i może zostać.

## 2. Moduły aplikacji

```
┌──────────────┐   ┌──────────────┐   ┌──────────────────┐
│ Edytor LAD   │──▶│ Kompilator   │──▶│ Runtime PLC      │
│ (UI, sieci)  │   │ LAD → IR     │   │ (cykl skanowania)│
└──────────────┘   └──────────────┘   └────────┬─────────┘
       ▲                                       │ obraz procesu I/Q
       │ monitoring online                     ▼
       │                              ┌──────────────────┐
       └──────────────────────────────│ Symulator obiektu│
                                      │ (komponenty 2D)  │
                                      └──────────────────┘
       Tablica tagów (zmienne, adresy, komentarze) — wspólna dla wszystkich modułów
```

### 2.1 Edytor LAD
- Program = lista **sieci (networks)**, każda z tytułem i komentarzem (jak w TIA).
- Model sieci jako drzewo szeregowo-równoległe:
  `Series[ NO(Start), Parallel[ Series[NC(Stop)], Series[NO(Q_Motor)] ], Coil(Q_Motor) ]`.
  Upraszcza to edycję, walidację i wykonanie; nie dopuszcza „mostków”, które i tak są
  niezalecane.
- Edycja dotykowa: tryb poziomy, siatka komórek, zaznaczenie komórki tapnięciem,
  dolny pasek „ulubionych” instrukcji (NO, NC, cewka, otwórz/zamknij gałąź, S/R, timer),
  pełna paleta w wysuwanym panelu. Przypisanie tagu przez dialog z autouzupełnianiem.
- Pinch-zoom i przewijanie, cofnij/ponów, kopiuj/wklej sieci.
- Walidacja na bieżąco: brak tagu, cewka nie na końcu, podwójne przypisanie cewki (ostrzeżenie).

### 2.2 Zestaw instrukcji (MVP → później)
| Grupa | MVP | Później |
|---|---|---|
| Logika bitowa | NO `-| |-`, NC `-|/|-`, cewka `-( )-`, negacja `-(/)-`, S, R, NOT | P/N (zbocza), SR/RS |
| Timery IEC | TON, TOF, TP | TONR |
| Liczniki IEC | CTU, CTD | CTUD |
| Porównania | ==, <>, >, <, >=, <= (INT) | REAL, IN_RANGE |
| Przenoszenie / matematyka | MOVE, ADD, SUB | MUL, DIV, skalowanie analogów (NORM_X/SCALE_X) |
| Struktura | — | bloki FC/FB, DB |

Typy danych w MVP: BOOL, INT, TIME. Później REAL, DINT.

### 2.3 Runtime PLC
- Cykl skanowania jak w PLC:
  1. odczyt wejść z symulatora do obrazu procesu wejść (PII),
  2. wykonanie sieci po kolei, od góry do dołu, od lewej do prawej,
  3. zapis obrazu wyjść (PIQ) do symulatora.
- Wejścia „zamrożone” na czas cyklu — dokładnie jak w prawdziwym sterowniku. To ważne
  dydaktycznie (np. przy zboczach i podwójnych cewkach).
- Czas symulowany, deterministyczny (np. cykl 10 ms), z możliwością: STOP/RUN,
  pauzy, pracy krok po kroku (jeden cykl), spowolnienia ×0.1 / przyspieszenia ×10.
- Program kompilowany do prostej reprezentacji pośredniej (IR, np. drzewo wyrażeń
  lub lista instrukcji stosowych) — runtime nie interpretuje bezpośrednio struktur UI.
- Silnik w czystym kodzie (bez zależności od UI) — w pełni testowalny jednostkowo.

### 2.4 Monitoring online
- Przełącznik „Monitorowanie” jak w TIA: przepływ prądu zaznaczony na zielono,
  przerwany — szary/przerywany, bieżące wartości timerów (ET/PT) i liczników nad blokami.
- Możliwość wymuszania (force) wartości tagu z poziomu edytora i tablicy tagów.

### 2.5 Symulator obiektu
Osobny ekran „Obiekt” z płótnem 2D, na które użytkownik przeciąga komponenty i wiąże je
z adresami I/O. Każdy komponent ma własny model zachowania aktualizowany w każdym kroku czasu.

| Komponent | Wejścia/wyjścia PLC | Zachowanie |
|---|---|---|
| Przycisk NO/NC (chwilowy) | `%I` | aktywny tylko podczas przytrzymania |
| Przełącznik / stacyjka | `%I` | stabilny 2/3 pozycje |
| Grzybek bezpieczeństwa | `%I` (NC) | zatrzaskowy, odblokowanie obrotem |
| Lampka (kolory), buzzer | `%Q` | świeci/miga wg wyjścia |
| Siłownik jedno- i dwustronnego działania + zawór 5/2 mono/bistabilny | `%Q` (cewki zaworu) | pozycja 0…1, regulowany czas wysuwu/wsuwu |
| Czujnik krańcowy / kontaktron na siłowniku | `%I` | wyliczany z pozycji tłoka |
| Czujnik zbliżeniowy / fotokomórka | `%I` | wykrywa obiekt na taśmie |
| Silnik / taśmociąg | `%Q` | przesuwa detale, opcjonalnie kierunek L/P |
| Potencjometr, wskaźnik (później) | `%IW`, `%QW` | wartości analogowe 0…27648 |
| Zbiornik z pompą i zaworem (później) | `%Q`, `%I`, `%IW` | poziom cieczy, czujniki min/max |

- Gotowe szablony stanowisk: „Start–Stop silnika”, „Siłownik z krańcówkami”,
  „Taśmociąg z sortowaniem”, „Sygnalizacja świetlna”, „Napełnianie zbiornika”.
- Widok dzielony na tablecie: LAD + obiekt jednocześnie. Na telefonie: szybkie
  przełączanie zakładek + pływający mini-panel przycisków.

### 2.6 Tablica tagów
- Nazwa, adres, typ, komentarz; automatyczne przypisanie adresu przy tworzeniu
  komponentu w symulatorze.
- Widok „watch table” z bieżącymi wartościami i wymuszaniem.

### 2.7 Projekty i nauka
- Zapis lokalny (JSON), eksport/import pliku projektu (udostępnianie przez systemowe „Udostępnij”).
- Później: moduł ćwiczeń z automatyczną weryfikacją (scenariusz testowy wymusza wejścia
  i sprawdza wyjścia w czasie), np. „samopodtrzymanie”, „sekwencja A+ B+ A- B-”.

## 3. Technologia (rekomendacja)

**Flutter (Dart)** — jedna baza kodu Android + iOS, wydajne rysowanie własnych widoków
(`CustomPainter`) dla drabinki i płótna symulacji, stabilne 60 fps, dobre wsparcie testów.

Alternatywy:
- React Native + Skia — sensowne przy doświadczeniu w JS/TS; rysowanie własnych widoków
  jest bardziej kłopotliwe.
- Natywny Kotlin + Jetpack Compose — jeśli celem jest wyłącznie Android.

Struktura kodu (Flutter):
```
lib/
  core/        # model programu, kompilator, runtime, timery, liczniki (czysty Dart)
  sim/         # modele komponentów symulacji i ich fizyka
  editor/      # UI edytora LAD
  plant/       # UI płótna symulacji
  tags/        # tablica tagów / watch table
  storage/     # zapis/odczyt projektów
test/          # testy silnika i symulacji
```

## 4. Plan etapów

1. **Silnik** — model sieci, kompilator do IR, cykl skanowania, logika bitowa, TON/TOF/TP,
   CTU/CTD, testy jednostkowe. Bez UI.
2. **Edytor LAD** — sieci, styki, cewki, gałęzie równoległe, tablica tagów, zapis projektu.
3. **Symulator obiektu (podstawa)** — przyciski, przełączniki, lampki, siłownik z zaworem
   i krańcówkami, powiązanie z I/O, RUN/STOP.
4. **Monitoring online** — przepływ prądu, wartości timerów/liczników, wymuszanie.
5. **Rozszerzenia** — porównania/MOVE/matematyka, taśmociąg, analogi, szablony,
   ćwiczenia, później FC/FB.

## 5. Ryzyka i decyzje do podjęcia

- **Ekran telefonu** — LAD z kilkoma gałęziami szybko przestaje się mieścić. Wymagany tryb
  poziomy; tablet jako pełnoprawny cel, telefon jako „wystarczający”.
- **Zakres** — największe ryzyko projektu. FBD, SCL, DB, FB poza MVP.
- **Zgodność z TIA** — wierne odwzorowanie wszystkich niuansów (np. instancyjne DB timerów)
  jest kosztowne; w MVP uproszczenia z jasnym opisem różnic.
- **Konkurencja** — w sklepach istnieją już proste symulatory drabinkowe. Wyróżnik:
  realistyczny cykl skanowania, monitoring jak w TIA i dynamiczny symulator obiektu.
- **Prawa do znaków towarowych** — bez nazw i grafik Siemens w aplikacji i w opisie sklepu.
