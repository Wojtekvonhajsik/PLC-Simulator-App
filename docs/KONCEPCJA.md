# Koncepcja: mobilny symulator PLC (LAD + edytor schematów obiektu)

Status: wersja 2, szkic do dyskusji przed implementacją.

Zmiany względem wersji 1:
- symulator obiektu zastąpiony **edytorem schematów** — użytkownik buduje stanowisko
  z biblioteki elementów (zawory, siłowniki, różne typy czujników, przyciski, lampki)
  i sam je łączy, np. decyduje, czy siłownik ma kontaktrony i gdzie,
- z LAD usunięte operacje na liczbach (MOVE, ADD, SUB, matematyka, skalowanie analogów),
- rozszerzone: timery, liczniki, zbocza, komparatory.

## 1. Cel i założenia

Aplikacja na telefon/tablet do nauki programowania PLC w języku drabinkowym (LAD),
w stylu zbliżonym do edytora LAD z TIA Portal, z edytorem schematów
elektropneumatycznych, w którym buduje się sterowany obiekt.

Założenia:
- działa w pełni offline,
- semantyka wykonania wiernie odwzorowuje PLC (cykl skanowania, obraz procesu),
- edytory projektowane pod ekran dotykowy, w trybie poziomym,
- symbole pneumatyczne w stylu ISO 1219 (wartość dydaktyczna),
- **bez** nazw, logo i grafik Siemens/TIA Portal w aplikacji i w sklepie.

## 2. Moduły aplikacji

```
┌──────────────┐   ┌──────────────┐   ┌──────────────────┐
│ Edytor LAD   │──▶│ Kompilator   │──▶│ Runtime PLC      │
│ (sieci)      │   │ LAD → IR     │   │ (cykl skanowania)│
└──────────────┘   └──────────────┘   └────────┬─────────┘
       ▲                                       │ obraz procesu %I / %Q
       │ monitoring online                     ▼
       │                              ┌──────────────────────────┐
       └──────────────────────────────│ Edytor schematów +       │
                                      │ symulator obiektu        │
                                      └──────────────────────────┘
          Tablica tagów (nazwa, adres, komentarz) — wspólna dla wszystkich modułów
```

## 3. Edytor LAD

### 3.1 Struktura
- Program = lista **sieci (networks)** z tytułem i komentarzem.
- Sieć jako drzewo szeregowo-równoległe:
  `Series[ NO(Start), Parallel[ Series[NC(Stop)], Series[NO(Q_Motor)] ], Coil(Q_Motor) ]`.
  Bez „mostków” między gałęziami — upraszcza edycję i wykonanie.
- Edycja dotykowa: siatka komórek, dolny pasek ulubionych instrukcji, pełna paleta
  w wysuwanym panelu, dialog przypisania tagu z autouzupełnianiem, pinch-zoom,
  cofnij/ponów, kopiuj/wklej sieci.
- Walidacja na bieżąco: brak operandu, cewka nie na końcu, podwójna cewka (ostrzeżenie),
  ten sam bit pamięci zbocza użyty dwa razy (ostrzeżenie).

### 3.2 Zestaw instrukcji

| Grupa | Instrukcje |
|---|---|
| Styki | NO `-\| \|-`, NC `-\|/\|-`, NOT `-\|NOT\|-` |
| Cewki | `-( )-`, negowana `-(/)-`, Set `-(S)-`, Reset `-(R)-` |
| Przerzutniki | SR (dominujący reset), RS (dominujący set) |
| Zbocza | styk zbocza narastającego `-\|P\|-`, opadającego `-\|N\|-`, cewki `-(P)-`, `-(N)-`, bloki P_TRIG, N_TRIG |
| Timery IEC | TON (opóźnione załączenie), TOF (opóźnione wyłączenie), TP (impuls), TONR (z pamięcią czasu) |
| Liczniki IEC | CTU (w górę), CTD (w dół), CTUD (w górę/w dół) |
| Komparatory | `==`, `<>`, `>`, `<`, `>=`, `<=` oraz IN_RANGE / OUT_RANGE |

Uwagi:
- **Zbocza** wymagają bitu pamięci zbocza (jak w TIA). Edytor podpowiada wolny bit
  `%M`, użytkownik może go zmienić.
- **Timery i liczniki** mają instancję (np. `T_Wysuw`, `C_Detale`) z polami `IN/Q/PT/ET`
  lub `CU/CD/R/LD/PV/CV/QU/QD`. Pola dostępne jako operandy w innych sieciach,
  np. `T_Wysuw.Q`, `C_Detale.CV`.
- **Komparatory potrzebują wartości liczbowych.** Nie ma operacji arytmetycznych ani MOVE,
  ale wewnętrznie zostają typy INT (wartość licznika) i TIME (czas timera). Komparator
  porównuje `CV`/`ET` ze stałą albo z innym `CV`/`ET`, np. `C_Detale.CV >= 5`,
  `T_Cykl.ET > T#3s`.
- Typy danych widoczne dla użytkownika: BOOL, INT (tylko liczniki i stałe), TIME.

## 4. Runtime PLC

- Cykl skanowania: odczyt wejść do obrazu procesu (PII) → wykonanie sieci od góry
  do dołu → zapis obrazu wyjść (PIQ) do symulatora obiektu.
- Wejścia zamrożone na czas cyklu, jak w prawdziwym PLC (ważne przy zboczach).
- Czas symulowany, deterministyczny (cykl np. 10 ms): RUN/STOP, pauza, krok o jeden
  cykl, spowolnienie ×0.1 / przyspieszenie ×10.
- Program kompilowany do reprezentacji pośredniej (IR); silnik w czystym kodzie,
  bez zależności od UI, z testami jednostkowymi.

### Monitoring online
- Przepływ prądu na zielono, przerwany — szary/przerywany.
- Nad timerami i licznikami bieżące `ET`/`CV`, nad komparatorami wynik porównania.
- Wymuszanie (force) tagów z edytora i z tablicy obserwacji.

## 5. Edytor schematów i symulator obiektu

### 5.1 Biblioteka elementów

**Zasilanie i przygotowanie powietrza**
- źródło sprężonego powietrza, zespół przygotowania powietrza, zawór odcinający,
  rozdzielacz (listwa)

**Zawory rozdzielające**
- 3/2 NC i NO, 5/2, 5/3 (środek zamknięty / odpowietrzony / zasilony)
- sposób sterowania (konfigurowalny osobno dla każdej strony):
  elektromagnes (cewka `%Q`), przycisk/dźwignia ręczna, sprężyna powrotna
- warianty gotowe: 5/2 monostabilny (cewka + sprężyna), 5/2 bistabilny (2 cewki),
  5/3 z dwiema cewkami i centrowaniem sprężynami

**Elementy wykonawcze**
- siłownik jednostronnego działania (powrót sprężyną)
- siłownik dwustronnego działania
- parametry: skok, czas wysuwu/wsuwu, tłok magnetyczny (tak/nie — potrzebny dla kontaktronów)

**Elementy pomocnicze**
- zawór dławiąco-zwrotny (regulacja prędkości wysuwu/wsuwu)
- tłumik, zawór szybkiego spustu (później)

**Czujniki** (każdy daje sygnał `%I`)

| Typ | Montaż | Co wykrywa | Parametry |
|---|---|---|---|
| Kontaktron | na siłowniku, pozycja na skoku | magnes tłoka | pozycja (0…100 % skoku), histereza |
| Indukcyjny | na siłowniku (krzywka na tłoczysku) lub samodzielnie | metal | zasięg, NO/NC |
| Pojemnościowy | samodzielnie | dowolny materiał | zasięg, NO/NC |
| Optyczny (bariera / odbiciowy) | samodzielnie | dowolny obiekt | zasięg, NO/NC |
| Krańcowy mechaniczny | na siłowniku lub samodzielnie | kontakt mechaniczny | pozycja, NO/NC |
| Czujnik ciśnienia (presostat) | na przewodzie | ciśnienie w linii | próg |

**Elementy elektryczne / obsługi**
- przycisk chwilowy NO/NC, przełącznik 2/3-pozycyjny, grzybek bezpieczeństwa (NC, zatrzask)
- lampka (kolor, miganie), buzzer
- (później) silnik/taśmociąg i detale (metalowe/plastikowe) do testowania różnych czujników

### 5.2 Łączenie elementów
- **Pneumatyka:** każdy element ma porty wg oznaczeń ISO (1 – zasilanie, 2/4 – wyjścia,
  3/5 – odpowietrzenia, A/B – przyłącza siłownika). Przewód rysuje się, przeciągając
  palcem od portu do portu; trasa prowadzona automatycznie pod kątem prostym.
- **Czujniki na siłowniku:** czujnik przeciąga się na siłownik — „przykleja się”
  do jego korpusu. Można go przesunąć wzdłuż skoku albo usunąć. Siłownik może mieć
  0, 1, 2 lub więcej czujników.
- **Elektryka (sygnały PLC):** dwa tryby, użytkownik wybiera:
  1. *szybki* — adres `%I`/`%Q` wybierany we właściwościach elementu,
  2. *okablowanie* — na schemacie stoi moduł wejść/wyjść PLC z zaciskami
     (`I0.0…I1.7`, `Q0.0…Q1.7`); przewód rysuje się od cewki zaworu / czujnika do zacisku.
  Oba tryby zapisują to samo powiązanie, więc można je przełączać.
- Przy przypisaniu adresu automatycznie powstaje tag z sensowną nazwą
  (np. `Y1_Wysuw_A`, `B1_A_wsuniety`), do edycji.

### 5.3 Walidacja schematu
- niepodłączone porty, siłownik bez zasilania, zawór bez źródła,
- zwarcie zasilania z odpowietrzeniem (wyciek),
- kontaktron na siłowniku bez tłoka magnetycznego (czujnik nigdy nie zadziała — ostrzeżenie),
- cewka/czujnik bez adresu, dwa elementy na tym samym adresie wejścia.

### 5.4 Model symulacji (uproszczony, jakościowy)
Pełna symulacja przepływów i ciśnień jest poza zakresem i niepotrzebna dydaktycznie.
Zamiast tego:
- Połączone porty tworzą **linie**. Każda linia ma stan: *zasilona*, *odpowietrzona*
  lub *odcięta*.
- Każdy zawór w danej pozycji łączy określone porty (tabela przełączeń). Pozycja zależy
  od cewek (`%Q`), sterowania ręcznego i sprężyny; zawór bistabilny pamięta ostatnią pozycję.
- Stan linii wyliczany propagacją od źródła i odpowietrzeń w każdym kroku symulacji.
- Siłownik dwustronny: komora A zasilona i B odpowietrzona → wysuw ze stałą prędkością
  (z ustawień siłownika i dławików); odwrotnie → wsuw; obie zamknięte → stoi.
  Siłownik jednostronny: zasilony → wysuw, odpowietrzony → powrót sprężyną.
- Czujniki wyliczane z pozycji tłoka i obiektów w zasięgu.

### 5.5 Tryby ekranu
- **Edycja:** paleta elementów (szuflada z kategoriami), przeciąganie, połączenia,
  panel właściwości po przytrzymaniu.
- **Symulacja:** linie zasilone podświetlone, animacja tłoka, czujniki i lampki
  zmieniają kolor; przyciski klikalne; ręczne przesterowanie zaworu (jak przycisk
  ręczny na cewce w rzeczywistości).
- Na tablecie widok dzielony: LAD + schemat.

### 5.6 Szablony
Gotowe stanowiska jako punkt startu i zadania:
- start–stop z samopodtrzymaniem,
- siłownik 1A z zaworem 5/2 monostabilnym i dwoma kontaktronami,
- sekwencja dwóch siłowników A+ B+ A- B-,
- licznik cykli z zatrzymaniem po N cyklach (CTU + komparator),
- odliczanie czasu postoju na pozycji (TON).

## 6. Tablica tagów
- Nazwa, adres, typ, komentarz; tagi tworzone automatycznie z edytora schematów.
- Tablica obserwacji z wartościami bieżącymi i wymuszaniem.

## 7. Projekty
- Projekt = program LAD + schemat + tagi, zapis lokalny (JSON).
- Eksport/import pliku projektu (systemowe „Udostępnij”).

## 8. Technologia (rekomendacja)

**Flutter (Dart)** — Android + iOS z jednej bazy, wydajne rysowanie własnych widoków
(`CustomPainter`) dla drabinki i schematu, dobre wsparcie testów.

```
lib/
  core/        # model LAD, kompilator, runtime, timery, liczniki, zbocza, komparatory
  plant/       # model schematu: elementy, porty, linie, propagacja stanów, fizyka siłowników
  editor_lad/  # UI edytora LAD
  editor_plant/# UI edytora schematów i trybu symulacji
  tags/        # tablica tagów i obserwacji
  storage/     # zapis/odczyt projektów
test/
```

## 9. Plan etapów

1. **Silnik PLC** — model LAD, IR, cykl skanowania, logika bitowa, zbocza, TON/TOF/TP/TONR,
   CTU/CTD/CTUD, komparatory; testy jednostkowe.
2. **Silnik schematu** — model elementów i portów, propagacja stanów linii, zawory 3/2, 5/2, 5/3,
   siłowniki, kontaktrony, czujnik indukcyjny; testy jednostkowe.
3. **Edytor LAD** — sieci, gałęzie, tagi, zapis projektu.
4. **Edytor schematów** — paleta, przeciąganie, przewody, montaż czujników na siłowniku,
   właściwości, walidacja.
5. **Integracja i monitoring** — RUN/STOP, podgląd przepływu prądu, animacja schematu, wymuszanie.
6. **Rozszerzenia** — moduł I/O z okablowaniem, taśmociąg i detale (czujniki pojemnościowe
   i optyczne w praktyce), presostat, szablony i ćwiczenia z automatyczną weryfikacją.

## 10. Ryzyka i decyzje

- **Edytor schematów na telefonie** — rysowanie przewodów palcem na małym ekranie jest
  trudne. Konieczne: przyciąganie do portów, powiększanie portu przy dotyku, automatyczne
  prowadzenie przewodów. Tryb okablowania elektrycznego przesunięty na później.
- **Zakres** — dwa pełne edytory (LAD + schemat) to praktycznie dwie aplikacje.
  Etapy 1–2 bez UI pozwalają wcześnie zweryfikować logikę.
- **Wierność fizyki** — model jakościowy celowo pomija ciśnienia, siły i masy.
  Należy to jasno komunikować.
- **Znaki towarowe** — bez nazw i grafik Siemens.
