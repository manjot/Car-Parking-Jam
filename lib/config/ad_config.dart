import 'package:flutter/foundation.dart';

/// Centralized configuration for Google AdMob and Unity Ads.
///
/// Configured with the live production AdMob App/Ad Unit IDs and Unity Ads
/// Game/Placement IDs for "Car Parking Jam 3D: Unlimited", while using official
/// test IDs when running in `kDebugMode` so development testing remains policy-safe.
class AdConfig {
  AdConfig._();

  /// Uses test ads in debug mode (`kDebugMode`) and live production ads in
  /// release builds (`--release`).
  static const bool useTestAds = bool.fromEnvironment(
    'USE_TEST_ADS',
    defaultValue: kDebugMode,
  );

  // ===========================================================================
  // GOOGLE ADMOB IDS (Live Production + Debug Test Fallback)
  // ===========================================================================

  static const String admobAndroidAppId = String.fromEnvironment(
    'ADMOB_ANDROID_APP_ID',
    defaultValue: 'ca-app-pub-4106606850293358~3032460547',
  );

  static const String admobIosAppId = String.fromEnvironment(
    'ADMOB_IOS_APP_ID',
    defaultValue: 'ca-app-pub-4106606850293358~2080798964',
  );

  static String get admobBannerAdUnitId {
    if (defaultTargetPlatform == TargetPlatform.android) {
      if (useTestAds) return 'ca-app-pub-3940256099942544/6300978111';
      return const String.fromEnvironment(
        'ADMOB_ANDROID_BANNER_ID',
        defaultValue: 'ca-app-pub-4106606850293358/1366483096',
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      if (useTestAds) return 'ca-app-pub-3940256099942544/2934735716';
      return const String.fromEnvironment(
        'ADMOB_IOS_BANNER_ID',
        defaultValue: 'ca-app-pub-4106606850293358/7532436191',
      );
    }
    return '';
  }

  static String get admobInterstitialAdUnitId {
    if (defaultTargetPlatform == TargetPlatform.android) {
      if (useTestAds) return 'ca-app-pub-3940256099942544/1033173712';
      return const String.fromEnvironment(
        'ADMOB_ANDROID_INTERSTITIAL_ID',
        defaultValue: 'ca-app-pub-4106606850293358/6427238083',
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      if (useTestAds) return 'ca-app-pub-3940256099942544/4411468910';
      return const String.fromEnvironment(
        'ADMOB_IOS_INTERSTITIAL_ID',
        defaultValue: 'ca-app-pub-4106606850293358/5660951327',
      );
    }
    return '';
  }

  static String get admobRewardedAdUnitId {
    if (defaultTargetPlatform == TargetPlatform.android) {
      if (useTestAds) return 'ca-app-pub-3940256099942544/5224354917';
      return const String.fromEnvironment(
        'ADMOB_ANDROID_REWARDED_ID',
        defaultValue: 'ca-app-pub-4106606850293358/4292029338',
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      if (useTestAds) return 'ca-app-pub-3940256099942544/1712485313';
      return const String.fromEnvironment(
        'ADMOB_IOS_REWARDED_ID',
        defaultValue: 'ca-app-pub-4106606850293358/4509193742',
      );
    }
    return '';
  }

  // ===========================================================================
  // UNITY ADS IDS (Live Production IDs for Car Parking Jam 3D)
  // ===========================================================================

  static String get unityGameId {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return const String.fromEnvironment(
        'UNITY_ANDROID_GAME_ID',
        defaultValue: '800418997',
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      return const String.fromEnvironment(
        'UNITY_IOS_GAME_ID',
        defaultValue: '800419006',
      );
    }
    return '800418997';
  }

  static String get unityBannerPlacementId {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return const String.fromEnvironment(
        'UNITY_ANDROID_BANNER_PLACEMENT',
        defaultValue: 'BP_Banner_Android',
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      return const String.fromEnvironment(
        'UNITY_IOS_BANNER_PLACEMENT',
        defaultValue: 'BP_Banner_iOS',
      );
    }
    return 'BP_Banner_Android';
  }

  static String get unityInterstitialPlacementId {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return const String.fromEnvironment(
        'UNITY_ANDROID_INTERSTITIAL_PLACEMENT',
        defaultValue: 'BP_Interstitial_Android',
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      return const String.fromEnvironment(
        'UNITY_IOS_INTERSTITIAL_PLACEMENT',
        defaultValue: 'BP_Interstitial_iOS',
      );
    }
    return 'BP_Interstitial_Android';
  }

  static String get unityRewardedPlacementId {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return const String.fromEnvironment(
        'UNITY_ANDROID_REWARDED_PLACEMENT',
        defaultValue: 'BP_Rewarded_Android',
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      return const String.fromEnvironment(
        'UNITY_IOS_REWARDED_PLACEMENT',
        defaultValue: 'BP_Rewarded_iOS',
      );
    }
    return 'BP_Rewarded_Android';
  }

  /// Show an interstitial ad every N completed levels.
  static const int interstitialLevelFrequency = 2;
}
