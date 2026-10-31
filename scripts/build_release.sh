#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Car Parking Jam 3D - Production Release Build Script (App Store & Play Store)
# ==============================================================================
# Usage:
#   ./scripts/build_release.sh
#
# Optional environment overrides for live Google AdMob & Unity Ads credentials:
#   export ADMOB_ANDROID_APP_ID="ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY"
#   export ADMOB_IOS_APP_ID="ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY"
#   export ADMOB_ANDROID_BANNER_ID="ca-app-pub-XXXXXXXXXXXXXXXX/YYYYYYYYYY"
#   export ADMOB_ANDROID_INTERSTITIAL_ID="ca-app-pub-XXXXXXXXXXXXXXXX/YYYYYYYYYY"
#   export ADMOB_ANDROID_REWARDED_ID="ca-app-pub-XXXXXXXXXXXXXXXX/YYYYYYYYYY"
#   export ADMOB_IOS_BANNER_ID="ca-app-pub-XXXXXXXXXXXXXXXX/YYYYYYYYYY"
#   export ADMOB_IOS_INTERSTITIAL_ID="ca-app-pub-XXXXXXXXXXXXXXXX/YYYYYYYYYY"
#   export ADMOB_IOS_REWARDED_ID="ca-app-pub-XXXXXXXXXXXXXXXX/YYYYYYYYYY"
#   export UNITY_ANDROID_GAME_ID="5718492"
#   export UNITY_IOS_GAME_ID="5718493"
# ==============================================================================

DART_DEFINES=(
  "--dart-define=USE_TEST_ADS=${USE_TEST_ADS:-false}"
)

if [[ -n "${ADMOB_ANDROID_BANNER_ID:-}" ]]; then
  DART_DEFINES+=("--dart-define=ADMOB_ANDROID_BANNER_ID=${ADMOB_ANDROID_BANNER_ID}")
fi
if [[ -n "${ADMOB_ANDROID_INTERSTITIAL_ID:-}" ]]; then
  DART_DEFINES+=("--dart-define=ADMOB_ANDROID_INTERSTITIAL_ID=${ADMOB_ANDROID_INTERSTITIAL_ID}")
fi
if [[ -n "${ADMOB_ANDROID_REWARDED_ID:-}" ]]; then
  DART_DEFINES+=("--dart-define=ADMOB_ANDROID_REWARDED_ID=${ADMOB_ANDROID_REWARDED_ID}")
fi
if [[ -n "${ADMOB_IOS_BANNER_ID:-}" ]]; then
  DART_DEFINES+=("--dart-define=ADMOB_IOS_BANNER_ID=${ADMOB_IOS_BANNER_ID}")
fi
if [[ -n "${ADMOB_IOS_INTERSTITIAL_ID:-}" ]]; then
  DART_DEFINES+=("--dart-define=ADMOB_IOS_INTERSTITIAL_ID=${ADMOB_IOS_INTERSTITIAL_ID}")
fi
if [[ -n "${ADMOB_IOS_REWARDED_ID:-}" ]]; then
  DART_DEFINES+=("--dart-define=ADMOB_IOS_REWARDED_ID=${ADMOB_IOS_REWARDED_ID}")
fi
if [[ -n "${UNITY_ANDROID_GAME_ID:-}" ]]; then
  DART_DEFINES+=("--dart-define=UNITY_ANDROID_GAME_ID=${UNITY_ANDROID_GAME_ID}")
fi
if [[ -n "${UNITY_IOS_GAME_ID:-}" ]]; then
  DART_DEFINES+=("--dart-define=UNITY_IOS_GAME_ID=${UNITY_IOS_GAME_ID}")
fi

echo "==> Running Flutter Analyze & Tests..."
flutter analyze
flutter test

echo "==> Building Google Play Store App Bundle (.aab)..."
flutter build appbundle --release "${DART_DEFINES[@]}"
echo "    Android App Bundle ready at: build/app/outputs/bundle/release/app-release.aab"

echo "==> Building Apple App Store IPA Archive..."
flutter build ipa --release "${DART_DEFINES[@]}"
echo "    iOS Archive ready at: build/ios/archive/Runner.xcarchive"
