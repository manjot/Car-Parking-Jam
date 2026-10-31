import 'package:flutter/foundation.dart';

/// Centralized configuration for Google AdMob and Unity Ads.
///
/// By default, official Google AdMob and Unity Ads test IDs are used in debug/test
/// mode so you can test banners, interstitials, and rewarded ads safely without
/// policy violations.
///
/// For production App Store & Play Store builds, pass your live IDs via
/// `--dart-define` (see `scripts/build_release.sh`) or update the constants below.
class AdConfig {
  AdConfig._();

  /// Whether to use test ads. Defaults to `false` in release builds when custom
  /// production IDs are supplied via `--dart-define=USE_TEST_ADS=false`.
  static const bool useTestAds = bool.fromEnvironment(
    'USE_TEST_ADS',
    defaultValue: kDebugMode,
  );

  // ===========================================================================
  // GOOGLE ADMOB IDS
  // ===========================================================================

  static const String admobAndroidAppId = String.fromEnvironment(
    'ADMOB_ANDROID_APP_ID',
    defaultValue: 'ca-app-pub-3940256099942544~3347511713',
  );

  static const String admobIosAppId = String.fromEnvironment(
    'ADMOB_IOS_APP_ID',
    defaultValue: 'ca-app-pub-3940256099942544~1458002511',
  );

  static String get admobBannerAdUnitId {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return const String.fromEnvironment(
        'ADMOB_ANDROID_BANNER_ID',
        defaultValue: 'ca-app-pub-3940256099942544/6300978111',
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      return const String.fromEnvironment(
        'ADMOB_IOS_BANNER_ID',
        defaultValue: 'ca-app-pub-3940256099942544/2934735716',
      );
    }
    return '';
  }

  static String get admobInterstitialAdUnitId {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return const String.fromEnvironment(
        'ADMOB_ANDROID_INTERSTITIAL_ID',
        defaultValue: 'ca-app-pub-3940256099942544/1033173712',
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      return const String.fromEnvironment(
        'ADMOB_IOS_INTERSTITIAL_ID',
        defaultValue: 'ca-app-pub-3940256099942544/4411468910',
      );
    }
    return '';
  }

  static String get admobRewardedAdUnitId {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return const String.fromEnvironment(
        'ADMOB_ANDROID_REWARDED_ID',
        defaultValue: 'ca-app-pub-3940256099942544/5224354917',
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      return const String.fromEnvironment(
        'ADMOB_IOS_REWARDED_ID',
        defaultValue: 'ca-app-pub-3940256099942544/1712485313',
      );
    }
    return '';
  }

  // ===========================================================================
  // UNITY ADS IDS
  // ===========================================================================

  static String get unityGameId {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return const String.fromEnvironment(
        'UNITY_ANDROID_GAME_ID',
        defaultValue: '5718492',
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      return const String.fromEnvironment(
        'UNITY_IOS_GAME_ID',
        defaultValue: '5718493',
      );
    }
    return '5718492';
  }

  static String get unityBannerPlacementId {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return const String.fromEnvironment(
        'UNITY_ANDROID_BANNER_PLACEMENT',
        defaultValue: 'Banner_Android',
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      return const String.fromEnvironment(
        'UNITY_IOS_BANNER_PLACEMENT',
        defaultValue: 'Banner_iOS',
      );
    }
    return 'Banner_Android';
  }

  static String get unityInterstitialPlacementId {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return const String.fromEnvironment(
        'UNITY_ANDROID_INTERSTITIAL_PLACEMENT',
        defaultValue: 'Interstitial_Android',
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      return const String.fromEnvironment(
        'UNITY_IOS_INTERSTITIAL_PLACEMENT',
        defaultValue: 'Interstitial_iOS',
      );
    }
    return 'Interstitial_Android';
  }

  static String get unityRewardedPlacementId {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return const String.fromEnvironment(
        'UNITY_ANDROID_REWARDED_PLACEMENT',
        defaultValue: 'Rewarded_Android',
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      return const String.fromEnvironment(
        'UNITY_IOS_REWARDED_PLACEMENT',
        defaultValue: 'Rewarded_iOS',
      );
    }
    return 'Rewarded_Android';
  }

  /// Show an interstitial ad every N completed levels.
  static const int interstitialLevelFrequency = 2;
}
