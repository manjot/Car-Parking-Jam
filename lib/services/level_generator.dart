import 'dart:math';
import 'package:flutter/material.dart';
import '../models/game_models.dart';

class MoveCheckResult {
  final bool canExit;
  final int freeCellsToSlide;
  final ExitDirection targetDirection;
  final ParkingCar? blockingCar;
  final bool hitWallOrObstacle;

  const MoveCheckResult({
    required this.canExit,
    required this.freeCellsToSlide,
    required this.targetDirection,
    this.blockingCar,
    this.hitWallOrObstacle = false,
  });
}

class HintMove {
  final ParkingCar car;
  final int directionSign; // +1 or -1
  final ExitDirection exitDirection;

  const HintMove({
    required this.car,
    required this.directionSign,
    required this.exitDirection,
  });
}

class LevelGenerator {
  LevelGenerator._();

  /// Generates a 100% solvable 3D Car Parking Jam level for any [levelNumber] (1 to infinity).
  static LevelData generateLevel({
    required int levelNumber,
    required CarSkinPack skinPack,
    int seedOffset = 0,
  }) {
    final safeLevel = max(1, levelNumber);
    final isBoss = safeLevel % 5 == 0;
    final rng = Random(safeLevel * 7919 + seedOffset * 104729 + 1337);

    // Scale grid size with level progression
    final int gridSize;
    if (safeLevel <= 2) {
      gridSize = 6;
    } else if (safeLevel <= 6) {
      gridSize = isBoss ? 8 : 6;
    } else if (safeLevel <= 14) {
      gridSize = isBoss ? 8 : 7;
    } else if (safeLevel <= 28) {
      gridSize = isBoss ? 9 : 8;
    } else {
      gridSize = isBoss ? 10 : (8 + (safeLevel % 2));
    }

    // Target number of cars scales with level & grid area
    final int maxCapacity = (gridSize * gridSize) ~/ 2 - 2;
    final int baseTarget;
    if (safeLevel == 1) {
      baseTarget = 5;
    } else if (safeLevel == 2) {
      baseTarget = 7;
    } else if (safeLevel <= 5) {
      baseTarget = 8 + safeLevel;
    } else {
      baseTarget = min(maxCapacity, 10 + (safeLevel ~/ 2) + (isBoss ? 4 : 0));
    }
    final int targetCars = baseTarget.clamp(5, maxCapacity);

    // 1. Generate Perimeter Walls (ensuring every row and column has at least one open exit)
    final walls = <PerimeterWall>[];
    final wallChance = safeLevel == 1
        ? 0.18
        : (0.25 + min(0.18, safeLevel * 0.004));

    for (int i = 0; i < gridSize; i++) {
      // Horizontal row i: West vs East walls
      final addWest = rng.nextDouble() < wallChance;
      final addEast = !addWest && (rng.nextDouble() < wallChance);
      if (addWest) {
        walls.add(PerimeterWall(side: ExitDirection.west, index: i));
      } else if (addEast) {
        walls.add(PerimeterWall(side: ExitDirection.east, index: i));
      }

      // Vertical col i: North vs South walls
      final addNorth = rng.nextDouble() < wallChance;
      final addSouth = !addNorth && (rng.nextDouble() < wallChance);
      if (addNorth) {
        walls.add(PerimeterWall(side: ExitDirection.north, index: i));
      } else if (addSouth) {
        walls.add(PerimeterWall(side: ExitDirection.south, index: i));
      }
    }

    bool hasWall(ExitDirection side, int idx) {
      for (final w in walls) {
        if (w.side == side && w.index == idx) return true;
      }
      return false;
    }

    // 2. Generate internal static obstacles on higher levels
    final obstacles = <GridObstacle>[];
    final int obstacleCount = safeLevel < 4
        ? 0
        : (safeLevel < 12 ? 1 : (isBoss ? 3 : 2));

    for (int n = 0; n < obstacleCount; n++) {
      for (int attempt = 0; attempt < 20; attempt++) {
        final ox = 1 + rng.nextInt(gridSize - 2);
        final oy = 1 + rng.nextInt(gridSize - 2);
        if (obstacles.any((o) => o.gridX == ox && o.gridY == oy)) continue;
        // Avoid placing two obstacles in the same row or column
        if (obstacles.any((o) => o.gridX == ox || o.gridY == oy)) continue;

        final obsType =
            ObstacleType.values[(safeLevel + n) % ObstacleType.values.length];
        obstacles.add(GridObstacle(gridX: ox, gridY: oy, type: obsType));
        break;
      }
    }

    // Occupancy grid: 0 = empty, -1 = obstacle, >0 = car index
    final grid = List.generate(gridSize, (_) => List.filled(gridSize, 0));
    for (final o in obstacles) {
      grid[o.gridY][o.gridX] = -1;
    }

    bool canExitOnCurrentGrid({
      required int gx,
      required int gy,
      required int length,
      required CarOrientation orientation,
      required int dirSign,
    }) {
      if (orientation == CarOrientation.horizontal) {
        final side = dirSign < 0 ? ExitDirection.west : ExitDirection.east;
        if (hasWall(side, gy)) return false;
        if (dirSign < 0) {
          for (int x = gx - 1; x >= 0; x--) {
            if (grid[gy][x] != 0) return false;
          }
          return true;
        } else {
          for (int x = gx + length; x < gridSize; x++) {
            if (grid[gy][x] != 0) return false;
          }
          return true;
        }
      } else {
        final side = dirSign < 0 ? ExitDirection.north : ExitDirection.south;
        if (hasWall(side, gx)) return false;
        if (dirSign < 0) {
          for (int y = gy - 1; y >= 0; y--) {
            if (grid[y][gx] != 0) return false;
          }
          return true;
        } else {
          for (int y = gy + length; y < gridSize; y++) {
            if (grid[y][gx] != 0) return false;
          }
          return true;
        }
      }
    }

    // 3. Reverse-Dependency Solvable Car Placement
    // Each car placed at step k is guaranteed to have a clear exit path given
    // cars {1..k-1}, and is scored higher when it blocks the exit rays of {1..k-1}.
    final placedCars = <ParkingCar>[];

    for (int carIdx = 0; carIdx < targetCars; carIdx++) {
      // Collect cells that currently lie on the open exit rays of already-placed cars
      final exitRayCells = <Point2I>{};
      for (final existing in placedCars) {
        for (final dirSign in [-1, 1]) {
          if (canExitOnCurrentGrid(
            gx: existing.gridX,
            gy: existing.gridY,
            length: existing.length,
            orientation: existing.orientation,
            dirSign: dirSign,
          )) {
            if (existing.orientation == CarOrientation.horizontal) {
              if (dirSign < 0) {
                for (int x = existing.gridX - 1; x >= 0; x--) {
                  exitRayCells.add(Point2I(x, existing.gridY));
                }
              } else {
                for (int x = existing.gridX + existing.length;
                    x < gridSize;
                    x++) {
                  exitRayCells.add(Point2I(x, existing.gridY));
                }
              }
            } else {
              if (dirSign < 0) {
                for (int y = existing.gridY - 1; y >= 0; y--) {
                  exitRayCells.add(Point2I(existing.gridX, y));
                }
              } else {
                for (int y = existing.gridY + existing.length;
                    y < gridSize;
                    y++) {
                  exitRayCells.add(Point2I(existing.gridX, y));
                }
              }
            }
          }
        }
      }

      // Allow 3-cell vehicles (bus/limo/fireTruck) on levels >= 3
      final allowLen3 =
          safeLevel >= 3 && carIdx % 5 == 1 && gridSize >= 7;

      double bestScore = -1e9;
      int? bestX;
      int? bestY;
      int? bestLen;
      CarOrientation? bestOrient;

      final candidateLengths = allowLen3 ? [3, 2] : [2];

      for (final len in candidateLengths) {
        for (final orient in CarOrientation.values) {
          final maxX =
              orient == CarOrientation.horizontal ? gridSize - len : gridSize - 1;
          final maxY =
              orient == CarOrientation.vertical ? gridSize - len : gridSize - 1;

          for (int gy = 0; gy <= maxY; gy++) {
            for (int gx = 0; gx <= maxX; gx++) {
              // Check cells are free
              bool overlaps = false;
              for (int i = 0; i < len; i++) {
                final cx = orient == CarOrientation.horizontal ? gx + i : gx;
                final cy = orient == CarOrientation.vertical ? gy + i : gy;
                if (grid[cy][cx] != 0) {
                  overlaps = true;
                  break;
                }
              }
              if (overlaps) continue;

              // Check invariant: must have at least one unobstructed exit right now
              final exitNeg = canExitOnCurrentGrid(
                gx: gx,
                gy: gy,
                length: len,
                orientation: orient,
                dirSign: -1,
              );
              final exitPos = canExitOnCurrentGrid(
                gx: gx,
                gy: gy,
                length: len,
                orientation: orient,
                dirSign: 1,
              );
              if (!exitNeg && !exitPos) continue;

              // Score this placement
              double score = rng.nextDouble() * 14.0;

              // Reward blocking exit rays of earlier cars (builds deep dependency chains!)
              int rayIntersections = 0;
              for (int i = 0; i < len; i++) {
                final cx = orient == CarOrientation.horizontal ? gx + i : gx;
                final cy = orient == CarOrientation.vertical ? gy + i : gy;
                if (exitRayCells.contains(Point2I(cx, cy))) {
                  rayIntersections++;
                }
              }
              score += rayIntersections * 48.0;

              // Prefer placements near the center early, spreading out later
              final centerDist =
                  ((gx - gridSize / 2.0).abs() + (gy - gridSize / 2.0).abs());
              if (carIdx < targetCars ~/ 2) {
                score -= centerDist * 3.5;
              }

              // Prefer one-way exit constraint (more strategic!)
              if (exitNeg != exitPos) {
                score += 18.0;
              }

              // Reward alternating orientations
              if (placedCars.isNotEmpty &&
                  placedCars.last.orientation != orient) {
                score += 12.0;
              }

              if (len == 3) {
                score += 15.0;
              }

              if (score > bestScore) {
                bestScore = score;
                bestX = gx;
                bestY = gy;
                bestLen = len;
                bestOrient = orient;
              }
            }
          }
        }
      }

      if (bestX == null ||
          bestY == null ||
          bestLen == null ||
          bestOrient == null) {
        break;
      }

      // Mark grid cells occupied
      for (int i = 0; i < bestLen; i++) {
        final cx =
            bestOrient == CarOrientation.horizontal ? bestX + i : bestX;
        final cy = bestOrient == CarOrientation.vertical ? bestY + i : bestY;
        grid[cy][cx] = carIdx + 1;
      }

      // Choose visual style and facing direction
      final exitPos = canExitOnCurrentGrid(
        gx: bestX,
        gy: bestY,
        length: bestLen,
        orientation: bestOrient,
        dirSign: 1,
      );
      final exitNeg = canExitOnCurrentGrid(
        gx: bestX,
        gy: bestY,
        length: bestLen,
        orientation: bestOrient,
        dirSign: -1,
      );
      final bool facingPos = (exitPos && !exitNeg)
          ? true
          : (!exitPos && exitNeg)
              ? false
              : rng.nextBool();

      final isVipCar = carIdx == 0 && safeLevel >= 2; // First placed = deepest locked VIP car!
      final carType = _pickCarType(bestLen, carIdx, safeLevel, rng);
      final colors = _pickCarColors(carType, isVipCar, carIdx, skinPack);

      placedCars.add(
        ParkingCar(
          id: 'car_${safeLevel}_$carIdx',
          gridX: bestX,
          gridY: bestY,
          length: bestLen,
          orientation: bestOrient,
          facingPositive: facingPos,
          type: carType,
          primaryColor: colors.$1,
          secondaryColor: colors.$2,
          isVip: isVipCar,
        ),
      );
    }

    return LevelData(
      levelNumber: safeLevel,
      gridSize: gridSize,
      isBossLevel: isBoss,
      cars: placedCars,
      obstacles: obstacles,
      walls: walls,
      parMoves: placedCars.length + (isBoss ? 2 : 1),
    );
  }

  static CarType _pickCarType(int length, int idx, int level, Random rng) {
    if (length == 3) {
      const longTypes = [CarType.bus, CarType.limo, CarType.fireTruck];
      return longTypes[(idx + level) % longTypes.length];
    }
    const stdTypes = [
      CarType.sedan,
      CarType.sports,
      CarType.suv,
      CarType.pickup,
      CarType.taxi,
      CarType.police,
    ];
    return stdTypes[(idx * 3 + level) % stdTypes.length];
  }

  static (Color, Color) _pickCarColors(
    CarType type,
    bool isVip,
    int idx,
    CarSkinPack skinPack,
  ) {
    if (isVip) {
      return (const Color(0xFFFFD700), const Color(0xFFFFFBEB));
    }
    if (type == CarType.taxi) {
      return (const Color(0xFFFACC15), const Color(0xFF1E293B));
    }
    if (type == CarType.police) {
      return (const Color(0xFF1E293B), const Color(0xFFFFFFFF));
    }
    if (type == CarType.fireTruck) {
      return (const Color(0xFFDC2626), const Color(0xFFFDE047));
    }
    final palette = skinPack.palette;
    final primary = palette[idx % palette.length];
    final hsl = HSLColor.fromColor(primary);
    final secondary = hsl
        .withLightness((hsl.lightness + 0.22).clamp(0.0, 0.95))
        .toColor();
    return (primary, secondary);
  }

  /// Evaluates what happens when [car] is pushed in [directionSign] (-1 or +1)
  /// along its movement axis.
  static MoveCheckResult evaluateMove({
    required LevelData level,
    required List<ParkingCar> activeCars,
    required ParkingCar car,
    required int directionSign,
  }) {
    final gridSize = level.gridSize;
    final ExitDirection targetDir;
    if (car.orientation == CarOrientation.horizontal) {
      targetDir = directionSign < 0 ? ExitDirection.west : ExitDirection.east;
    } else {
      targetDir = directionSign < 0 ? ExitDirection.north : ExitDirection.south;
    }

    int freeSteps = 0;

    if (car.orientation == CarOrientation.horizontal) {
      final y = car.gridY;
      int checkX = directionSign < 0 ? car.gridX - 1 : car.gridX + car.length;

      while (checkX >= 0 && checkX < gridSize) {
        if (level.hasObstacle(checkX, y)) {
          return MoveCheckResult(
            canExit: false,
            freeCellsToSlide: freeSteps,
            targetDirection: targetDir,
            hitWallOrObstacle: true,
          );
        }
        ParkingCar? blocker;
        for (final other in activeCars) {
          if (other.id != car.id && other.occupiesCell(checkX, y)) {
            blocker = other;
            break;
          }
        }
        if (blocker != null) {
          return MoveCheckResult(
            canExit: false,
            freeCellsToSlide: freeSteps,
            targetDirection: targetDir,
            blockingCar: blocker,
          );
        }
        freeSteps++;
        checkX += directionSign;
      }

      // Reached border edge at row y: check if there's a perimeter wall
      if (level.hasWall(targetDir, y)) {
        return MoveCheckResult(
          canExit: false,
          freeCellsToSlide: freeSteps,
          targetDirection: targetDir,
          hitWallOrObstacle: true,
        );
      }

      return MoveCheckResult(
        canExit: true,
        freeCellsToSlide: freeSteps,
        targetDirection: targetDir,
      );
    } else {
      final x = car.gridX;
      int checkY = directionSign < 0 ? car.gridY - 1 : car.gridY + car.length;

      while (checkY >= 0 && checkY < gridSize) {
        if (level.hasObstacle(x, checkY)) {
          return MoveCheckResult(
            canExit: false,
            freeCellsToSlide: freeSteps,
            targetDirection: targetDir,
            hitWallOrObstacle: true,
          );
        }
        ParkingCar? blocker;
        for (final other in activeCars) {
          if (other.id != car.id && other.occupiesCell(x, checkY)) {
            blocker = other;
            break;
          }
        }
        if (blocker != null) {
          return MoveCheckResult(
            canExit: false,
            freeCellsToSlide: freeSteps,
            targetDirection: targetDir,
            blockingCar: blocker,
          );
        }
        freeSteps++;
        checkY += directionSign;
      }

      // Reached border edge at col x: check if there's a perimeter wall
      if (level.hasWall(targetDir, x)) {
        return MoveCheckResult(
          canExit: false,
          freeCellsToSlide: freeSteps,
          targetDirection: targetDir,
          hitWallOrObstacle: true,
        );
      }

      return MoveCheckResult(
        canExit: true,
        freeCellsToSlide: freeSteps,
        targetDirection: targetDir,
      );
    }
  }

  /// Finds the next car that has an unobstructed exit path (used for Hints & Auto-Solve).
  static HintMove? findHintMove({
    required LevelData level,
    required List<ParkingCar> activeCars,
  }) {
    final parkedCars = activeCars
        .where((c) => c.state == CarAnimState.parked)
        .toList()
        .reversed;

    for (final car in parkedCars) {
      // Prefer the direction the car is already facing first
      final preferredDirs = car.facingPositive ? [1, -1] : [-1, 1];
      for (final dirSign in preferredDirs) {
        final res = evaluateMove(
          level: level,
          activeCars: activeCars,
          car: car,
          directionSign: dirSign,
        );
        if (res.canExit) {
          return HintMove(
            car: car,
            directionSign: dirSign,
            exitDirection: res.targetDirection,
          );
        }
      }
    }
    return null;
  }
}
