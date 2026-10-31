# Car Parking Jam 3D — Unlimited Levels (Flutter + Google AdMob + Unity Ads)

A 3D **Car Parking Jam** puzzle game built with Flutter, featuring a custom 3D isometric/perspective rendering engine, a mathematically guaranteed **100% solvable unlimited procedural level generator (Level 1 → ∞)**, and dual-network ad monetization (**Google AdMob** + **Unity Ads** waterfall/round-robin mediation).

## Features

- **Unlimited Solvable 3D Levels (`1 → ∞`)**:
  - Uses a reverse-dependency ray-intersection placement algorithm (`lib/services/level_generator.dart`) so every generated level from Level 1 to Level 999,999,999+ is guaranteed solvable while creating deep interlocking chains.
  - Scales grid sizes from `6×6` up to `10×10`, introducing Boss Levels every 5 levels, internal bollards/hydrants/chargers, perimeter barrier curbs, and 3-cell vehicles (buses, limos, fire trucks).
  - Includes an **Unlimited Level Selector** allowing players to jump to any level number on demand.
- **Custom 3D Rendering Engine (`lib/rendering/parking_3d_painter.dart`)**:
  - Real-time 3D projection & depth-sorted Painter's Algorithm with interactive **3D Camera Orbit/Pitch** controls.
  - Detailed 3D extruded vehicles (sedans, sports cars with spoilers, police cars with flashing lightbars, taxis, SUVs, pickups, buses, fire trucks, and VIP gold cars) with suspension pitch on collision, exhaust smoke, spark particles, and 90° highway exit turns.
- **Google AdMob & Unity Ads Monetization (`lib/services/ad_service.dart`)**:
  - **Banner Ads**: Adaptive AdMob bottom banner with automatic fallback to `UnityBannerAd`.
  - **Interstitial Ads**: Shown between completed levels using configurable mediation (`roundRobin`, `admobPrimaryUnityFallback`, `unityPrimaryAdmobFallback`).
  - **Rewarded Video Ads**: Used for **2X Level Coins**, **+200 Garage Coins**, **Auto-Hint Boosters**, **VIP Helicopter Airlift**, and **Lot Shuffle**.
  - Includes an in-app **Ad Mediation Console** (megaphone icon in top-right HUD) to test AdMob & Unity Ads placements directly.

## Quick Start

```bash
flutter pub get
flutter test
flutter run
```

## Production Build & Store Release

Update your live AdMob & Unity Ads IDs in `lib/config/ad_config.dart` (or pass via `--dart-define`), `android/app/src/main/AndroidManifest.xml`, and `ios/Runner/Info.plist`, then run:

```bash
chmod +x scripts/build_release.sh
./scripts/build_release.sh
```
