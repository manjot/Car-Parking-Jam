import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:unity_ads_plugin/unity_ads_plugin.dart';

import '../config/ad_config.dart';

enum AdNetwork {
  admob,
  unityAds,
}

enum MediationStrategy {
  admobPrimaryUnityFallback,
  unityPrimaryAdmobFallback,
  roundRobin,
}

/// Manages Google AdMob and Unity Ads initialization, preloading,
/// waterfall mediation, and banner/interstitial/rewarded display.
class AdService extends ChangeNotifier {
  AdService._();
  static final AdService instance = AdService._();

  bool _isInitialized = false;
  bool _admobReady = false;
  bool _unityReady = false;

  BannerAd? _admobBannerAd;
  bool _admobBannerLoaded = false;

  InterstitialAd? _admobInterstitialAd;
  bool _unityInterstitialLoaded = false;

  RewardedAd? _admobRewardedAd;
  bool _unityRewardedLoaded = false;

  MediationStrategy _strategy = MediationStrategy.roundRobin;
  AdNetwork _nextRoundRobinNetwork = AdNetwork.admob;

  int _admobImpressions = 0;
  int _unityImpressions = 0;
  int _rewardsGranted = 0;
  String _lastStatusMessage = 'Initializing AdMob & Unity Ads...';

  bool get isInitialized => _isInitialized;
  bool get admobReady => _admobReady;
  bool get unityReady => _unityReady;
  bool get admobBannerLoaded => _admobBannerLoaded;
  bool get admobInterstitialReady => _admobInterstitialAd != null;
  bool get unityInterstitialReady => _unityInterstitialLoaded;
  bool get admobRewardedReady => _admobRewardedAd != null;
  bool get unityRewardedReady => _unityRewardedLoaded;
  MediationStrategy get strategy => _strategy;
  int get admobImpressions => _admobImpressions;
  int get unityImpressions => _unityImpressions;
  int get rewardsGranted => _rewardsGranted;
  String get lastStatusMessage => _lastStatusMessage;

  bool _isTestEnvironment = false;

  @visibleForTesting
  void setTestEnvironment(bool value) {
    _isTestEnvironment = value;
  }

  bool get isMobilePlatform =>
      !_isTestEnvironment &&
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  void setMediationStrategy(MediationStrategy newStrategy) {
    _strategy = newStrategy;
    _log('Mediation strategy set to ${newStrategy.name}');
    notifyListeners();
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    if (!isMobilePlatform) {
      _admobReady = true;
      _unityReady = true;
      _unityInterstitialLoaded = true;
      _unityRewardedLoaded = true;
      _log('Desktop/Web preview mode: AdMob & Unity Ads simulator active');
      notifyListeners();
      return;
    }

    await Future.wait([
      _initAdMob(),
      _initUnityAds(),
    ]);
  }

  Future<void> _initAdMob() async {
    try {
      final status = await MobileAds.instance.initialize();
      _admobReady = true;
      _log('Google AdMob initialized (${status.adapterStatuses.length} adapters)');
      _loadAdMobBanner();
      _loadAdMobInterstitial();
      _loadAdMobRewarded();
    } catch (e) {
      _log('AdMob init error: $e');
    }
    notifyListeners();
  }

  Future<void> _initUnityAds() async {
    try {
      await UnityAds.setPrivacyConsent(PrivacyConsentType.gdpr, true);
      await UnityAds.setPrivacyConsent(PrivacyConsentType.ccpa, true);

      await UnityAds.init(
        gameId: AdConfig.unityGameId,
        testMode: AdConfig.useTestAds,
        onComplete: () {
          _unityReady = true;
          _log('Unity Ads initialized (gameId: ${AdConfig.unityGameId})');
          _loadUnityInterstitial();
          _loadUnityRewarded();
          notifyListeners();
        },
        onFailed: (error, message) {
          _log('Unity Ads init failed: ${error.name} - $message');
          notifyListeners();
        },
      );
    } catch (e) {
      _log('Unity Ads init exception: $e');
    }
    notifyListeners();
  }

  // ===========================================================================
  // BANNER ADS
  // ===========================================================================

  void _loadAdMobBanner() {
    if (!isMobilePlatform) return;
    final unitId = AdConfig.admobBannerAdUnitId;
    if (unitId.isEmpty) return;

    _admobBannerAd?.dispose();
    _admobBannerLoaded = false;

    _admobBannerAd = BannerAd(
      adUnitId: unitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          _admobBannerLoaded = true;
          _log('AdMob Banner loaded');
          notifyListeners();
        },
        onAdFailedToLoad: (ad, error) {
          _admobBannerLoaded = false;
          ad.dispose();
          _admobBannerAd = null;
          _log('AdMob Banner failed (${error.message}), falling back to Unity Banner');
          notifyListeners();
        },
      ),
    )..load();
  }

  Widget buildBannerAdWidget() {
    if (isMobilePlatform) {
      if (_admobBannerLoaded && _admobBannerAd != null) {
        return Container(
          alignment: Alignment.center,
          width: _admobBannerAd!.size.width.toDouble(),
          height: _admobBannerAd!.size.height.toDouble(),
          child: AdWidget(ad: _admobBannerAd!),
        );
      }
      if (_unityReady) {
        return Container(
          alignment: Alignment.center,
          height: 50,
          child: UnityBannerAd(
            placementId: AdConfig.unityBannerPlacementId,
            onLoad: (id) => _log('Unity Banner loaded ($id)'),
            onFailed: (id, err, msg) =>
                _log('Unity Banner failed ($id): $msg'),
          ),
        );
      }
    }

    // Fallback preview banner bar (for macOS/Web/Simulator or while loading)
    return Container(
      height: 48,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF111827), Color(0xFF1E293B)],
        ),
        border: Border(
          top: BorderSide(
            color: Colors.amberAccent.withValues(alpha: 0.35),
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber.shade700,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'AD',
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Google AdMob • Unity Ads Mediation Active',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          Text(
            'AdMob: $_admobImpressions | Unity: $_unityImpressions',
            style: const TextStyle(
              color: Colors.cyanAccent,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // INTERSTITIAL ADS (ADMOB + UNITY WATERFALL)
  // ===========================================================================

  void _loadAdMobInterstitial() {
    if (!isMobilePlatform) return;
    final unitId = AdConfig.admobInterstitialAdUnitId;
    if (unitId.isEmpty) return;

    InterstitialAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _admobInterstitialAd = ad;
          _log('AdMob Interstitial preloaded');
          notifyListeners();
        },
        onAdFailedToLoad: (error) {
          _admobInterstitialAd = null;
          _log('AdMob Interstitial load failed: ${error.message}');
          notifyListeners();
        },
      ),
    );
  }

  void _loadUnityInterstitial() {
    if (!isMobilePlatform || !_unityReady) return;
    UnityAds.load(
      placementId: AdConfig.unityInterstitialPlacementId,
      onComplete: (placementId) {
        _unityInterstitialLoaded = true;
        _log('Unity Interstitial preloaded ($placementId)');
        notifyListeners();
      },
      onFailed: (placementId, error, message) {
        _unityInterstitialLoaded = false;
        _log('Unity Interstitial load failed: $message');
        notifyListeners();
      },
    );
  }

  AdNetwork _pickPrimaryNetwork() {
    switch (_strategy) {
      case MediationStrategy.admobPrimaryUnityFallback:
        return AdNetwork.admob;
      case MediationStrategy.unityPrimaryAdmobFallback:
        return AdNetwork.unityAds;
      case MediationStrategy.roundRobin:
        final chosen = _nextRoundRobinNetwork;
        _nextRoundRobinNetwork =
            chosen == AdNetwork.admob ? AdNetwork.unityAds : AdNetwork.admob;
        return chosen;
    }
  }

  /// Shows an interstitial ad using the active mediation strategy
  /// (AdMob <-> Unity Ads waterfall).
  Future<void> showInterstitialAd({
    BuildContext? context,
    AdNetwork? forceNetwork,
    VoidCallback? onClosed,
  }) async {
    final primary = forceNetwork ?? _pickPrimaryNetwork();

    if (isMobilePlatform) {
      if (primary == AdNetwork.admob) {
        final shown = await _tryShowAdMobInterstitial(onClosed: onClosed);
        if (shown) return;
        final fallbackShown =
            await _tryShowUnityInterstitial(onClosed: onClosed);
        if (fallbackShown) return;
      } else {
        final shown = await _tryShowUnityInterstitial(onClosed: onClosed);
        if (shown) return;
        final fallbackShown =
            await _tryShowAdMobInterstitial(onClosed: onClosed);
        if (fallbackShown) return;
      }
    }

    // Simulated Interstitial dialog when testing on desktop/web or if no fill
    if (context != null && context.mounted) {
      await _showSimulatedAdDialog(
        context: context,
        network: primary,
        isRewarded: false,
      );
    }
    if (primary == AdNetwork.admob) {
      _admobImpressions++;
    } else {
      _unityImpressions++;
    }
    notifyListeners();
    onClosed?.call();
  }

  Future<bool> _tryShowAdMobInterstitial({VoidCallback? onClosed}) async {
    final ad = _admobInterstitialAd;
    if (ad == null) {
      _loadAdMobInterstitial();
      return false;
    }

    final completer = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) {
        _admobImpressions++;
        _log('Showing Google AdMob Interstitial');
        notifyListeners();
      },
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _admobInterstitialAd = null;
        _loadAdMobInterstitial();
        onClosed?.call();
        if (!completer.isCompleted) completer.complete(true);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _admobInterstitialAd = null;
        _loadAdMobInterstitial();
        if (!completer.isCompleted) completer.complete(false);
      },
    );
    await ad.show();
    return completer.future;
  }

  Future<bool> _tryShowUnityInterstitial({VoidCallback? onClosed}) async {
    if (!_unityReady || !_unityInterstitialLoaded) {
      _loadUnityInterstitial();
      return false;
    }

    final completer = Completer<bool>();
    _unityInterstitialLoaded = false;

    await UnityAds.showVideoAd(
      placementId: AdConfig.unityInterstitialPlacementId,
      onStart: (id) {
        _unityImpressions++;
        _log('Showing Unity Ads Interstitial ($id)');
        notifyListeners();
      },
      onComplete: (id) {
        _loadUnityInterstitial();
        onClosed?.call();
        if (!completer.isCompleted) completer.complete(true);
      },
      onSkipped: (id) {
        _loadUnityInterstitial();
        onClosed?.call();
        if (!completer.isCompleted) completer.complete(true);
      },
      onFailed: (id, error, message) {
        _loadUnityInterstitial();
        if (!completer.isCompleted) completer.complete(false);
      },
    );
    return completer.future;
  }

  // ===========================================================================
  // REWARDED ADS (ADMOB + UNITY WATERFALL)
  // ===========================================================================

  void _loadAdMobRewarded() {
    if (!isMobilePlatform) return;
    final unitId = AdConfig.admobRewardedAdUnitId;
    if (unitId.isEmpty) return;

    RewardedAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _admobRewardedAd = ad;
          _log('AdMob Rewarded Ad preloaded');
          notifyListeners();
        },
        onAdFailedToLoad: (error) {
          _admobRewardedAd = null;
          _log('AdMob Rewarded load failed: ${error.message}');
          notifyListeners();
        },
      ),
    );
  }

  void _loadUnityRewarded() {
    if (!isMobilePlatform || !_unityReady) return;
    UnityAds.load(
      placementId: AdConfig.unityRewardedPlacementId,
      onComplete: (placementId) {
        _unityRewardedLoaded = true;
        _log('Unity Rewarded Video preloaded ($placementId)');
        notifyListeners();
      },
      onFailed: (placementId, error, message) {
        _unityRewardedLoaded = false;
        _log('Unity Rewarded load failed: $message');
        notifyListeners();
      },
    );
  }

  /// Shows a Rewarded Video Ad (Google AdMob or Unity Ads waterfall) and invokes
  /// [onRewardEarned] when the user completes watching the video.
  Future<bool> showRewardedAd({
    required VoidCallback onRewardEarned,
    BuildContext? context,
    AdNetwork? forceNetwork,
    String rewardLabel = 'Bonus Reward',
  }) async {
    final primary = forceNetwork ?? _pickPrimaryNetwork();

    if (isMobilePlatform) {
      if (primary == AdNetwork.admob) {
        final shown = await _tryShowAdMobRewarded(onRewardEarned);
        if (shown) return true;
        final fallbackShown = await _tryShowUnityRewarded(onRewardEarned);
        if (fallbackShown) return true;
      } else {
        final shown = await _tryShowUnityRewarded(onRewardEarned);
        if (shown) return true;
        final fallbackShown = await _tryShowAdMobRewarded(onRewardEarned);
        if (fallbackShown) return true;
      }
    }

    // Fallback interactive test ad preview so rewards work in simulator/desktop
    if (context != null && context.mounted) {
      final completed = await _showSimulatedAdDialog(
        context: context,
        network: primary,
        isRewarded: true,
        rewardLabel: rewardLabel,
      );
      if (completed) {
        if (primary == AdNetwork.admob) {
          _admobImpressions++;
        } else {
          _unityImpressions++;
        }
        _rewardsGranted++;
        onRewardEarned();
        notifyListeners();
        return true;
      }
      return false;
    }

    _rewardsGranted++;
    onRewardEarned();
    notifyListeners();
    return true;
  }

  Future<bool> _tryShowAdMobRewarded(VoidCallback onRewardEarned) async {
    final ad = _admobRewardedAd;
    if (ad == null) {
      _loadAdMobRewarded();
      return false;
    }

    final completer = Completer<bool>();
    bool earned = false;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) {
        _admobImpressions++;
        _log('Showing Google AdMob Rewarded Ad');
        notifyListeners();
      },
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _admobRewardedAd = null;
        _loadAdMobRewarded();
        if (!completer.isCompleted) completer.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _admobRewardedAd = null;
        _loadAdMobRewarded();
        if (!completer.isCompleted) completer.complete(false);
      },
    );

    await ad.show(
      onUserEarnedReward: (adWithoutView, reward) {
        earned = true;
        _rewardsGranted++;
        _log('AdMob reward earned: ${reward.amount} ${reward.type}');
        onRewardEarned();
        notifyListeners();
      },
    );

    return completer.future;
  }

  Future<bool> _tryShowUnityRewarded(VoidCallback onRewardEarned) async {
    if (!_unityReady || !_unityRewardedLoaded) {
      _loadUnityRewarded();
      return false;
    }

    final completer = Completer<bool>();
    _unityRewardedLoaded = false;

    await UnityAds.showVideoAd(
      placementId: AdConfig.unityRewardedPlacementId,
      onStart: (id) {
        _unityImpressions++;
        _log('Showing Unity Ads Rewarded Video ($id)');
        notifyListeners();
      },
      onComplete: (id) {
        _rewardsGranted++;
        _log('Unity Ads reward earned ($id)');
        onRewardEarned();
        _loadUnityRewarded();
        notifyListeners();
        if (!completer.isCompleted) completer.complete(true);
      },
      onSkipped: (id) {
        _loadUnityRewarded();
        if (!completer.isCompleted) completer.complete(false);
      },
      onFailed: (id, error, message) {
        _loadUnityRewarded();
        if (!completer.isCompleted) completer.complete(false);
      },
    );

    return completer.future;
  }

  Future<bool> _showSimulatedAdDialog({
    required BuildContext context,
    required AdNetwork network,
    required bool isRewarded,
    String rewardLabel = 'Reward',
  }) async {
    final isAdMob = network == AdNetwork.admob;
    final networkTitle = isAdMob ? 'Google AdMob' : 'Unity Ads';
    final badgeColor =
        isAdMob ? const Color(0xFF4285F4) : const Color(0xFF10B981);

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _SimulatedAdOverlay(
        networkTitle: networkTitle,
        badgeColor: badgeColor,
        isRewarded: isRewarded,
        rewardLabel: rewardLabel,
      ),
    );
    return result ?? false;
  }

  void _log(String message) {
    _lastStatusMessage = message;
    debugPrint('[AdService] $message');
  }
}

class _SimulatedAdOverlay extends StatefulWidget {
  final String networkTitle;
  final Color badgeColor;
  final bool isRewarded;
  final String rewardLabel;

  const _SimulatedAdOverlay({
    required this.networkTitle,
    required this.badgeColor,
    required this.isRewarded,
    required this.rewardLabel,
  });

  @override
  State<_SimulatedAdOverlay> createState() => _SimulatedAdOverlayState();
}

class _SimulatedAdOverlayState extends State<_SimulatedAdOverlay> {
  int _secondsRemaining = 3;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_secondsRemaining > 0) {
          _secondsRemaining--;
        } else {
          _timer?.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canClaim = _secondsRemaining == 0;
    return Dialog(
      backgroundColor: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: widget.badgeColor, width: 2),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: widget.badgeColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${widget.networkTitle} • ${widget.isRewarded ? "REWARDED VIDEO" : "INTERSTITIAL"}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      canClaim ? 'Ready' : '${_secondsRemaining}s',
                      style: const TextStyle(
                        color: Colors.amberAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.badgeColor.withValues(alpha: 0.18),
                  border: Border.all(color: widget.badgeColor, width: 2),
                ),
                child: Icon(
                  widget.isRewarded
                      ? Icons.play_circle_fill_rounded
                      : Icons.ads_click_rounded,
                  size: 46,
                  color: widget.badgeColor,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.isRewarded
                    ? 'Unlock ${widget.rewardLabel}'
                    : 'Car Parking Jam 3D Sponsor',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Test Ad Mode (${widget.networkTitle} SDK integrated).\nOn physical iOS/Android devices with live ad units, native full-screen video ads play here.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: canClaim
                      ? () => Navigator.of(context).pop(true)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.badgeColor,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.white10,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: Icon(
                    canClaim ? Icons.check_circle_rounded : Icons.timer_rounded,
                  ),
                  label: Text(
                    canClaim
                        ? (widget.isRewarded
                            ? 'CLAIM REWARD & CONTINUE'
                            : 'CONTINUE TO GAME')
                        : 'PLEASE WAIT ($_secondsRemaining s)...',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              if (widget.isRewarded) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text(
                    'Skip Reward',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
