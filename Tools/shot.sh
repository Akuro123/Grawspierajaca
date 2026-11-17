#!/bin/bash
# Użycie: Tools/shot.sh <plik.png> [argumenty uruchomienia] – instaluje Debug na symulatorze i robi zrzut po 5 s.
D="iPhone 18 Pro"; OUT="$1"; shift
APP=$(find ~/Library/Developer/Xcode/DerivedData/RehabRunner-*/Build/Products/Debug-iphonesimulator -name RehabRunner.app -maxdepth 1 | head -1)
xcrun simctl boot "$D" 2>/dev/null; xcrun simctl install "$D" "$APP"
xcrun simctl terminate "$D" com.example.RehabRunner 2>/dev/null
xcrun simctl launch "$D" com.example.RehabRunner "$@" >/dev/null
sleep "${SHOT_DELAY:-5}"; xcrun simctl io "$D" screenshot "$OUT" 2>/dev/null
