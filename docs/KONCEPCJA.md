# Koncepcja: mobilny symulator PLC (LAD + edytor schematów obiektu)

Status: wersja 3, szkic do dyskusji przed implementacją.

Zmiany w wersji 3:
- edytor schematów ma **dwa widoki**: obrazkowy (realistyczne elementy) i symbolowy (ISO 1219),
- ustalona architektura aplikacji (rozdział 8).

Zmiany w wersji 2:
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

### 5.5 Dwa widoki schematu: obrazkowy i symbolowy

Ten sam schemat można oglądać i edytować w dwóch widokach, przełączanych jednym przyciskiem.

| | Widok obrazkowy | Widok symbolowy |
|---|---|---|
| Wygląd | realistyczne ilustracje 2D (siłownik z tłoczyskiem, wyspa zaworowa, czujniki na korpusie, wężyki, panel z przyciskami) | symbole wg ISO 1219 (pneumatyka) i IEC 60617 (przyciski, lampki, czujniki) |
| Do czego | intuicyjne budowanie stanowiska „jak na stole laboratoryjnym”, dla początkujących | nauka czytania i rysowania schematów, dokumentacja |
| Przewody | wężyki pneumatyczne prowadzone łukami | linie proste, pod kątem prostym, układ warstwowy |
| Symulacja | ruch tłoczyska, diody na czujnikach i cewkach, wężyki zasilone podświetlone | przesuwanie pól zaworu, ruch tłoczyska w symbolu, linie zasilone podświetlone |

Zasady:
- **Wspólny model, osobne rozmieszczenie.** Elementy, ich parametry, połączenia,
  zamocowania czujników i adresy są wspólne dla obu widoków. Każdy widok przechowuje tylko
  własne położenia i obroty elementów. Zmiana w jednym widoku (dodanie zaworu, nowe połączenie,
  przesunięcie kontaktronu na skoku) natychmiast pojawia się w drugim.
- **Dlaczego nie wspólne położenia:** elementy mają w obu widokach inne wymiary i inne
  rozmieszczenie portów, a schemat symbolowy ma przyjęty układ (siłowniki u góry,
  zawory pod nimi, zasilanie na dole). Wspólne współrzędne dawałyby nakładające się
  elementy i nieczytelny schemat.
- **Automatyczne rozmieszczenie:** element dodany w jednym widoku dostaje w drugim
  pozycję wyliczoną automatycznie (w symbolowym — warstwowo wg roli elementu;
  w obrazkowym — obok elementu, z którym jest połączony). Użytkownik może ją poprawić.
  Przycisk „uporządkuj schemat” przelicza układ od nowa.
- **Przewody nie są zapisywane jako geometria** — trasa liczona przy rysowaniu, w każdym
  widoku po swojemu. Opcjonalnie zapisywane są punkty pośrednie dodane ręcznie.

### 5.6 Tryby ekranu
- **Edycja:** paleta elementów (szuflada z kategoriami, ikony zgodne z bieżącym widokiem),
  przeciąganie, połączenia, panel właściwości po przytrzymaniu.
- **Symulacja:** stan linii, animacja tłoka, czujniki i lampki zmieniają kolor;
  przyciski klikalne; ręczne przesterowanie zaworu (jak przycisk ręczny na cewce).
- Na tablecie widok dzielony: LAD + schemat; można też pokazać obok siebie
  widok obrazkowy i symbolowy.

### 5.7 Szablony
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

## 8. Architektura

### 8.1 Decyzje

| Obszar | Wybór | Uzasadnienie |
|---|---|---|
| Framework | **Flutter (Dart)** | Android + iOS z jednej bazy, własne rysowanie przez `CustomPainter` przy 60 fps |
| Rdzeń | czyste pakiety Dart bez zależności od Fluttera | testowalne jednostkowo, możliwe uruchamianie symulacji w testach i z linii poleceń |
| Stan aplikacji | Riverpod | przewidywalny, testowalny, bez globalnych singletonów |
| Model danych | niemutowalne klasy; w pakietach rdzenia pisane ręcznie, bez generatorów kodu (zero zależności); serializacja JSON dodawana razem z zapisem projektu | łatwe cofnij/ponów i zapis projektu |
| Cofnij/ponów | wzorzec Command na modelu dokumentu | jedna historia dla edycji w obu widokach |
| Grafika — widok symbolowy | rysowana kodem (`CustomPainter`) | symbole są proste i muszą reagować na stan (przesuwanie pól zaworu) |
| Grafika — widok obrazkowy | warstwy SVG (korpus, tłoczysko, dioda…) składane i animowane w kodzie | realistyczny wygląd bez rysowania wszystkiego ręcznie w kodzie |
| Zapis | lokalne pliki JSON z numerem wersji formatu | migracje przy zmianach formatu |

### 8.2 Warstwy i pakiety

```
packages/
  plc_core/        # czysty Dart: model LAD, kompilator do IR, runtime, timery, liczniki,
                   # zbocza, komparatory, tablica tagów
  plant_core/      # czysty Dart: katalog typów elementów, porty, połączenia, zamocowania
                   # czujników, propagacja stanów linii, dynamika siłowników
  sim_engine/      # czysty Dart: zegar symulacji, sprzężenie PLC <-> obiekt, scenariusze testowe
app/
  lib/
    features/
      lad_editor/      # UI edytora LAD + monitoring
      plant_editor/    # wspólna logika edycji schematu (zaznaczanie, przeciąganie, łączenie)
        views/
          symbolic/    # renderery symboli ISO/IEC
          pictorial/   # renderery obrazkowe + zasoby SVG
      tags/            # tablica tagów i obserwacji
      projects/        # lista projektów, zapis/odczyt, szablony
    shared/            # motyw, komponenty UI
  test/
```

### 8.3 Katalog elementów — jeden typ, dwa renderery

Każdy typ elementu jest opisany raz i ma dwa renderery:

```dart
// plant_core — logika, bez UI
abstract class ElementType {
  String get id;                       // np. 'valve_5_2_mono'
  List<PortDef> get ports;             // np. 1, 2, 4, 3, 5, Y1
  ParamSchema get params;              // parametry edytowalne w panelu właściwości
  ElementBehavior createBehavior();    // reakcja na stan linii, cewek, czas
}

// app — wygląd, osobno dla każdego widoku
abstract class ElementRenderer {
  Size size(ElementInstance e);
  Offset portAnchor(ElementInstance e, String portId); // porty leżą w innych miejscach w każdym widoku
  Rect? mountZone(ElementInstance e);                  // np. obszar korpusu siłownika do montażu czujników
  void paint(Canvas c, ElementInstance e, ElementState? s); // s == null w trybie edycji
}
```

Dodanie nowego elementu = definicja typu + renderer symbolowy + renderer obrazkowy
+ wpis w palecie. Reszta (edycja, zapis, symulacja, walidacja) działa bez zmian.

### 8.4 Model dokumentu (format projektu)

```
Project
├─ tags[]                      nazwa, adres, typ, komentarz
├─ program
│  └─ networks[]               drzewo Series/Parallel z instrukcjami
└─ plant
   ├─ elements[]               id, typeId, params, adresy %I/%Q
   ├─ connections[]            (elementId.port) ↔ (elementId.port)
   ├─ mounts[]                 czujnik → siłownik, pozycja na skoku
   └─ layouts
      ├─ symbolic  { elementId → x, y, obrót; punkty pośrednie przewodów }
      └─ pictorial { elementId → x, y, obrót; punkty pośrednie przewodów }
```

### 8.5 Pętla symulacji

Stały krok czasu (domyślnie 10 ms), niezależny od częstotliwości odświeżania ekranu:

```
co krok:
  1. obiekt: aktualizacja pozycji siłowników, stanów linii, czujników
  2. PLC: odczyt czujników/przycisków → obraz wejść
  3. PLC: wykonanie programu (jeden cykl skanowania)
  4. PLC: obraz wyjść → cewki zaworów, lampki
ekran (60 fps): rysuje ostatni stan (snapshot), niczego nie liczy
```

Zegar z akumulatorem pozwala na pauzę, krok o jeden cykl i zmianę tempa bez zmiany wyników.
Symulacja jest deterministyczna, więc te same wejścia zawsze dają ten sam przebieg — podstawa
testów i przyszłych ćwiczeń z automatyczną weryfikacją.

## 9. Plan etapów

1. ✅ **Silnik PLC** (`packages/plc_core`) — model LAD, IR, cykl skanowania, logika bitowa, zbocza,
   TON/TOF/TP/TONR, CTU/CTD/CTUD, komparatory; testy jednostkowe.
2. ✅ **Silnik schematu** (`packages/plant_core`) — model elementów i portów, propagacja stanów linii,
   zawory 3/2, 5/2, 5/3, siłowniki, dławiki, kontaktrony, czujniki indukcyjne i krańcowe, presostat;
   testy jednostkowe.
   ✅ **Sprzężenie** (`packages/sim_engine`) — powiązania sygnałów z adresami PLC, wspólna pętla
   czasu, zegar symulacji; testy end-to-end (sekwencja A+ B+ A- B-).
3. **Edytor LAD** — sieci, gałęzie, tagi, zapis projektu.
4. **Edytor schematów — widok symbolowy** — paleta, przeciąganie, przewody, montaż czujników
   na siłowniku, właściwości, walidacja. Widok symbolowy pierwszy, bo grafika rysowana kodem
   jest gotowa szybciej i weryfikuje mechanikę edytora.
5. **Edytor schematów — widok obrazkowy** — zasoby SVG, renderery obrazkowe, automatyczne
   rozmieszczenie między widokami.
6. **Integracja i monitoring w UI** — RUN/STOP, podgląd przepływu prądu, animacja schematu, wymuszanie.
7. **Rozszerzenia** — moduł I/O z okablowaniem, taśmociąg i detale (czujniki pojemnościowe
   i optyczne w praktyce), szablony i ćwiczenia z automatyczną weryfikacją.

## 10. Ryzyka i decyzje

- **Edytor schematów na telefonie** — rysowanie przewodów palcem na małym ekranie jest
  trudne. Konieczne: przyciąganie do portów, powiększanie portu przy dotyku, automatyczne
  prowadzenie przewodów. Tryb okablowania elektrycznego przesunięty na później.
- **Zakres** — dwa pełne edytory (LAD + schemat) to praktycznie dwie aplikacje.
  Etapy 1–2 bez UI pozwalają wcześnie zweryfikować logikę.
- **Wierność fizyki** — model jakościowy celowo pomija ciśnienia, siły i masy.
  Należy to jasno komunikować.
- **Grafika widoku obrazkowego** — to największy koszt nie-programistyczny. Każdy element
  wymaga zestawu warstw SVG w spójnym stylu. Plan: na start własne, płaskie ilustracje wektorowe;
  docelowo ewentualnie grafik.
- **Synchronizacja dwóch widoków** — wymaga dyscypliny: każda operacja edycji działa na
  wspólnym modelu, widoki są tylko projekcją. Żadnej logiki zależnej od widoku w `plant_core`.
- **Znaki towarowe** — bez nazw i grafik Siemens ani producentów pneumatyki (np. Festo, SMC)
  w ilustracjach.
