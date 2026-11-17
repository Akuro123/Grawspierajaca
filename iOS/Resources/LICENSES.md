# Licencje zasobów

## Modele 3D (`iOS/Resources/Models`)
Pobrane z publicznych repozytoriów GitHub; pełne teksty licencji w `Models/licenses/`.

| Zasób | Autor / źródło | Licencja |
|---|---|---|
| `RobotExpressive.glb` (postać, klipy Running/Jump/Sitting/Idle/Wave) | Tomás Laulhé (Quaternius/modyfikacje: Don McCurdy), repozytorium three.js `examples/models/gltf/RobotExpressive` | CC0 1.0 (domena publiczna) |
| `city_*.glb` (budynki, drogi, chodniki, trawa i drzewa) | Kenney (kenney.nl), `KenneyNL/Starter-Kit-City-Builder` | MIT dla kodu startowego, zasoby Kenney CC0 |
| `race_*.glb` (ciężarówki, motocykl) | Kenney, `KenneyNL/Starter-Kit-Racing` | j.w. |
| `plat_*.glb` (moneta, klocek) | Kenney, `KenneyNL/Starter-Kit-3D-Platformer` | j.w. |
| `colormap_city.png`, `colormap_race.png` | Kenney | CC0 |

Kenney nie wymaga atrybucji (CC0), ale jest podana z szacunku dla autora. Przed publikacją w sklepie zweryfikuj aktualne warunki w repozytoriach źródłowych.

## Własne
- **Sprite'y 2D** (`iOS/Resources/Sprites`: niebo, chmura, cień, iskry, kurz, tablica bramki) i **ikona aplikacji**: generowane kodem `Tools/GenerateArt.swift`.
- **Bramka (portal ze znakiem)** w scenie 3D: proste bryły SceneKit z własną teksturą (jedyny element 3D zbudowany w kodzie).
- **Dźwięki** (`iOS/Resources/Sounds`): syntezowane `Tools/GenerateSounds.py`.
- **Ikony interfejsu**: SF Symbols (Apple).

Nie użyto materiałów Subway Surfers ani innych chronionych zasobów.
