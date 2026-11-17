# Rehab Runner

Gra biegowa na iPhone'a (SwiftUI + SpriteKit) sterowana ruchem z Apple Watcha (Core Motion + WatchConnectivity), z warstwą rehabilitacyjną: profil pacjenta, poziomy trudności, statystyki i przypomnienia. Zapis lokalny w SwiftData. Bez konta, serwera i zapisu surowych danych czujnika.

> **Uwaga:** aplikacja rozpoznaje ruch, ale **nie ocenia poprawności techniki** ani nie mierzy poprawy sprawności. Zestaw ćwiczeń i zakresy ruchu powinien zatwierdzić fizjoterapeuta. To nie jest wyrób medyczny.

## Wymagania
Xcode 27 (testowane na 27.2), iOS 17+, watchOS 10+. Projekt jest generowany z `project.yml` (XcodeGen); `RehabRunner.xcodeproj` jest w repozytorium. Po zmianie `project.yml`: `xcodegen generate`.

## Grafika, silnik i dźwięk
Gra używa **SceneKit (3D)** zamiast SpriteKit. Modele (postać RobotExpressive z klipami biegu/skoku/siadu; budynki, drogi, drzewa, ciężarówki, monety Kenney) są w `iOS/Resources/Models`, licencje w `iOS/Resources/LICENSES.md`. SceneKit nie czyta glTF, więc `iOS/Game3D/GLTFLoader.swift` wczytuje `.glb` (hierarchia, materiały, tekstury, klipy animacji z własnym miksowaniem).
- **Scena**: `RunnerScene3D` (kamera za postacią z lekkim podążaniem i wstrząsem, trzy tory, droga z kafelków, dwa rzędy dekoracji, mgła, trójpunktowe światło, cząsteczki). Strefy (Park → Miasto → Zachód → Noc) zmieniają niebo, światło, mgłę, poświatę okien i zestaw budynków.
- **Postać**: animacje z klipów (bieg dopasowany do prędkości świata, skok mapowany na postęp skoku z silnika, siad dla kucania i ślizgu, pochylenie przy zmianie toru). Dłonie robota są przypięte sztywno do kości (bez skinningu palców).
- **Co zostało z poprzedniej wersji**: cała logika (`RunnerEngine`, sesja, łączność z zegarkiem, SwiftData) jest niezależna od renderowania, więc migracja 2D → 3D **nie zmieniła** integracji z Apple Watchem ani zapisu danych. Silnik jest krokowany z `CADisplayLink` na wątku głównym.
- **Wersja 2D sprite'ów** (`Tools/GenerateArt.swift`) służy już tylko do nieba, chmury w menu, cienia, iskier, kurzu, tablicy bramki i ikony. Dźwięki: `Tools/GenerateSounds.py`.
- Podgląd wyglądu w symulatorze: `Tools/shot.sh plik.png -debugDemo [-debugZone 0-3] [-debugPose jump|slide|crouch]`.

## Gesty (Apple Watch)
Detektor ma dwie ścieżki, wybierane w `GestureMode` (zależnie od trudności):
- **Kąty (powolne ruchy)**: pochylenie przedramienia w górę/dół, odchylenie w lewo/prawo względem pozycji neutralnej, utrzymane przez `angleHold`. **Nie zależy od szybkości ruchu**, więc pacjent może ćwiczyć powoli. Wymaga orientacji (`CMDeviceMotion.attitude`, układ `xArbitraryZVertical`).
- **Machnięcia (szybkie)**: dotychczasowa detekcja po przyspieszeniu (tryb Aktywny i „Oba”).
- **Kucanie** = obrót przedramienia (oś roll) przy spokojnym ramieniu; **ślizg** = pochylenie w dół. To osobne osie, a ruchy mieszane (pochylenie i obrót naraz, przekątna) są odrzucane.
- Blokada do powrotu w tolerancję neutralnej, kompensacja dryfu żyroskopu (gdy ręka spoczywa >2 s blisko neutralnej), histereza, hold dla odfiltrowania drżenia i muśnięć.
- **Ekran diagnostyczny** (Ustawienia lub Kalibracja → „Ekran diagnostyczny”): pochylenie, odchylenie, obrót, przyspieszenie, stan detektora, log gestów oraz ping RTT i wiek ostatnich danych. Zegarek wysyła telemetrię ~5 Hz tylko w trybie testera.

## Schematy
- **RehabRunner**: aplikacja iPhone'a razem z aplikacją na Watcha (osadzoną). Używaj go do uruchamiania i testów.
- **RehabRunnerWatch**: sama aplikacja zegarka (do uruchamiania na symulatorze lub zegarku).

## Demo bez zegarka (symulator)
1. Wybierz schemat **RehabRunner** i symulator iPhone'a, naciśnij Run.
2. Na ekranie Start wybierz **Demo bez zegarka**.
3. Sterowanie: swipe w lewo/prawo (zmiana toru), w górę (skok), w dół (ślizg). Kucanie: przytrzymaj przycisk **Kucaj**; puszczenie kończy kucanie.
4. Demo nie trafia do historii. Potknięcie nie kończy gry.

W buildzie Debug przy sesji ćwiczeń na symulatorze (bez zegarka) dostępny jest przycisk „DEBUG: wykonaj”, który wstrzykuje zdarzenie tak, jakby przyszło z zegarka. Argumenty uruchomienia `-debugDemo`, `-debugExercise`, `-debugHistory` omijają menu.

## Sesja ćwiczeń
Start → Graj → profil pacjenta (kończyna: lewa/prawa ręka lub noga, ćwiczenia, trudność, powtórzenia, limit czasu, zatwierdzenie terapeuty) → Kalibracja → Gra → Podsumowanie (gwiazdki, odznaki). Gra pokazuje duży symbol ruchu i czeka bez limitu czasu. Moneta za każde ukończone powtórzenie, bez kar i bez premii za siłę ruchu. Poziom rośnie co 5 powtórzeń i zmienia strefę. **Pauza** jest dostępna zawsze (czas stoi, ruchy są pomijane). Sesja kończy się po liczbie powtórzeń lub po ustawionym czasie.

Poziomy trudności (`Difficulty`): Łagodny / Standardowy / Aktywny zmieniają progi detektora, czasy przytrzymania, przerwę po powtórzeniu i wizualne tempo świata. Żaden nie narzuca limitu czasu na ruch.

## Dane i statystyki
SwiftData: `PatientProfile` (profil, ustawienia sesji, zatwierdzenie terapeuty) i `ExerciseSessionRecord` (data, czas, kończyna, trudność, powtórzenia per ćwiczenie, monety, punkty, poziom). Panel **Postępy**: wykresy dzień/tydzień/miesiąc (Swift Charts), seria dni, regularność z 30 dni, odznaki, historia z filtrem kończyny. Logika w `iOS/Data/Rehab.swift` (czyste funkcje, testy). Architektura (profil i sesje oddzielone, `patientID` w sesji) pozwala dodać panel fizjoterapeuty i synchronizację bez zmian modelu.

| Ruch ręki | Akcja |
|---|---|
| w lewo / w prawo | zmiana toru |
| w górę | skok |
| krótki ruch w dół | ślizg |
| lekki obrót przedramienia i utrzymanie | kucanie; powrót do neutralnej kończy |

Profil **Noga**: jeden ruch w siadzie. Zmiana nachylenia podudzia = skok, powrót do pozycji wyjściowej = pełne powtórzenie.

### Kalibracja i tester
Na ekranie Kalibracja ustaw rękę z zegarkiem (lewa/prawa), naciśnij **Ustaw pozycję neutralną** (zegarek odlicza 2 s i mierzy 1,2 s; trzymaj nieruchomo). Tester pokazuje nazwę wykrytego gestu (na iPhonie i na zegarku), bez zaliczania. Progi i czasy (wejście/wyjście, przytrzymanie, blokada) są w sekcji „Zaawansowane” oraz w Ustawieniach na zegarku.

### Jak działa detektor
- Ruchy kierunkowe: przyspieszenie bez grawitacji (`userAcceleration`) w układzie wyznaczonym z pozycji neutralnej; okno decyzyjne wybiera dominujący kierunek, a ruch w przeciwną stronę na tej samej osi (hamowanie, powrót ręki) jest odrzucany.
- Po akcji detektor jest zablokowany do powrotu ręki do neutralnej (spoczynek przez zadany czas i kąt poniżej progu wyjścia). Powrót nie wyzwala przeciwnego gestu.
- Kucanie: obrót względem skalibrowanej pozycji, osobne progi wejścia i wyjścia (histereza) i czas przytrzymania. Gwałtowny ruch resetuje próbę kucania, więc jedno machnięcie nie da jednocześnie ślizgu i kucania.
- Kod: `Shared/GestureDetector.swift`, `Shared/LegRepDetector.swift`. Detektor nie zna sceny gry; dotyk i zegarek wywołują te same `GameAction` w `RunnerEngine`.

### Łączność
iPhone wysyła start, stop i konfigurację; zegarek analizuje ruch lokalnie i wysyła wyłącznie zdarzenia (ID sesji, ID powtórzenia, akcja, faza). iPhone odrzuca duplikaty i zdarzenia ze starych sesji. Gdy łączność zniknie (brak osiągalności ponad 2 s lub brak heartbeatu ponad 8 s), gra zatrzymuje się, a zaliczone powtórzenia zostają. Po powrocie łączności aplikacja prosi o ponowne ustawienie pozycji neutralnej przed wznowieniem.

## Uruchomienie na sparowanym iPhonie i Watchu
1. W Xcode: projekt **RehabRunner** → każdy z targetów (`RehabRunner`, `RehabRunnerWatch`, `RehabRunnerTests`) → *Signing & Capabilities* → wybierz swój **Team**.
2. Zmień prefiks identyfikatora `com.example` na własny, spójnie we wszystkich targetach i w `project.yml`. Identyfikator zegarka musi mieć postać `<iPhone>.watchkitapp`, a `WKCompanionAppBundleIdentifier` musi wskazywać identyfikator iPhone'a.
3. Włącz tryb programisty na iPhonie i zegarku, połącz iPhone'a kablem, wybierz schemat **RehabRunner** i swój iPhone, naciśnij Run. Aplikacja na zegarek zainstaluje się automatycznie (może to potrwać; sprawdź też aplikację Watch na iPhonie).
4. Otwórz aplikację na zegarku przed rozpoczęciem sesji. Zezwól na dostęp do ruchu i powiadomień.

## Przypomnienia
Lokalne powiadomienia w wybrane dni tygodnia o wybranej godzinie (ekran Przypomnienia).

## Archiwizacja (Release)
1. Ustaw Team i własny prefiks identyfikatorów (jak wyżej).
2. Xcode → wybierz schemat **RehabRunner** i *Any iOS Device (arm64)* → Product → Archive → Distribute App (TestFlight / Ad Hoc).
3. Z wiersza poleceń (po podpisaniu): `xcodebuild archive -scheme RehabRunner -configuration Release -destination 'generic/platform=iOS' -archivePath build/RehabRunner.xcarchive`.
4. Przed TestFlight dodaj ikonę/zrzuty w App Store Connect i politykę prywatności (aplikacja nie zbiera danych poza urządzeniem).

## Testy
`xcodebuild test -scheme RehabRunner -destination 'platform=iOS Simulator,name=iPhone 18 Pro' CODE_SIGNING_ALLOWED=NO`
Testy logiki (53; w tym detekcja z orientacji na próbkach syntetycznych, test mutacyjny dryfu sprawdzony ręcznie): gesty, noga, duplikaty i stare sesje, utrata łączności, silnik gry, pauza, limit czasu, trudność, statystyki, serie, odznaki, SwiftData (profil i sesje), przypomnienia.

## Przed wdrożeniem rehabilitacyjnym (poza zakresem kodu)
- Walidacja z fizjoterapeutami: dobór ćwiczeń, zakresy ruchu, domyślne progi i poziomy trudności.
- Ocena bezpieczeństwa i ryzyka (np. zmęczenie, ból, upadek przy ćwiczeniu w siadzie/staniu) oraz instrukcja użytkownika.
- Analiza prawna: czy przy zamierzonym zastosowaniu aplikacja jest wyrobem medycznym (MDR/oprogramowanie medyczne), RODO dla danych o zdrowiu, wymogi sklepów App Store.
- Testy z pacjentami (dostępność: Dynamic Type, VoiceOver, kontrast).

## Co wymaga sprawdzenia na prawdziwym urządzeniu
- **Płynność 60 FPS** na iPhonie (SceneKit; ok. 700 węzłów, z czego większość ukryta); w symulatorze nie mierzono. Jeśli spadnie, zmniejsz `tileCount`, wyłącz `multisampling4X` w `Game3DView`.
- Czucie animacji postaci i dźwięków.
- **Działanie zegarka poza nadgarstkiem trzeba sprawdzić na prawdziwym urządzeniu.** Symulator nie dostarcza ruchu, a testy używają próbek syntetycznych.
- **Detekcja z orientacji**: czy osie (+Y = palce) i znaki pochylenia/odchylenia zgadzają się na prawdziwym nadgarstku (lewym i prawym, różne ustawienia korony), czy dryf żyroskopu przez kilka minut nie psuje neutralnej, czy progi 25° są sensowne dla pacjenta. Testy używają próbek syntetycznych, nie prawdziwych ruchów.
- Opóźnienie WatchConnectivity (ekran Diagnostyka) i dostarczanie `sendMessage` przy opuszczonym nadgarstku.
- Orientacja osi dla lewego/prawego nadgarstka i ustawienia korony (użyj testera i przełącznika ręki), domyślne progi, czułość kucania.
- Zachowanie `WKExtendedRuntimeSession` (tryb `physical-therapy`) i łączności przy opuszczonym nadgarstku oraz ponowne połączenie.
- Dostarczanie zdarzeń zakolejkowanych (`transferUserInfo`) po utracie łączności.
- Powiadomienia o określonej godzinie na prawdziwym iPhonie.
