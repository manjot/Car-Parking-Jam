import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../config/ad_config.dart';
import '../models/game_models.dart';
import '../rendering/parking_3d_painter.dart';
import '../services/ad_service.dart';
import '../services/game_storage.dart';
import '../services/level_generator.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  final GameStorage _storage = GameStorage.instance;
  final AdService _adService = AdService.instance;
  final Random _rng = Random();

  late Ticker _ticker;
  Duration _lastTick = Duration.zero;
  double _animTime = 0.0;

  late LevelData _level;
  List<ParkingCar> _cars = [];
  final List<Particle3D> _particles = [];
  final List<FloatingBadge3D> _badges = [];

  Camera3DConfig _camera = const Camera3DConfig();
  bool _cameraOrbitMode = false;

  String? _selectedCarId;
  Offset? _dragStartScreen;
  bool _dragTriggeredMove = false;
  bool _helicopterMode = false;

  int _movesMade = 0;
  int _collisionsCount = 0;
  int _comboCount = 0;
  int _levelCoinsEarned = 0;
  int _shuffleSeedOffset = 0;
  bool _levelCompletedDialogShown = false;

  EnvironmentTheme get _currentTheme => EnvironmentTheme.allThemes.firstWhere(
        (t) => t.id == _storage.selectedThemeId,
        orElse: () => EnvironmentTheme.allThemes.first,
      );

  CarSkinPack get _currentSkinPack => CarSkinPack.allPacks.firstWhere(
        (p) => p.id == _storage.selectedSkinPackId,
        orElse: () => CarSkinPack.allPacks.first,
      );

  @override
  void initState() {
    super.initState();
    _loadLevel(_storage.currentLevel);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _loadLevel(int levelNumber, {int seedOffset = 0}) {
    _storage.currentLevel = max(1, levelNumber);
    if (_storage.currentLevel > _storage.highestUnlockedLevel) {
      _storage.highestUnlockedLevel = _storage.currentLevel;
    }
    _storage.save();

    _shuffleSeedOffset = seedOffset;
    _level = LevelGenerator.generateLevel(
      levelNumber: _storage.currentLevel,
      skinPack: _currentSkinPack,
      seedOffset: seedOffset,
    );
    _cars = _level.cars.map((c) => c.copy()).toList();
    _particles.clear();
    _badges.clear();
    _selectedCarId = null;
    _helicopterMode = false;
    _movesMade = 0;
    _collisionsCount = 0;
    _comboCount = 0;
    _levelCoinsEarned = 0;
    _levelCompletedDialogShown = false;
    setState(() {});
  }

  void _onTick(Duration elapsed) {
    final dt = _lastTick == Duration.zero
        ? 0.016
        : ((elapsed - _lastTick).inMicroseconds / 1000000.0).clamp(0.001, 0.05);
    _lastTick = elapsed;
    _animTime += dt;

    bool needsRepaint = true;

    // Update cars
    for (final car in _cars) {
      if (car.shakeTimer > 0) {
        car.shakeTimer = max(0.0, car.shakeTimer - dt * 2.8);
        car.tiltPitch = sin(car.shakeTimer * 32.0) * 0.14 * car.shakeDirection;
        if (car.shakeTimer == 0) {
          car.tiltPitch = 0.0;
        }
      }

      switch (car.state) {
        case CarAnimState.parked:
          // Smoothly interpolate animX/animY toward gridX/gridY
          car.animX += (car.gridX - car.animX) * min(1.0, dt * 16.0);
          car.animY += (car.gridY - car.animY) * min(1.0, dt * 16.0);
          break;

        case CarAnimState.sliding:
          final dx = car.gridX - car.animX;
          final dy = car.gridY - car.animY;
          final dist = sqrt(dx * dx + dy * dy);
          const slideSpeed = 14.0;
          if (dist <= slideSpeed * dt) {
            car.animX = car.gridX.toDouble();
            car.animY = car.gridY.toDouble();
            car.state = CarAnimState.parked;
            // Trigger collision bump at the end of a blocked slide
            car.shakeTimer = 0.55;
            _spawnCollisionSparks(car);
          } else {
            car.animX += (dx / dist) * slideSpeed * dt;
            car.animY += (dy / dist) * slideSpeed * dt;
          }
          break;

        case CarAnimState.exitingLot:
          const exitSpeed = 13.5;
          final dir = car.exitDirection ?? ExitDirection.east;
          switch (dir) {
            case ExitDirection.west:
              car.animX -= exitSpeed * dt;
              if (car.animX <= -1.35) {
                car.animX = -1.35;
                car.state = CarAnimState.drivingOnRoad;
              }
              break;
            case ExitDirection.east:
              car.animX += exitSpeed * dt;
              if (car.animX >= _level.gridSize + 0.35) {
                car.animX = _level.gridSize + 0.35;
                car.state = CarAnimState.drivingOnRoad;
              }
              break;
            case ExitDirection.north:
              car.animY -= exitSpeed * dt;
              if (car.animY <= -1.35) {
                car.animY = -1.35;
                car.state = CarAnimState.drivingOnRoad;
              }
              break;
            case ExitDirection.south:
              car.animY += exitSpeed * dt;
              if (car.animY >= _level.gridSize + 0.35) {
                car.animY = _level.gridSize + 0.35;
                car.state = CarAnimState.drivingOnRoad;
              }
              break;
          }
          if (_rng.nextDouble() < 0.45) {
            _spawnExhaustSmoke(car);
          }
          break;

        case CarAnimState.drivingOnRoad:
          const highwaySpeed = 17.0;
          car.roadProgress += highwaySpeed * dt;
          final dir = car.exitDirection ?? ExitDirection.east;
          switch (dir) {
            case ExitDirection.west:
              car.yawAngle = _lerpAngle(car.yawAngle, pi * 0.5, dt * 12.0);
              car.animY += highwaySpeed * dt;
              break;
            case ExitDirection.east:
              car.yawAngle = _lerpAngle(car.yawAngle, -pi * 0.5, dt * 12.0);
              car.animY -= highwaySpeed * dt;
              break;
            case ExitDirection.north:
              car.yawAngle = _lerpAngle(car.yawAngle, 0.0, dt * 12.0);
              car.animX += highwaySpeed * dt;
              break;
            case ExitDirection.south:
              car.yawAngle = _lerpAngle(car.yawAngle, pi, dt * 12.0);
              car.animX -= highwaySpeed * dt;
              break;
          }
          if (_rng.nextDouble() < 0.5) {
            _spawnExhaustSmoke(car);
          }
          if (car.roadProgress > _level.gridSize + 6.0) {
            car.state = CarAnimState.exited;
            _checkLevelCompletion();
          }
          break;

        case CarAnimState.helicopterLift:
          car.animZ += dt * 4.5;
          car.yawAngle += dt * 2.5;
          if (car.animZ > 4.2) {
            car.state = CarAnimState.exited;
            _checkLevelCompletion();
          }
          break;

        case CarAnimState.exited:
          break;
      }
    }

    // Update 3D particles
    for (int i = _particles.length - 1; i >= 0; i--) {
      final p = _particles[i];
      p.life -= dt;
      if (p.life <= 0) {
        _particles.removeAt(i);
      } else {
        p.x += p.vx * dt;
        p.y += p.vy * dt;
        p.z += p.vz * dt;
        p.vz -= 1.5 * dt;
      }
    }

    // Update floating 3D badges
    for (int i = _badges.length - 1; i >= 0; i--) {
      final b = _badges[i];
      b.life -= dt;
      if (b.life <= 0) {
        _badges.removeAt(i);
      } else {
        b.z += dt * 0.9;
      }
    }

    if (needsRepaint && mounted) {
      setState(() {});
    }
  }

  double _lerpAngle(double current, double target, double t) {
    double diff = (target - current) % (2 * pi);
    if (diff > pi) diff -= 2 * pi;
    if (diff < -pi) diff += 2 * pi;
    return current + diff * min(1.0, t);
  }

  // ===========================================================================
  // TOUCH / SWIPE / RAYCAST INTERACTION
  // ===========================================================================

  Parking3DPainter _createPainter() {
    return Parking3DPainter(
      level: _level,
      cars: _cars,
      particles: _particles,
      badges: _badges,
      theme: _currentTheme,
      camera: _camera,
      animTime: _animTime,
      selectedCarId: _selectedCarId,
      helicopterModeActive: _helicopterMode,
    );
  }

  ParkingCar? _pickCarAtScreenPoint(Offset localPos, Size canvasSize) {
    final painter = _createPainter();
    // Unproject onto car roof plane (z = 0.35) and base plane (z = 0.15)
    for (final planeZ in [0.38, 0.15]) {
      final worldPt = painter.unprojectToPlane(
        localPos,
        canvasSize,
        planeZ: planeZ,
      );

      for (final car in _cars) {
        if (car.state != CarAnimState.parked) continue;
        final minX = car.gridX - 0.15;
        final maxX = car.gridX +
            (car.orientation == CarOrientation.horizontal ? car.length : 1) +
            0.15;
        final minY = car.gridY - 0.15;
        final maxY = car.gridY +
            (car.orientation == CarOrientation.vertical ? car.length : 1) +
            0.15;

        if (worldPt.dx >= minX &&
            worldPt.dx <= maxX &&
            worldPt.dy >= minY &&
            worldPt.dy <= maxY) {
          return car;
        }
      }
    }
    return null;
  }

  void _onPanStart(DragStartDetails details, Size canvasSize) {
    _dragStartScreen = details.localPosition;
    _dragTriggeredMove = false;

    if (_cameraOrbitMode) return;

    final hitCar = _pickCarAtScreenPoint(details.localPosition, canvasSize);
    if (hitCar != null) {
      if (_helicopterMode) {
        _triggerHelicopterLift(hitCar);
        _dragTriggeredMove = true;
        return;
      }
      setState(() {
        _selectedCarId = hitCar.id;
      });
    } else {
      setState(() {
        _selectedCarId = null;
      });
    }
  }

  void _onPanUpdate(DragUpdateDetails details, Size canvasSize) {
    if (_cameraOrbitMode) {
      setState(() {
        _camera = _camera.copyWith(
          yaw: _camera.yaw + details.delta.dx * 0.008,
          pitch: (_camera.pitch + details.delta.dy * 0.006).clamp(0.55, 1.32),
        );
      });
      return;
    }

    if (_dragTriggeredMove || _selectedCarId == null || _dragStartScreen == null) {
      return;
    }

    final screenDelta = details.localPosition - _dragStartScreen!;
    if (screenDelta.distance < 16.0) return;

    final car = _cars.where((c) => c.id == _selectedCarId).firstOrNull;
    if (car == null || car.state != CarAnimState.parked) return;

    final painter = _createPainter();
    final worldDelta = painter.screenDeltaToWorld(screenDelta, canvasSize);

    final int dirSign;
    if (car.orientation == CarOrientation.horizontal) {
      dirSign = worldDelta.dx >= 0 ? 1 : -1;
    } else {
      dirSign = worldDelta.dy >= 0 ? 1 : -1;
    }

    _dragTriggeredMove = true;
    _attemptCarMove(car, dirSign);
  }

  void _onPanEnd(DragEndDetails details) {
    if (!_cameraOrbitMode && !_dragTriggeredMove && _selectedCarId != null) {
      final car = _cars.where((c) => c.id == _selectedCarId).firstOrNull;
      if (car != null && car.state == CarAnimState.parked) {
        // Smart tap: try facing direction first; if blocked, check if opposite direction exits
        final preferredSign = car.facingPositive ? 1 : -1;
        final checkPref = LevelGenerator.evaluateMove(
          level: _level,
          activeCars: _cars,
          car: car,
          directionSign: preferredSign,
        );
        if (checkPref.canExit) {
          _attemptCarMove(car, preferredSign);
        } else {
          final checkOpp = LevelGenerator.evaluateMove(
            level: _level,
            activeCars: _cars,
            car: car,
            directionSign: -preferredSign,
          );
          if (checkOpp.canExit) {
            _attemptCarMove(car, -preferredSign);
          } else if (checkPref.freeCellsToSlide >= checkOpp.freeCellsToSlide) {
            _attemptCarMove(car, preferredSign);
          } else {
            _attemptCarMove(car, -preferredSign);
          }
        }
      }
    }
    _selectedCarId = null;
    _dragStartScreen = null;
  }

  void _attemptCarMove(ParkingCar car, int directionSign) {
    if (car.state != CarAnimState.parked) return;

    // Clear any active hint highlights
    for (final c in _cars) {
      c.isHighlighted = false;
    }

    _movesMade++;
    final result = LevelGenerator.evaluateMove(
      level: _level,
      activeCars: _cars,
      car: car,
      directionSign: directionSign,
    );

    if (result.canExit) {
      // Unobstructed path! Launch car out of the parking lot!
      HapticFeedback.mediumImpact();
      car.state = CarAnimState.exitingLot;
      car.exitDirection = result.targetDirection;
      _comboCount++;

      final baseReward = car.isVip ? 45 : (car.length == 3 ? 25 : 15);
      final comboBonus = (_comboCount > 1) ? (_comboCount - 1) * 5 : 0;
      final totalEarned = baseReward + comboBonus;

      _levelCoinsEarned += totalEarned;
      _storage.coins += totalEarned;
      _storage.totalCarsCleared++;
      _storage.save();

      _badges.add(
        FloatingBadge3D(
          x: car.animX + 0.5,
          y: car.animY + 0.5,
          z: 0.85,
          text: car.isVip
              ? 'VIP +$totalEarned COINS!'
              : (_comboCount > 1
                  ? '${_comboCount}x COMBO +$totalEarned'
                  : '+$totalEarned'),
          color: car.isVip ? Colors.amberAccent : Colors.greenAccent,
        ),
      );

      // Check immediately in case all remaining cars are already exiting/exited
      _checkLevelCompletion();
    } else {
      // Blocked! Slide up to blocker and collide with 3D suspension shake
      HapticFeedback.heavyImpact();
      _collisionsCount++;
      _comboCount = 0;

      if (result.freeCellsToSlide > 0) {
        if (car.orientation == CarOrientation.horizontal) {
          car.gridX += directionSign * result.freeCellsToSlide;
        } else {
          car.gridY += directionSign * result.freeCellsToSlide;
        }
        car.state = CarAnimState.sliding;
        car.shakeDirection = directionSign.toDouble();
      } else {
        car.shakeTimer = 0.55;
        car.shakeDirection = directionSign.toDouble();
        _spawnCollisionSparks(car);
      }

      if (result.blockingCar != null) {
        result.blockingCar!.shakeTimer = 0.45;
        result.blockingCar!.shakeDirection = directionSign.toDouble();
      }

      _badges.add(
        FloatingBadge3D(
          x: car.gridX + 0.5,
          y: car.gridY + 0.5,
          z: 0.9,
          text: result.hitWallOrObstacle ? 'BLOCKED!' : 'BUMP!',
          color: Colors.redAccent,
        ),
      );
    }
  }

  void _spawnExhaustSmoke(ParkingCar car) {
    _particles.add(
      Particle3D(
        x: car.animX + 0.5 + (_rng.nextDouble() - 0.5) * 0.3,
        y: car.animY + 0.5 + (_rng.nextDouble() - 0.5) * 0.3,
        z: 0.15,
        vx: (_rng.nextDouble() - 0.5) * 0.8,
        vy: (_rng.nextDouble() - 0.5) * 0.8,
        vz: 1.2 + _rng.nextDouble() * 0.8,
        size: 5.0 + _rng.nextDouble() * 4.0,
        life: 0.45,
        maxLife: 0.45,
        color: Colors.blueGrey.shade200,
      ),
    );
  }

  void _spawnCollisionSparks(ParkingCar car) {
    final cx = car.gridX + 0.5;
    final cy = car.gridY + 0.5;
    for (int i = 0; i < 10; i++) {
      final angle = _rng.nextDouble() * 2 * pi;
      final speed = 1.5 + _rng.nextDouble() * 2.5;
      _particles.add(
        Particle3D(
          x: cx,
          y: cy,
          z: 0.35,
          vx: cos(angle) * speed,
          vy: sin(angle) * speed,
          vz: 1.8 + _rng.nextDouble() * 2.0,
          size: 4.5,
          life: 0.5,
          maxLife: 0.5,
          color: i.isEven ? Colors.amberAccent : Colors.deepOrangeAccent,
        ),
      );
    }
  }

  // ===========================================================================
  // POWER-UPS & BOOSTERS (WITH ADMOB / UNITY REWARDED ADS)
  // ===========================================================================

  void _useHintBooster() {
    if (_storage.hintsCount <= 0) {
      _promptRewardedBooster(
        title: 'Get +2 Hint Boosters',
        onEarned: () {
          _storage.hintsCount += 2;
          _storage.save();
          setState(() {});
        },
      );
      return;
    }

    final hint = LevelGenerator.findHintMove(
      level: _level,
      activeCars: _cars,
    );
    if (hint == null) return;

    _storage.hintsCount--;
    _storage.save();
    hint.car.isHighlighted = true;
    _attemptCarMove(hint.car, hint.directionSign);
  }

  void _toggleHelicopterBooster() {
    if (_helicopterMode) {
      setState(() => _helicopterMode = false);
      return;
    }
    if (_storage.helicoptersCount <= 0) {
      _promptRewardedBooster(
        title: 'Get +1 VIP Helicopter Lift',
        onEarned: () {
          _storage.helicoptersCount += 1;
          _storage.save();
          setState(() => _helicopterMode = true);
        },
      );
      return;
    }
    setState(() => _helicopterMode = true);
  }

  void _triggerHelicopterLift(ParkingCar car) {
    HapticFeedback.heavyImpact();
    _storage.helicoptersCount = max(0, _storage.helicoptersCount - 1);
    _storage.coins += 30;
    _levelCoinsEarned += 30;
    _storage.totalCarsCleared++;
    _storage.save();

    car.state = CarAnimState.helicopterLift;
    _helicopterMode = false;

    _badges.add(
      FloatingBadge3D(
        x: car.animX + 0.5,
        y: car.animY + 0.5,
        z: 1.1,
        text: 'AIRLIFT +30!',
        color: Colors.amberAccent,
      ),
    );
  }

  void _useShuffleBooster() {
    if (_storage.shufflesCount <= 0) {
      _promptRewardedBooster(
        title: 'Get +2 Lot Shuffles',
        onEarned: () {
          _storage.shufflesCount += 2;
          _storage.save();
          setState(() {});
        },
      );
      return;
    }
    HapticFeedback.mediumImpact();
    _storage.shufflesCount--;
    _storage.save();
    _loadLevel(_storage.currentLevel, seedOffset: _shuffleSeedOffset + 1);
  }

  void _promptRewardedBooster({
    required String title,
    required VoidCallback onEarned,
  }) {
    _adService.showRewardedAd(
      context: context,
      rewardLabel: title,
      onRewardEarned: onEarned,
    );
  }

  // ===========================================================================
  // LEVEL COMPLETION & MONETIZATION FLOW
  // ===========================================================================

  void _checkLevelCompletion() {
    if (_levelCompletedDialogShown) return;

    final anyRemaining = _cars.any(
      (c) =>
          c.state == CarAnimState.parked ||
          c.state == CarAnimState.sliding,
    );
    if (anyRemaining) return;

    final allExited = _cars.every((c) => c.state == CarAnimState.exited);
    if (!allExited) return;

    _levelCompletedDialogShown = true;
    final stars = _collisionsCount == 0
        ? 3
        : (_collisionsCount <= 2 ? 2 : 1);

    final prevStars = _storage.levelStars[_level.levelNumber] ?? 0;
    if (stars > prevStars) {
      _storage.levelStars[_level.levelNumber] = stars;
    }

    final completionBonus = _level.isBossLevel ? 100 : 40;
    _levelCoinsEarned += completionBonus;
    _storage.coins += completionBonus;
    if (_storage.currentLevel >= _storage.highestUnlockedLevel) {
      _storage.highestUnlockedLevel = _storage.currentLevel + 1;
    }
    _storage.save();

    Future.delayed(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      _showVictoryModal(stars: stars);
    });
  }

  void _showVictoryModal({required int stars}) {
    bool doubledRewardClaimed = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              backgroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
                side: const BorderSide(color: Color(0xFF38BDF8), width: 2),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: _level.isBossLevel
                              ? Colors.deepOrangeAccent
                              : Colors.cyan.shade700,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _level.isBossLevel
                              ? 'BOSS LEVEL ${_level.levelNumber} CLEARED!'
                              : 'LEVEL ${_level.levelNumber} COMPLETE!',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(3, (index) {
                          final earned = index < stars;
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Icon(
                              Icons.star_rounded,
                              size: index == 1 ? 54 : 42,
                              color: earned
                                  ? const Color(0xFFFACC15)
                                  : Colors.white24,
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildStatColumn(
                              'COINS EARNED',
                              '+$_levelCoinsEarned',
                              Colors.amberAccent,
                            ),
                            _buildStatColumn(
                              'MOVES',
                              '$_movesMade',
                              Colors.cyanAccent,
                            ),
                            _buildStatColumn(
                              'BUMPS',
                              '$_collisionsCount',
                              _collisionsCount == 0
                                  ? Colors.greenAccent
                                  : Colors.orangeAccent,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (!doubledRewardClaimed)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              final bonus = _levelCoinsEarned;
                              await _adService.showRewardedAd(
                                context: context,
                                rewardLabel: '2X Coins (+$bonus)',
                                onRewardEarned: () {
                                  _storage.coins += bonus;
                                  _levelCoinsEarned += bonus;
                                  _storage.save();
                                  setModalState(() {
                                    doubledRewardClaimed = true;
                                  });
                                  setState(() {});
                                },
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFF59E0B),
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            icon: const Icon(Icons.ondemand_video_rounded),
                            label: Text(
                              'WATCH AD FOR 2X COINS (+$_levelCoinsEarned)',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final completedLevel = _level.levelNumber;
                            Navigator.of(ctx).pop();

                            // Show interstitial ad every N levels via AdMob/Unity waterfall
                            if (completedLevel %
                                    AdConfig.interstitialLevelFrequency ==
                                0) {
                              await _adService.showInterstitialAd(
                                context: this.context,
                              );
                            }
                            _loadLevel(completedLevel + 1);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: Text(
                            'NEXT LEVEL (LEVEL ${_level.levelNumber + 1})',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatColumn(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white60,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // UNLIMITED LEVEL SELECTOR MODAL
  // ===========================================================================

  void _showUnlimitedLevelPicker() {
    final controller =
        TextEditingController(text: _storage.currentLevel.toString());

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'UNLIMITED 3D LEVELS (1 → ∞)',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.close, color: Colors.white70),
                  ),
                ],
              ),
              const Text(
                'Every level is procedurally generated and mathematically verified 100% solvable.',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Jump to Any Level # (e.g. 50, 500, 9999)',
                        labelStyle: const TextStyle(color: Colors.white60),
                        filled: true,
                        fillColor: Colors.white10,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () {
                      final parsed = int.tryParse(controller.text.trim()) ?? 1;
                      Navigator.of(ctx).pop();
                      _loadLevel(parsed.clamp(1, 999999999));
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.cyanAccent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'PLAY',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 220,
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.1,
                  ),
                  itemCount: max(50, _storage.highestUnlockedLevel + 15),
                  itemBuilder: (context, index) {
                    final lvl = index + 1;
                    final isCurrent = lvl == _storage.currentLevel;
                    final isBoss = lvl % 5 == 0;
                    final stars = _storage.levelStars[lvl] ?? 0;

                    return InkWell(
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _loadLevel(lvl);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? Colors.cyanAccent
                              : (isBoss
                                  ? Colors.deepOrange.withValues(alpha: 0.35)
                                  : Colors.white10),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isCurrent
                                ? Colors.white
                                : (isBoss
                                    ? Colors.orangeAccent
                                    : Colors.white24),
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '$lvl',
                              style: TextStyle(
                                color: isCurrent ? Colors.black : Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                              ),
                            ),
                            if (stars > 0)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(
                                  stars,
                                  (_) => Icon(
                                    Icons.star_rounded,
                                    size: 11,
                                    color: isCurrent
                                        ? Colors.black
                                        : Colors.amberAccent,
                                  ),
                                ),
                              )
                            else if (isBoss)
                              Text(
                                'BOSS',
                                style: TextStyle(
                                  color: isCurrent
                                      ? Colors.black87
                                      : Colors.orangeAccent,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ===========================================================================
  // GARAGE & 3D ENVIRONMENT THEMES SHOP
  // ===========================================================================

  void _showGarageAndThemesModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.78,
              maxChildSize: 0.92,
              minChildSize: 0.5,
              builder: (_, scrollController) {
                return ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '3D GARAGE & WORLD THEMES',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.amberAccent),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.monetization_on_rounded,
                                color: Colors.amberAccent,
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${_storage.coins}',
                                style: const TextStyle(
                                  color: Colors.amberAccent,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () async {
                        await _adService.showRewardedAd(
                          context: context,
                          rewardLabel: '+200 Garage Coins',
                          onRewardEarned: () {
                            _storage.coins += 200;
                            _storage.save();
                            setSheetState(() {});
                            setState(() {});
                          },
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.play_circle_fill_rounded),
                      label: const Text(
                        'WATCH REWARDED AD FOR +200 FREE COINS',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      '3D ENVIRONMENT WORLDS',
                      style: TextStyle(
                        color: Colors.cyanAccent,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...EnvironmentTheme.allThemes.map((theme) {
                      final unlocked =
                          _storage.unlockedThemeIds.contains(theme.id);
                      final selected = _storage.selectedThemeId == theme.id;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: selected
                              ? Colors.cyan.withValues(alpha: 0.18)
                              : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: selected ? Colors.cyanAccent : Colors.white12,
                            width: selected ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                gradient: LinearGradient(
                                  colors: [theme.skyTop, theme.groundColor],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    theme.name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                  ),
                                  Text(
                                    theme.subtitle,
                                    style: const TextStyle(
                                      color: Colors.white60,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                if (unlocked) {
                                  _storage.selectedThemeId = theme.id;
                                  _storage.save();
                                  setSheetState(() {});
                                  setState(() {});
                                } else if (_storage.coins >= theme.unlockCost) {
                                  _storage.coins -= theme.unlockCost;
                                  _storage.unlockedThemeIds.add(theme.id);
                                  _storage.selectedThemeId = theme.id;
                                  _storage.save();
                                  setSheetState(() {});
                                  setState(() {});
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: selected
                                    ? Colors.green
                                    : (unlocked
                                        ? Colors.white24
                                        : Colors.amber.shade700),
                                foregroundColor: Colors.white,
                              ),
                              child: Text(
                                selected
                                    ? 'ACTIVE'
                                    : (unlocked
                                        ? 'SELECT'
                                        : '${theme.unlockCost} COINS'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 16),
                    const Text(
                      '3D CAR FLEET PAINT PACKS',
                      style: TextStyle(
                        color: Colors.amberAccent,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...CarSkinPack.allPacks.map((pack) {
                      final unlocked =
                          _storage.unlockedSkinPackIds.contains(pack.id);
                      final selected = _storage.selectedSkinPackId == pack.id;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: selected
                              ? Colors.amber.withValues(alpha: 0.16)
                              : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color:
                                selected ? Colors.amberAccent : Colors.white12,
                            width: selected ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Row(
                              children: pack.palette.take(4).map((c) {
                                return Container(
                                  width: 14,
                                  height: 36,
                                  margin: const EdgeInsets.only(right: 3),
                                  decoration: BoxDecoration(
                                    color: c,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                );
                              }).toList(),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    pack.name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                  ),
                                  Text(
                                    pack.description,
                                    style: const TextStyle(
                                      color: Colors.white60,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                if (unlocked) {
                                  _storage.selectedSkinPackId = pack.id;
                                  _storage.save();
                                  _loadLevel(
                                    _storage.currentLevel,
                                    seedOffset: _shuffleSeedOffset,
                                  );
                                  setSheetState(() {});
                                } else if (_storage.coins >= pack.unlockCost) {
                                  _storage.coins -= pack.unlockCost;
                                  _storage.unlockedSkinPackIds.add(pack.id);
                                  _storage.selectedSkinPackId = pack.id;
                                  _storage.save();
                                  _loadLevel(
                                    _storage.currentLevel,
                                    seedOffset: _shuffleSeedOffset,
                                  );
                                  setSheetState(() {});
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: selected
                                    ? Colors.green
                                    : (unlocked
                                        ? Colors.white24
                                        : Colors.amber.shade700),
                                foregroundColor: Colors.white,
                              ),
                              child: Text(
                                selected
                                    ? 'ACTIVE'
                                    : (unlocked
                                        ? 'SELECT'
                                        : '${pack.unlockCost} COINS'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  // ===========================================================================
  // GOOGLE ADMOB & UNITY ADS MEDIATION INSPECTOR MODAL
  // ===========================================================================

  void _showAdMediationInspector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return ListenableBuilder(
          listenable: _adService,
          builder: (context, _) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.monetization_on, color: Colors.amberAccent),
                      SizedBox(width: 8),
                      Text(
                        'GOOGLE ADMOB & UNITY ADS CONSOLE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Status: ${_adService.lastStatusMessage}',
                    style: const TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: MediationStrategy.values.map((s) {
                      final active = _adService.strategy == s;
                      return ChoiceChip(
                        label: Text(s.name),
                        selected: active,
                        onSelected: (_) => _adService.setMediationStrategy(s),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _adService.showInterstitialAd(
                            context: context,
                            forceNetwork: AdNetwork.admob,
                          ),
                          icon: const Icon(Icons.ads_click, size: 16),
                          label: const Text('Test AdMob Interstitial'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _adService.showInterstitialAd(
                            context: context,
                            forceNetwork: AdNetwork.unityAds,
                          ),
                          icon: const Icon(Icons.videogame_asset, size: 16),
                          label: const Text('Test Unity Interstitial'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _adService.showRewardedAd(
                            context: context,
                            forceNetwork: AdNetwork.admob,
                            rewardLabel: 'AdMob Test +50 Coins',
                            onRewardEarned: () {
                              _storage.coins += 50;
                              _storage.save();
                              setState(() {});
                            },
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4285F4),
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.play_arrow, size: 16),
                          label: const Text('AdMob Rewarded'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _adService.showRewardedAd(
                            context: context,
                            forceNetwork: AdNetwork.unityAds,
                            rewardLabel: 'Unity Test +50 Coins',
                            onRewardEarned: () {
                              _storage.coins += 50;
                              _storage.save();
                              setState(() {});
                            },
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.play_arrow, size: 16),
                          label: const Text('Unity Rewarded'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ===========================================================================
  // BUILD UI
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final remainingCars = _cars
        .where(
          (c) =>
              c.state == CarAnimState.parked ||
              c.state == CarAnimState.sliding,
        )
        .length;
    final totalCars = _cars.length;

    return Scaffold(
      backgroundColor: _currentTheme.skyTop,
      body: SafeArea(
        child: Column(
          children: [
            // Top HUD Bar
            _buildTopHudBar(remainingCars, totalCars),

            // Main 3D Interactive Viewport
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final canvasSize = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  return Stack(
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (d) => _onPanStart(d, canvasSize),
                        onPanUpdate: (d) => _onPanUpdate(d, canvasSize),
                        onPanEnd: _onPanEnd,
                        child: CustomPaint(
                          size: canvasSize,
                          painter: _createPainter(),
                        ),
                      ),

                      // Floating Camera 3D Controls (top-right of viewport)
                      Positioned(
                        top: 10,
                        right: 14,
                        child: Column(
                          children: [
                            _buildMiniRoundButton(
                              icon: _cameraOrbitMode
                                  ? Icons.threed_rotation
                                  : Icons.swipe_rounded,
                              label: _cameraOrbitMode ? '3D Orbit' : 'Drive',
                              active: _cameraOrbitMode,
                              onTap: () {
                                setState(() {
                                  _cameraOrbitMode = !_cameraOrbitMode;
                                });
                              },
                            ),
                            const SizedBox(height: 8),
                            _buildMiniRoundButton(
                              icon: Icons.center_focus_strong_rounded,
                              label: 'Reset Cam',
                              onTap: () {
                                setState(() {
                                  _camera = const Camera3DConfig();
                                  _cameraOrbitMode = false;
                                });
                              },
                            ),
                          ],
                        ),
                      ),

                      // Helicopter target mode banner
                      if (_helicopterMode)
                        Positioned(
                          top: 12,
                          left: 16,
                          right: 88,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade800.withValues(alpha: 0.95),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.airplanemode_active,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'TAP ANY CAR TO AIRLIFT IT OUT OF THE JAM!',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),

            // Bottom Power-ups & Booster Dock
            _buildBottomBoosterBar(),

            // Google AdMob / Unity Ads Banner Slot
            ListenableBuilder(
              listenable: _adService,
              builder: (context, _) => _adService.buildBannerAdWidget(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopHudBar(int remainingCars, int totalCars) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
      ),
      child: Row(
        children: [
          // Level Pill (Tap to open Unlimited Level Selector)
          InkWell(
            onTap: _showUnlimitedLevelPicker,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _level.isBossLevel
                      ? [const Color(0xFFDC2626), const Color(0xFFF97316)]
                      : [const Color(0xFF0284C7), const Color(0xFF2563EB)],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    _level.isBossLevel
                        ? Icons.local_fire_department_rounded
                        : Icons.grid_view_rounded,
                    color: Colors.white,
                    size: 17,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _level.isBossLevel
                        ? 'BOSS LVL ${_level.levelNumber}'
                        : 'LEVEL ${_level.levelNumber}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: Colors.white70,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 10),

          // Cars Remaining Counter
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.directions_car_filled_rounded,
                  color: Colors.cyanAccent,
                  size: 16,
                ),
                const SizedBox(width: 5),
                Text(
                  '$remainingCars/$totalCars',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // Coins Counter
          InkWell(
            onTap: _showGarageAndThemesModal,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.amberAccent.withValues(alpha: 0.6),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.monetization_on_rounded,
                    color: Colors.amberAccent,
                    size: 17,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${_storage.coins}',
                    style: const TextStyle(
                      color: Colors.amberAccent,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Ad Mediation Console Button
          IconButton(
            onPressed: _showAdMediationInspector,
            tooltip: 'AdMob & Unity Ads Inspector',
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.12),
            ),
            icon: const Icon(
              Icons.campaign_rounded,
              color: Colors.amberAccent,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniRoundButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? Colors.cyanAccent
              : Colors.black.withValues(alpha: 0.52),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? Colors.white : Colors.white24,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: active ? Colors.black : Colors.white,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: active ? Colors.black : Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBoosterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.92),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildBoosterButton(
            icon: Icons.refresh_rounded,
            label: 'Restart',
            badge: null,
            color: Colors.blueGrey,
            onTap: () => _loadLevel(
              _storage.currentLevel,
              seedOffset: _shuffleSeedOffset,
            ),
          ),
          _buildBoosterButton(
            icon: Icons.lightbulb_rounded,
            label: 'Auto Hint',
            badge: _storage.hintsCount > 0 ? '${_storage.hintsCount}' : 'AD',
            color: const Color(0xFF10B981),
            onTap: _useHintBooster,
          ),
          _buildBoosterButton(
            icon: Icons.airplanemode_active_rounded,
            label: 'Helicopter',
            badge: _storage.helicoptersCount > 0
                ? '${_storage.helicoptersCount}'
                : 'AD',
            color: _helicopterMode
                ? Colors.deepOrangeAccent
                : const Color(0xFFF59E0B),
            onTap: _toggleHelicopterBooster,
          ),
          _buildBoosterButton(
            icon: Icons.shuffle_rounded,
            label: 'Shuffle',
            badge: _storage.shufflesCount > 0
                ? '${_storage.shufflesCount}'
                : 'AD',
            color: const Color(0xFF8B5CF6),
            onTap: _useShuffleBooster,
          ),
          _buildBoosterButton(
            icon: Icons.garage_rounded,
            label: 'Garage',
            badge: null,
            color: const Color(0xFF06B6D4),
            onTap: _showGarageAndThemesModal,
          ),
        ],
      ),
    );
  }

  Widget _buildBoosterButton({
    required IconData icon,
    required String label,
    required String? badge,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 64,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.65), width: 1.5),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 22),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            if (badge != null)
              Positioned(
                top: -6,
                right: 4,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: badge == 'AD' ? Colors.amberAccent : color,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      color: badge == 'AD' ? Colors.black : Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

