import 'dart:math';
import 'package:flutter/material.dart';
import '../models/game_models.dart';

class Camera3DConfig {
  final double yaw; // radians around Z axis
  final double pitch; // elevation angle
  final double zoom;

  const Camera3DConfig({
    this.yaw = -0.62,
    this.pitch = 0.96,
    this.zoom = 1.0,
  });

  Camera3DConfig copyWith({
    double? yaw,
    double? pitch,
    double? zoom,
  }) {
    return Camera3DConfig(
      yaw: yaw ?? this.yaw,
      pitch: pitch ?? this.pitch,
      zoom: zoom ?? this.zoom,
    );
  }
}

class _Face3D {
  final List<Offset> points2D;
  final double depth;
  final Color color;
  final Color? strokeColor;

  const _Face3D({
    required this.points2D,
    required this.depth,
    required this.color,
    this.strokeColor,
  });
}

class _Drawable3DItem {
  final double depth;
  final void Function(Canvas canvas) draw;

  const _Drawable3DItem({
    required this.depth,
    required this.draw,
  });
}

class Parking3DPainter extends CustomPainter {
  final LevelData level;
  final List<ParkingCar> cars;
  final List<Particle3D> particles;
  final List<FloatingBadge3D> badges;
  final EnvironmentTheme theme;
  final Camera3DConfig camera;
  final String? selectedCarId;
  final double animTime;
  final bool helicopterModeActive;

  Parking3DPainter({
    required this.level,
    required this.cars,
    required this.particles,
    required this.badges,
    required this.theme,
    required this.camera,
    required this.animTime,
    this.selectedCarId,
    this.helicopterModeActive = false,
  });

  double _scale(Size size) {
    final totalSpan = level.gridSize + 4.8;
    final shortest = min(size.width, size.height * 1.08);
    return (shortest / totalSpan) * camera.zoom;
  }

  Offset _centerOffset(Size size) {
    return Offset(size.width * 0.5, size.height * 0.52);
  }

  /// Projects a 3D world coordinate (x, y in grid cells, z in height units)
  /// to 2D canvas coordinates.
  Offset project(double x, double y, double z, Size size) {
    final half = level.gridSize / 2.0;
    final cx = x - half;
    final cy = y - half;

    final cosYaw = cos(camera.yaw);
    final sinYaw = sin(camera.yaw);
    final rx = cx * cosYaw - cy * sinYaw;
    final ry = cx * sinYaw + cy * cosYaw;

    final cosPitch = cos(camera.pitch);
    final sinPitch = sin(camera.pitch);

    final screenX = rx;
    final screenY = ry * sinPitch - z * cosPitch;

    final s = _scale(size);
    final center = _centerOffset(size);
    return Offset(center.dx + screenX * s, center.dy + screenY * s);
  }

  /// Computes camera-space depth (larger values = closer to viewer).
  double depthOf(double x, double y, double z) {
    final half = level.gridSize / 2.0;
    final cx = x - half;
    final cy = y - half;
    final sinYaw = sin(camera.yaw);
    final cosYaw = cos(camera.yaw);
    final ry = cx * sinYaw + cy * cosYaw;
    return ry * cos(camera.pitch) + z * sin(camera.pitch);
  }

  /// Unprojects a 2D touch point on screen onto a horizontal plane at height [planeZ].
  Offset unprojectToPlane(Offset screenPt, Size size, {double planeZ = 0.3}) {
    final s = _scale(size);
    final center = _centerOffset(size);
    final sx = (screenPt.dx - center.dx) / s;
    final sy = (screenPt.dy - center.dy) / s;

    final sinPitch = sin(camera.pitch);
    final cosPitch = cos(camera.pitch);

    final rx = sx;
    final ry = (sy + planeZ * cosPitch) / max(0.2, sinPitch);

    final cosYaw = cos(camera.yaw);
    final sinYaw = sin(camera.yaw);

    final cx = rx * cosYaw + ry * sinYaw;
    final cy = -rx * sinYaw + ry * cosYaw;

    final half = level.gridSize / 2.0;
    return Offset(cx + half, cy + half);
  }

  /// Converts a 2D screen drag delta into a 3D world XY vector.
  Offset screenDeltaToWorld(Offset deltaScreen, Size size) {
    final p0 = unprojectToPlane(Offset.zero, size, planeZ: 0.0);
    final p1 = unprojectToPlane(deltaScreen, size, planeZ: 0.0);
    return p1 - p0;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _drawSkyAndBackdrop(canvas, size);
    _drawSurroundingEnvironment(canvas, size);
    _drawPerimeterHighway(canvas, size);
    _drawParkingLotBase(canvas, size);

    // Collect all 3D objects for depth-sorted Painter's Algorithm rendering
    final drawables = <_Drawable3DItem>[];

    // 1. Decorative outer trees / lamps
    _addOuterSceneryDrawables(drawables, size);

    // 2. Perimeter curb barrier walls
    for (final wall in level.walls) {
      drawables.add(_buildWallDrawable(wall, size));
    }

    // 3. Corner bollards around the parking lot
    final g = level.gridSize.toDouble();
    final corners = [
      const Offset(-0.15, -0.15),
      Offset(g + 0.15, -0.15),
      Offset(-0.15, g + 0.15),
      Offset(g + 0.15, g + 0.15),
    ];
    for (final c in corners) {
      drawables.add(
        _Drawable3DItem(
          depth: depthOf(c.dx, c.dy, 0.25),
          draw: (canvas) => _drawCornerPost(canvas, size, c.dx, c.dy),
        ),
      );
    }

    // 4. Internal obstacles
    for (final obs in level.obstacles) {
      drawables.add(_buildObstacleDrawable(obs, size));
    }

    // 5. Cars
    for (final car in cars) {
      if (car.state == CarAnimState.exited) continue;
      drawables.add(_buildCarDrawable(car, size));
    }

    // 6. 3D Particles
    for (final p in particles) {
      drawables.add(
        _Drawable3DItem(
          depth: depthOf(p.x, p.y, p.z) + 0.4,
          draw: (canvas) => _drawParticle(canvas, size, p),
        ),
      );
    }

    // Sort back-to-front by camera depth
    drawables.sort((a, b) => a.depth.compareTo(b.depth));

    for (final item in drawables) {
      item.draw(canvas);
    }

    // 7. Floating 3D text badges always on top
    for (final badge in badges) {
      _drawFloatingBadge(canvas, size, badge);
    }

    // 8. Helicopter target mode overlay hint
    if (helicopterModeActive) {
      _drawHelicopterRadarOverlay(canvas, size);
    }
  }

  void _drawSkyAndBackdrop(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final skyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [theme.skyTop, theme.skyBottom],
      ).createShader(rect);
    canvas.drawRect(rect, skyPaint);

    if (theme.isNight) {
      final starPaint = Paint()..color = Colors.white.withValues(alpha: 0.45);
      for (int i = 0; i < 28; i++) {
        final sx = ((i * 97) % 100) / 100.0 * size.width;
        final sy = ((i * 53) % 100) / 100.0 * (size.height * 0.35);
        final twinkle = 1.0 + 0.8 * sin(animTime * 3.0 + i);
        canvas.drawCircle(Offset(sx, sy), twinkle, starPaint);
      }
    }
  }

  void _drawSurroundingEnvironment(Canvas canvas, Size size) {
    final g = level.gridSize.toDouble();
    const margin = 3.2;
    _drawExtrudedBoxAxisAligned(
      canvas,
      size,
      minX: -margin,
      maxX: g + margin,
      minY: -margin,
      maxY: g + margin,
      minZ: -0.28,
      maxZ: -0.06,
      topColor: theme.groundColor,
      sideColorA: _darken(theme.groundColor, 0.22),
      sideColorB: _darken(theme.groundColor, 0.35),
    );
  }

  void _drawPerimeterHighway(Canvas canvas, Size size) {
    final g = level.gridSize.toDouble();
    const roadMargin = 1.85;

    // Outer perimeter asphalt ring
    _drawExtrudedBoxAxisAligned(
      canvas,
      size,
      minX: -roadMargin,
      maxX: g + roadMargin,
      minY: -roadMargin,
      maxY: g + roadMargin,
      minZ: -0.06,
      maxZ: 0.0,
      topColor: theme.roadColor,
      sideColorA: _darken(theme.roadColor, 0.25),
      sideColorB: _darken(theme.roadColor, 0.38),
    );

    // Dashed highway lane markings along the 4 perimeter roads
    final dashPaint = Paint()
      ..color = Colors.amberAccent.withValues(alpha: 0.55)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    const laneOffset = 0.95;
    for (double t = -0.8; t < g + 0.8; t += 0.9) {
      // North road
      canvas.drawLine(
        project(t, -laneOffset, 0.01, size),
        project(t + 0.45, -laneOffset, 0.01, size),
        dashPaint,
      );
      // South road
      canvas.drawLine(
        project(t, g + laneOffset, 0.01, size),
        project(t + 0.45, g + laneOffset, 0.01, size),
        dashPaint,
      );
      // West road
      canvas.drawLine(
        project(-laneOffset, t, 0.01, size),
        project(-laneOffset, t + 0.45, 0.01, size),
        dashPaint,
      );
      // East road
      canvas.drawLine(
        project(g + laneOffset, t, 0.01, size),
        project(g + laneOffset, t + 0.45, 0.01, size),
        dashPaint,
      );
    }
  }

  void _drawParkingLotBase(Canvas canvas, Size size) {
    final g = level.gridSize.toDouble();

    // Raised parking lot platform
    _drawExtrudedBoxAxisAligned(
      canvas,
      size,
      minX: -0.12,
      maxX: g + 0.12,
      minY: -0.12,
      maxY: g + 0.12,
      minZ: 0.0,
      maxZ: 0.07,
      topColor: theme.curbColor,
      sideColorA: _darken(theme.curbColor, 0.25),
      sideColorB: _darken(theme.curbColor, 0.38),
    );

    // Inner asphalt surface
    final asphaltQuad = Path()
      ..moveTo(project(0, 0, 0.075, size).dx, project(0, 0, 0.075, size).dy)
      ..lineTo(project(g, 0, 0.075, size).dx, project(g, 0, 0.075, size).dy)
      ..lineTo(project(g, g, 0.075, size).dx, project(g, g, 0.075, size).dy)
      ..lineTo(project(0, g, 0.075, size).dx, project(0, g, 0.075, size).dy)
      ..close();

    canvas.drawPath(asphaltQuad, Paint()..color = theme.lotAsphaltColor);

    // Grid stall lines
    final gridPaint = Paint()
      ..color = theme.stallLineColor.withValues(alpha: 0.24)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    for (int i = 0; i <= level.gridSize; i++) {
      final d = i.toDouble();
      canvas.drawLine(
        project(d, 0, 0.08, size),
        project(d, g, 0.08, size),
        gridPaint,
      );
      canvas.drawLine(
        project(0, d, 0.08, size),
        project(g, d, 0.08, size),
        gridPaint,
      );
    }

    // Draw glowing exit chevrons at open perimeter lanes
    final pulse = 0.45 + 0.35 * sin(animTime * 4.0);
    final arrowPaint = Paint()
      ..color = theme.stallLineColor.withValues(alpha: pulse)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < level.gridSize; i++) {
      final c = i + 0.5;
      if (!level.hasWall(ExitDirection.north, i)) {
        _drawExitChevron(canvas, size, c, -0.35, 0, -1, arrowPaint);
      }
      if (!level.hasWall(ExitDirection.south, i)) {
        _drawExitChevron(canvas, size, c, g + 0.35, 0, 1, arrowPaint);
      }
      if (!level.hasWall(ExitDirection.west, i)) {
        _drawExitChevron(canvas, size, -0.35, c, -1, 0, arrowPaint);
      }
      if (!level.hasWall(ExitDirection.east, i)) {
        _drawExitChevron(canvas, size, g + 0.35, c, 1, 0, arrowPaint);
      }
    }
  }

  void _drawExitChevron(
    Canvas canvas,
    Size size,
    double cx,
    double cy,
    double dx,
    double dy,
    Paint paint,
  ) {
    final tip = project(cx + dx * 0.16, cy + dy * 0.16, 0.02, size);
    final left = project(
      cx - dx * 0.12 - dy * 0.18,
      cy - dy * 0.12 + dx * 0.18,
      0.02,
      size,
    );
    final right = project(
      cx - dx * 0.12 + dy * 0.18,
      cy - dy * 0.12 - dx * 0.18,
      0.02,
      size,
    );
    final path = Path()
      ..moveTo(left.dx, left.dy)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(right.dx, right.dy);
    canvas.drawPath(path, paint);
  }

  void _addOuterSceneryDrawables(List<_Drawable3DItem> drawables, Size size) {
    final g = level.gridSize.toDouble();
    final treeCoords = <Offset>[
      const Offset(-2.45, -2.45),
      Offset(g * 0.5, -2.55),
      Offset(g + 2.45, -2.45),
      Offset(-2.55, g * 0.5),
      Offset(g + 2.55, g * 0.5),
      Offset(-2.45, g + 2.45),
      Offset(g * 0.5, g + 2.55),
      Offset(g + 2.45, g + 2.45),
    ];

    for (final pos in treeCoords) {
      drawables.add(
        _Drawable3DItem(
          depth: depthOf(pos.dx, pos.dy, 0.5),
          draw: (canvas) => _drawTree3D(canvas, size, pos.dx, pos.dy),
        ),
      );
    }
  }

  void _drawTree3D(Canvas canvas, Size size, double x, double y) {
    // Soft shadow
    final shadowCenter = project(x + 0.12, y + 0.12, -0.05, size);
    final s = _scale(size);
    canvas.drawOval(
      Rect.fromCenter(
        center: shadowCenter,
        width: s * 0.75,
        height: s * 0.48,
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.25),
    );

    // Trunk
    _drawExtrudedBoxAxisAligned(
      canvas,
      size,
      minX: x - 0.10,
      maxX: x + 0.10,
      minY: y - 0.10,
      maxY: y + 0.10,
      minZ: -0.05,
      maxZ: 0.45,
      topColor: const Color(0xFF78350F),
      sideColorA: const Color(0xFF78350F),
      sideColorB: const Color(0xFF451A03),
    );

    // Layered 3D foliage blocks
    _drawExtrudedBoxAxisAligned(
      canvas,
      size,
      minX: x - 0.36,
      maxX: x + 0.36,
      minY: y - 0.36,
      maxY: y + 0.36,
      minZ: 0.38,
      maxZ: 0.85,
      topColor: _lighten(theme.treeFoliageColor, 0.1),
      sideColorA: theme.treeFoliageColor,
      sideColorB: _darken(theme.treeFoliageColor, 0.22),
    );

    _drawExtrudedBoxAxisAligned(
      canvas,
      size,
      minX: x - 0.24,
      maxX: x + 0.24,
      minY: y - 0.24,
      maxY: y + 0.24,
      minZ: 0.85,
      maxZ: 1.22,
      topColor: _lighten(theme.treeFoliageColor, 0.22),
      sideColorA: _lighten(theme.treeFoliageColor, 0.05),
      sideColorB: _darken(theme.treeFoliageColor, 0.15),
    );
  }

  _Drawable3DItem _buildWallDrawable(PerimeterWall wall, Size size) {
    final g = level.gridSize.toDouble();
    final idx = wall.index.toDouble();
    double minX, maxX, minY, maxY;

    switch (wall.side) {
      case ExitDirection.north:
        minX = idx + 0.06;
        maxX = idx + 0.94;
        minY = -0.22;
        maxY = -0.02;
        break;
      case ExitDirection.south:
        minX = idx + 0.06;
        maxX = idx + 0.94;
        minY = g + 0.02;
        maxY = g + 0.22;
        break;
      case ExitDirection.west:
        minX = -0.22;
        maxX = -0.02;
        minY = idx + 0.06;
        maxY = idx + 0.94;
        break;
      case ExitDirection.east:
        minX = g + 0.02;
        maxX = g + 0.22;
        minY = idx + 0.06;
        maxY = idx + 0.94;
        break;
    }

    final cx = (minX + maxX) * 0.5;
    final cy = (minY + maxY) * 0.5;

    return _Drawable3DItem(
      depth: depthOf(cx, cy, 0.2),
      draw: (canvas) {
        // Draw 3 alternating red & white 3D barrier segments
        final isHoriz =
            wall.side == ExitDirection.north || wall.side == ExitDirection.south;
        for (int seg = 0; seg < 3; seg++) {
          final t0 = seg / 3.0;
          final t1 = (seg + 1) / 3.0;
          final sx0 = isHoriz ? minX + (maxX - minX) * t0 : minX;
          final sx1 = isHoriz ? minX + (maxX - minX) * t1 : maxX;
          final sy0 = isHoriz ? minY : minY + (maxY - minY) * t0;
          final sy1 = isHoriz ? maxY : minY + (maxY - minY) * t1;

          final baseColor =
              seg.isEven ? const Color(0xFFEF4444) : const Color(0xFFF8FAFC);

          _drawExtrudedBoxAxisAligned(
            canvas,
            size,
            minX: sx0,
            maxX: sx1,
            minY: sy0,
            maxY: sy1,
            minZ: 0.07,
            maxZ: 0.34,
            topColor: _lighten(baseColor, 0.08),
            sideColorA: baseColor,
            sideColorB: _darken(baseColor, 0.24),
          );
        }
      },
    );
  }

  void _drawCornerPost(Canvas canvas, Size size, double x, double y) {
    _drawExtrudedBoxAxisAligned(
      canvas,
      size,
      minX: x - 0.11,
      maxX: x + 0.11,
      minY: y - 0.11,
      maxY: y + 0.11,
      minZ: 0.07,
      maxZ: 0.42,
      topColor: const Color(0xFFFACC15),
      sideColorA: const Color(0xFFEAB308),
      sideColorB: const Color(0xFFA16207),
    );
  }

  _Drawable3DItem _buildObstacleDrawable(GridObstacle obs, Size size) {
    final cx = obs.gridX + 0.5;
    final cy = obs.gridY + 0.5;

    return _Drawable3DItem(
      depth: depthOf(cx, cy, 0.35),
      draw: (canvas) {
        // Base hazard pad on cell
        _drawExtrudedBoxAxisAligned(
          canvas,
          size,
          minX: obs.gridX + 0.12,
          maxX: obs.gridX + 0.88,
          minY: obs.gridY + 0.12,
          maxY: obs.gridY + 0.88,
          minZ: 0.075,
          maxZ: 0.14,
          topColor: const Color(0xFF475569),
          sideColorA: const Color(0xFF334155),
          sideColorB: const Color(0xFF1E293B),
        );

        switch (obs.type) {
          case ObstacleType.bollard:
            _drawExtrudedBoxAxisAligned(
              canvas,
              size,
              minX: cx - 0.16,
              maxX: cx + 0.16,
              minY: cy - 0.16,
              maxY: cy + 0.16,
              minZ: 0.14,
              maxZ: 0.68,
              topColor: const Color(0xFFFACC15),
              sideColorA: const Color(0xFFF59E0B),
              sideColorB: const Color(0xFFB45309),
            );
            break;
          case ObstacleType.fireHydrant:
            _drawExtrudedBoxAxisAligned(
              canvas,
              size,
              minX: cx - 0.18,
              maxX: cx + 0.18,
              minY: cy - 0.18,
              maxY: cy + 0.18,
              minZ: 0.14,
              maxZ: 0.64,
              topColor: const Color(0xFFF87171),
              sideColorA: const Color(0xFFEF4444),
              sideColorB: const Color(0xFF991B1B),
            );
            break;
          case ObstacleType.planter:
            _drawExtrudedBoxAxisAligned(
              canvas,
              size,
              minX: cx - 0.28,
              maxX: cx + 0.28,
              minY: cy - 0.28,
              maxY: cy + 0.28,
              minZ: 0.14,
              maxZ: 0.58,
              topColor: const Color(0xFF22C55E),
              sideColorA: const Color(0xFF16A34A),
              sideColorB: const Color(0xFF14532D),
            );
            break;
          case ObstacleType.charger:
            _drawExtrudedBoxAxisAligned(
              canvas,
              size,
              minX: cx - 0.20,
              maxX: cx + 0.20,
              minY: cy - 0.14,
              maxY: cy + 0.14,
              minZ: 0.14,
              maxZ: 0.78,
              topColor: const Color(0xFF38BDF8),
              sideColorA: const Color(0xFF0284C7),
              sideColorB: const Color(0xFF0369A1),
            );
            break;
        }
      },
    );
  }

  _Drawable3DItem _buildCarDrawable(ParkingCar car, Size size) {
    // Compute car center in 3D grid coordinates
    final double halfLen = car.length / 2.0;
    final double centerX;
    final double centerY;

    if (car.orientation == CarOrientation.horizontal) {
      centerX = car.animX + halfLen;
      centerY = car.animY + 0.5;
    } else {
      centerX = car.animX + 0.5;
      centerY = car.animY + halfLen;
    }

    // Apply collision shake offset if bumping
    final shakeOffset = car.shakeTimer > 0
        ? sin(car.shakeTimer * 36.0) * 0.11 * car.shakeDirection * car.shakeTimer
        : 0.0;

    final drawCenterX = centerX + cos(car.yawAngle) * shakeOffset;
    final drawCenterY = centerY + sin(car.yawAngle) * shakeOffset;
    final baseZ = 0.08 + car.animZ;

    return _Drawable3DItem(
      depth: depthOf(drawCenterX, drawCenterY, baseZ + 0.35),
      draw: (canvas) {
        _drawDetailedCar3D(
          canvas,
          size,
          car: car,
          cx: drawCenterX,
          cy: drawCenterY,
          baseZ: baseZ,
        );
      },
    );
  }

  void _drawDetailedCar3D(
    Canvas canvas,
    Size size, {
    required ParkingCar car,
    required double cx,
    required double cy,
    required double baseZ,
  }) {
    final halfL = car.length * 0.44;
    const halfW = 0.37;

    // 1. Ground shadow on asphalt (z = 0.082)
    final shadowCorners = [
      _transformCarLocal(cx, cy, 0.082, -halfL * 1.04, -halfW * 1.06, car.yawAngle, 0),
      _transformCarLocal(cx, cy, 0.082, halfL * 1.04, -halfW * 1.06, car.yawAngle, 0),
      _transformCarLocal(cx, cy, 0.082, halfL * 1.04, halfW * 1.06, car.yawAngle, 0),
      _transformCarLocal(cx, cy, 0.082, -halfL * 1.04, halfW * 1.06, car.yawAngle, 0),
    ];
    final shadowPath = Path();
    for (int i = 0; i < 4; i++) {
      final pt = project(
        shadowCorners[i].$1 + 0.07,
        shadowCorners[i].$2 + 0.07,
        shadowCorners[i].$3,
        size,
      );
      if (i == 0) {
        shadowPath.moveTo(pt.dx, pt.dy);
      } else {
        shadowPath.lineTo(pt.dx, pt.dy);
      }
    }
    shadowPath.close();
    canvas.drawPath(
      shadowPath,
      Paint()
        ..color = Colors.black.withValues(
          alpha: (0.38 - car.animZ * 0.08).clamp(0.08, 0.38),
        ),
    );

    // 2. Highlight / Selection / Hint Aura under car
    if (car.isHighlighted || car.id == selectedCarId || helicopterModeActive) {
      final auraColor = helicopterModeActive
          ? Colors.amberAccent
          : (car.isHighlighted ? Colors.greenAccent : Colors.cyanAccent);
      canvas.drawPath(
        shadowPath,
        Paint()
          ..color = auraColor.withValues(alpha: 0.65)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.2,
      );
    }

    // 3. Night-mode or active headlight beams on asphalt
    if (theme.isNight || car.state == CarAnimState.exitingLot || car.state == CarAnimState.drivingOnRoad) {
      _drawHeadlightBeams(canvas, size, cx, cy, halfL, halfW, car.yawAngle);
    }

    // 4. 3D Wheels (4 tires)
    final wheelPositions = [
      (-halfL * 0.62, -halfW * 0.96),
      (halfL * 0.62, -halfW * 0.96),
      (-halfL * 0.62, halfW * 0.96),
      (halfL * 0.62, halfW * 0.96),
    ];
    for (final wp in wheelPositions) {
      _drawOrientedPrism(
        canvas,
        size,
        cx: cx,
        cy: cy,
        yaw: car.yawAngle,
        pitch: car.tiltPitch,
        localMinX: wp.$1 - 0.16,
        localMaxX: wp.$1 + 0.16,
        localMinY: wp.$2 - 0.06,
        localMaxY: wp.$2 + 0.06,
        minZ: baseZ,
        maxZ: baseZ + 0.18,
        topColor: const Color(0xFF1E293B),
        frontColor: const Color(0xFF0F172A),
        sideColor: const Color(0xFF334155),
      );
    }

    // 5. Lower Car Chassis Body
    final chassisHeight = car.length == 3 ? 0.42 : 0.32;
    _drawOrientedPrism(
      canvas,
      size,
      cx: cx,
      cy: cy,
      yaw: car.yawAngle,
      pitch: car.tiltPitch,
      localMinX: -halfL,
      localMaxX: halfL,
      localMinY: -halfW,
      localMaxY: halfW,
      minZ: baseZ + 0.08,
      maxZ: baseZ + 0.08 + chassisHeight,
      topColor: _lighten(car.primaryColor, 0.12),
      frontColor: _darken(car.primaryColor, 0.16),
      sideColor: car.primaryColor,
      strokeColor: Colors.black.withValues(alpha: 0.25),
    );

    // 6. Headlights (+X front face) & Taillights (-X rear face)
    for (final sideSign in [-1.0, 1.0]) {
      // Front Headlight (+halfL)
      _drawOrientedPrism(
        canvas,
        size,
        cx: cx,
        cy: cy,
        yaw: car.yawAngle,
        pitch: car.tiltPitch,
        localMinX: halfL - 0.03,
        localMaxX: halfL + 0.02,
        localMinY: sideSign * halfW * 0.62 - 0.07,
        localMaxY: sideSign * halfW * 0.62 + 0.07,
        minZ: baseZ + 0.16,
        maxZ: baseZ + 0.28,
        topColor: const Color(0xFFFEF08A),
        frontColor: const Color(0xFFFFFFFF),
        sideColor: const Color(0xFFFDE047),
      );

      // Rear Taillight (-halfL)
      _drawOrientedPrism(
        canvas,
        size,
        cx: cx,
        cy: cy,
        yaw: car.yawAngle,
        pitch: car.tiltPitch,
        localMinX: -halfL - 0.02,
        localMaxX: -halfL + 0.03,
        localMinY: sideSign * halfW * 0.62 - 0.07,
        localMaxY: sideSign * halfW * 0.62 + 0.07,
        minZ: baseZ + 0.16,
        maxZ: baseZ + 0.28,
        topColor: const Color(0xFFF87171),
        frontColor: const Color(0xFFEF4444),
        sideColor: const Color(0xFFDC2626),
      );
    }

    // 7. Upper Cabin / Greenhouse + Windshield Glass
    final cabinMinX = car.type == CarType.bus
        ? -halfL * 0.86
        : (car.type == CarType.pickup ? -halfL * 0.15 : -halfL * 0.52);
    final cabinMaxX = car.type == CarType.bus
        ? halfL * 0.86
        : halfL * 0.42;
    final cabinBaseZ = baseZ + 0.08 + chassisHeight;
    final cabinTopZ = cabinBaseZ + (car.type == CarType.sports ? 0.20 : 0.25);

    // Dark tinted glass block
    _drawOrientedPrism(
      canvas,
      size,
      cx: cx,
      cy: cy,
      yaw: car.yawAngle,
      pitch: car.tiltPitch,
      localMinX: cabinMinX,
      localMaxX: cabinMaxX,
      localMinY: -halfW * 0.82,
      localMaxY: halfW * 0.82,
      minZ: cabinBaseZ,
      maxZ: cabinTopZ - 0.04,
      topColor: const Color(0xFF1E293B),
      frontColor: const Color(0xFF0F172A),
      sideColor: const Color(0xFF334155),
    );

    // Roof cap on top of glass
    _drawOrientedPrism(
      canvas,
      size,
      cx: cx,
      cy: cy,
      yaw: car.yawAngle,
      pitch: car.tiltPitch,
      localMinX: cabinMinX + 0.05,
      localMaxX: cabinMaxX - 0.05,
      localMinY: -halfW * 0.78,
      localMaxY: halfW * 0.78,
      minZ: cabinTopZ - 0.04,
      maxZ: cabinTopZ,
      topColor: car.secondaryColor,
      frontColor: car.primaryColor,
      sideColor: _lighten(car.primaryColor, 0.08),
    );

    // 8. Special 3D Roof Add-ons (Police siren, Taxi sign, Spoiler, Fire ladder, VIP crown)
    if (car.type == CarType.police) {
      final flash = (animTime * 8.0).floor().isEven;
      _drawOrientedPrism(
        canvas,
        size,
        cx: cx,
        cy: cy,
        yaw: car.yawAngle,
        pitch: car.tiltPitch,
        localMinX: -0.10,
        localMaxX: 0.10,
        localMinY: -0.22,
        localMaxY: 0.0,
        minZ: cabinTopZ,
        maxZ: cabinTopZ + 0.09,
        topColor: flash ? const Color(0xFFEF4444) : const Color(0xFF3B82F6),
        frontColor: const Color(0xFFEF4444),
        sideColor: const Color(0xFFDC2626),
      );
      _drawOrientedPrism(
        canvas,
        size,
        cx: cx,
        cy: cy,
        yaw: car.yawAngle,
        pitch: car.tiltPitch,
        localMinX: -0.10,
        localMaxX: 0.10,
        localMinY: 0.0,
        localMaxY: 0.22,
        minZ: cabinTopZ,
        maxZ: cabinTopZ + 0.09,
        topColor: flash ? const Color(0xFF3B82F6) : const Color(0xFFEF4444),
        frontColor: const Color(0xFF3B82F6),
        sideColor: const Color(0xFF2563EB),
      );
    } else if (car.type == CarType.taxi) {
      _drawOrientedPrism(
        canvas,
        size,
        cx: cx,
        cy: cy,
        yaw: car.yawAngle,
        pitch: car.tiltPitch,
        localMinX: -0.12,
        localMaxX: 0.12,
        localMinY: -0.16,
        localMaxY: 0.16,
        minZ: cabinTopZ,
        maxZ: cabinTopZ + 0.10,
        topColor: const Color(0xFFFEF08A),
        frontColor: const Color(0xFF1E293B),
        sideColor: const Color(0xFFFACC15),
      );
    } else if (car.type == CarType.sports) {
      // Rear spoiler wing
      _drawOrientedPrism(
        canvas,
        size,
        cx: cx,
        cy: cy,
        yaw: car.yawAngle,
        pitch: car.tiltPitch,
        localMinX: -halfL + 0.04,
        localMaxX: -halfL + 0.16,
        localMinY: -halfW * 0.85,
        localMaxY: halfW * 0.85,
        minZ: baseZ + 0.42,
        maxZ: baseZ + 0.50,
        topColor: car.secondaryColor,
        frontColor: _darken(car.primaryColor, 0.25),
        sideColor: car.primaryColor,
      );
    } else if (car.type == CarType.fireTruck) {
      // Silver ladder on roof
      _drawOrientedPrism(
        canvas,
        size,
        cx: cx,
        cy: cy,
        yaw: car.yawAngle,
        pitch: car.tiltPitch,
        localMinX: -halfL * 0.7,
        localMaxX: halfL * 0.5,
        localMinY: -0.14,
        localMaxY: 0.14,
        minZ: cabinTopZ,
        maxZ: cabinTopZ + 0.08,
        topColor: const Color(0xFFF8FAFC),
        frontColor: const Color(0xFFCBD5E1),
        sideColor: const Color(0xFF94A3B8),
      );
    }

    // VIP Star Indicator above VIP car
    if (car.isVip && car.state == CarAnimState.parked) {
      final vipPt = project(
        cx,
        cy,
        cabinTopZ + 0.28 + 0.06 * sin(animTime * 5.0),
        size,
      );
      canvas.drawCircle(
        vipPt,
        9,
        Paint()..color = const Color(0xFFFFD700),
      );
      canvas.drawCircle(
        vipPt,
        9,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8,
      );
    }

    // Helicopter cable when being lifted
    if (car.state == CarAnimState.helicopterLift) {
      final roofCenter = project(cx, cy, cabinTopZ, size);
      final skyHook = project(cx, cy, cabinTopZ + 4.5, size);
      canvas.drawLine(
        roofCenter,
        skyHook,
        Paint()
          ..color = Colors.amberAccent
          ..strokeWidth = 3.0,
      );
    }
  }

  void _drawHeadlightBeams(
    Canvas canvas,
    Size size,
    double cx,
    double cy,
    double halfL,
    double halfW,
    double yaw,
  ) {
    final p1 = _transformCarLocal(cx, cy, 0.085, halfL, -halfW * 0.65, yaw, 0);
    final p2 = _transformCarLocal(cx, cy, 0.085, halfL, halfW * 0.65, yaw, 0);
    final p3 = _transformCarLocal(cx, cy, 0.085, halfL + 1.15, halfW * 1.15, yaw, 0);
    final p4 = _transformCarLocal(cx, cy, 0.085, halfL + 1.15, -halfW * 1.15, yaw, 0);

    final beamPath = Path()
      ..moveTo(project(p1.$1, p1.$2, p1.$3, size).dx, project(p1.$1, p1.$2, p1.$3, size).dy)
      ..lineTo(project(p2.$1, p2.$2, p2.$3, size).dx, project(p2.$1, p2.$2, p2.$3, size).dy)
      ..lineTo(project(p3.$1, p3.$2, p3.$3, size).dx, project(p3.$1, p3.$2, p3.$3, size).dy)
      ..lineTo(project(p4.$1, p4.$2, p4.$3, size).dx, project(p4.$1, p4.$2, p4.$3, size).dy)
      ..close();

    canvas.drawPath(
      beamPath,
      Paint()..color = const Color(0xFFFEF08A).withValues(alpha: 0.22),
    );
  }

  (double, double, double) _transformCarLocal(
    double cx,
    double cy,
    double baseZ,
    double lx,
    double ly,
    double yaw,
    double pitch,
  ) {
    final cosY = cos(yaw);
    final sinY = sin(yaw);
    final wx = cx + lx * cosY - ly * sinY;
    final wy = cy + lx * sinY + ly * cosY;
    final wz = baseZ + lx * sin(pitch);
    return (wx, wy, wz);
  }

  void _drawOrientedPrism(
    Canvas canvas,
    Size size, {
    required double cx,
    required double cy,
    required double yaw,
    required double pitch,
    required double localMinX,
    required double localMaxX,
    required double localMinY,
    required double localMaxY,
    required double minZ,
    required double maxZ,
    required Color topColor,
    required Color frontColor,
    required Color sideColor,
    Color? strokeColor,
  }) {
    // 8 vertices in 3D world space
    final v = [
      _transformCarLocal(cx, cy, minZ, localMinX, localMinY, yaw, pitch), // 0
      _transformCarLocal(cx, cy, minZ, localMaxX, localMinY, yaw, pitch), // 1
      _transformCarLocal(cx, cy, minZ, localMaxX, localMaxY, yaw, pitch), // 2
      _transformCarLocal(cx, cy, minZ, localMinX, localMaxY, yaw, pitch), // 3
      _transformCarLocal(cx, cy, maxZ, localMinX, localMinY, yaw, pitch), // 4
      _transformCarLocal(cx, cy, maxZ, localMaxX, localMinY, yaw, pitch), // 5
      _transformCarLocal(cx, cy, maxZ, localMaxX, localMaxY, yaw, pitch), // 6
      _transformCarLocal(cx, cy, maxZ, localMinX, localMaxY, yaw, pitch), // 7
    ];

    final p = v.map((pt) => project(pt.$1, pt.$2, pt.$3, size)).toList();

    double faceDepth(List<int> indices) {
      double sum = 0;
      for (final i in indices) {
        sum += depthOf(v[i].$1, v[i].$2, v[i].$3);
      }
      return sum / indices.length;
    }

    final faces = <_Face3D>[
      // Front (+localX): 1,2,6,5
      _Face3D(
        points2D: [p[1], p[2], p[6], p[5]],
        depth: faceDepth([1, 2, 6, 5]),
        color: frontColor,
        strokeColor: strokeColor,
      ),
      // Back (-localX): 0,3,7,4
      _Face3D(
        points2D: [p[0], p[3], p[7], p[4]],
        depth: faceDepth([0, 3, 7, 4]),
        color: frontColor,
        strokeColor: strokeColor,
      ),
      // Left (-localY): 0,1,5,4
      _Face3D(
        points2D: [p[0], p[1], p[5], p[4]],
        depth: faceDepth([0, 1, 5, 4]),
        color: sideColor,
        strokeColor: strokeColor,
      ),
      // Right (+localY): 3,2,6,7
      _Face3D(
        points2D: [p[3], p[2], p[6], p[7]],
        depth: faceDepth([3, 2, 6, 7]),
        color: _darken(sideColor, 0.12),
        strokeColor: strokeColor,
      ),
      // Top (+Z): 4,5,6,7
      _Face3D(
        points2D: [p[4], p[5], p[6], p[7]],
        depth: faceDepth([4, 5, 6, 7]) + 0.05,
        color: topColor,
        strokeColor: strokeColor,
      ),
    ];

    faces.sort((a, b) => a.depth.compareTo(b.depth));

    for (final face in faces) {
      final path = Path()
        ..moveTo(face.points2D[0].dx, face.points2D[0].dy)
        ..lineTo(face.points2D[1].dx, face.points2D[1].dy)
        ..lineTo(face.points2D[2].dx, face.points2D[2].dy)
        ..lineTo(face.points2D[3].dx, face.points2D[3].dy)
        ..close();

      canvas.drawPath(path, Paint()..color = face.color);
      if (face.strokeColor != null) {
        canvas.drawPath(
          path,
          Paint()
            ..color = face.strokeColor!
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8,
        );
      }
    }
  }

  void _drawExtrudedBoxAxisAligned(
    Canvas canvas,
    Size size, {
    required double minX,
    required double maxX,
    required double minY,
    required double maxY,
    required double minZ,
    required double maxZ,
    required Color topColor,
    required Color sideColorA,
    required Color sideColorB,
  }) {
    final cx = (minX + maxX) * 0.5;
    final cy = (minY + maxY) * 0.5;
    _drawOrientedPrism(
      canvas,
      size,
      cx: cx,
      cy: cy,
      yaw: 0,
      pitch: 0,
      localMinX: minX - cx,
      localMaxX: maxX - cx,
      localMinY: minY - cy,
      localMaxY: maxY - cy,
      minZ: minZ,
      maxZ: maxZ,
      topColor: topColor,
      frontColor: sideColorB,
      sideColor: sideColorA,
    );
  }

  void _drawParticle(Canvas canvas, Size size, Particle3D p) {
    final pt = project(p.x, p.y, p.z, size);
    final alpha = (p.life / p.maxLife).clamp(0.0, 1.0);
    canvas.drawCircle(
      pt,
      p.size * alpha,
      Paint()..color = p.color.withValues(alpha: alpha),
    );
  }

  void _drawFloatingBadge(Canvas canvas, Size size, FloatingBadge3D badge) {
    final pt = project(badge.x, badge.y, badge.z, size);
    final alpha = (badge.life / badge.maxLife).clamp(0.0, 1.0);

    final textSpan = TextSpan(
      text: badge.text,
      style: TextStyle(
        color: badge.color.withValues(alpha: alpha),
        fontSize: 15,
        fontWeight: FontWeight.w900,
        shadows: [
          Shadow(
            color: Colors.black.withValues(alpha: alpha * 0.85),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
    final tp = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    tp.paint(canvas, Offset(pt.dx - tp.width * 0.5, pt.dy - tp.height * 0.5));
  }

  void _drawHelicopterRadarOverlay(Canvas canvas, Size size) {
    final pulse = 0.5 + 0.5 * sin(animTime * 6.0);
    final g = level.gridSize.toDouble();
    final centerPt = project(g * 0.5, g * 0.5, 0.5, size);
    canvas.drawCircle(
      centerPt,
      26 + pulse * 14,
      Paint()
        ..color = Colors.amberAccent.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  static Color _lighten(Color c, double amount) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
        .toColor();
  }

  static Color _darken(Color c, double amount) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor();
  }

  @override
  bool shouldRepaint(covariant Parking3DPainter oldDelegate) => true;
}
