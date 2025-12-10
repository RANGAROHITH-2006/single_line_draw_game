import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:singlelinedraw/svg_path_parser.dart';

/// Draw Controller
/// Manages the drawing interaction, path validation, and game state
/// Handles gesture recognition, progress tracking, and completion detection
/// Now with vertex-aware segment drawing for better path tracing
class DrawController extends ChangeNotifier {
  // Game state
  bool isDrawing = false;
  bool isGameCompleted = false;
  double progress = 0.0;
  String? errorMessage;

  // Drawing data
  List<Offset> userPath = [];
  Path? svgPath;
  double tolerance =
      16.0; // Hit detection tolerance in pixels (optimized for accuracy)

  // Continuous range-based tracking (instead of discrete dots)
  // Each segment has a list of drawn ranges [start, end] along its length
  List<List<List<double>>> drawnRanges =
      []; // [segmentIndex][rangeIndex][start, end]

  // Track the currently active segment index to prevent filling multiple edges at vertices
  int? _activeSegmentIndex;
  double? _lastDistanceOnSegment;

  // Track drawing direction
  bool? _drawingForward; // true = toward end, false = toward start

  // Track which segments have been significantly drawn (> 20% filled)
  Set<int> _drawnSegments = {};

  // Path metrics
  List<ui.PathMetric> pathSegments = [];
  double totalPathLength = 0.0;

  // Vertex-based segments
  List<PathSegmentInfo> vertexSegments = [];
  List<Offset> transformedVertices = [];

  // Callbacks
  VoidCallback? onLevelComplete;
  VoidCallback? onGameReset;

  DrawController({this.onLevelComplete, this.onGameReset});

  /// Initialize the controller with SVG path data
  void initializeWithPath(Path transformedPath) {
    svgPath = transformedPath;
    pathSegments = SvgPathParser.getPathSegments(transformedPath);
    totalPathLength = SvgPathParser.getPathLength(transformedPath);

    // Initialize empty ranges for each segment
    drawnRanges = List.generate(pathSegments.length, (_) => []);

    reset();
  }

  /// Initialize with vertex information for better segment tracking
  void initializeWithVertices(Path transformedPath, List<Offset> vertices) {
    svgPath = transformedPath;
    pathSegments = SvgPathParser.getPathSegments(transformedPath);
    totalPathLength = SvgPathParser.getPathLength(transformedPath);
    transformedVertices = vertices;

    // Extract vertex-based segments
    vertexSegments = SvgPathParser.extractSegmentsWithVertices(
      transformedPath,
      vertices,
    );

    // If not enough segments found, ensure minimum by sampling
    if (vertexSegments.isEmpty && pathSegments.isNotEmpty) {
      // Fall back to simple segment extraction
      _createDefaultVertexSegments();
    }

    // Initialize empty ranges for each segment
    drawnRanges = List.generate(pathSegments.length, (_) => []);

    reset();
  }

  /// Create default vertex segments by sampling the path
  void _createDefaultVertexSegments() {
    vertexSegments = [];
    transformedVertices = [];

    for (int i = 0; i < pathSegments.length; i++) {
      final metric = pathSegments[i];
      final length = metric.length;

      // Sample at least 5 points along each path metric
      final numPoints = (length / 50).ceil().clamp(5, 20);
      final step = length / numPoints;

      List<double> sampleDistances = [];
      for (int j = 0; j <= numPoints; j++) {
        sampleDistances.add((j * step).clamp(0.0, length));
      }

      // Create segments between sample points
      for (int j = 0; j < sampleDistances.length - 1; j++) {
        final startTangent = metric.getTangentForOffset(sampleDistances[j]);
        final endTangent = metric.getTangentForOffset(sampleDistances[j + 1]);

        if (startTangent != null && endTangent != null) {
          if (j == 0 || !transformedVertices.contains(startTangent.position)) {
            transformedVertices.add(startTangent.position);
          }
          if (!transformedVertices.contains(endTangent.position)) {
            transformedVertices.add(endTangent.position);
          }

          vertexSegments.add(
            PathSegmentInfo(
              pathMetricIndex: i,
              startVertex: startTangent.position,
              endVertex: endTangent.position,
              startDistance: sampleDistances[j],
              endDistance: sampleDistances[j + 1],
              startVertexIndex: transformedVertices.length - 2,
              endVertexIndex: transformedVertices.length - 1,
            ),
          );
        }
      }
    }
  }

  /// Get vertices for display
  List<Offset> get vertices => transformedVertices;

  /// Handle pan start - begin drawing
  void onPanStart(DragStartDetails details) {
    if (isGameCompleted) return;

    final localPosition = details.localPosition;

    // Check if starting position is on the path (vertex or middle)
    if (_isPointOnPath(localPosition)) {
      isDrawing = true;
      userPath.clear();
      userPath.add(localPosition);

      // Reset ranges for all segments
      drawnRanges = List.generate(pathSegments.length, (_) => []);

      // Reset active segment tracking
      _activeSegmentIndex = null;
      _lastDistanceOnSegment = null;
      _drawingForward = null;
      _drawnSegments.clear();

      progress = 0.0;
      errorMessage = null;

      // Find segment and auto-fill from start point to nearest endpoint
      _initializeSegmentWithAutoFill(localPosition);

      notifyListeners();
    }
  }

  /// Handle pan update - continue drawing
  void onPanUpdate(DragUpdateDetails details) {
    if (!isDrawing || isGameCompleted) return;

    final localPosition = details.localPosition;

    // Check if current position is valid (on path)
    if (_isPointOnPath(localPosition)) {
      userPath.add(localPosition);

      // Fill in segments between last and current position
      if (userPath.length > 1) {
        _fillPathBetweenOnActiveSegment(
          userPath[userPath.length - 2],
          localPosition,
        );
      }

      _updateProgress();

      // Check for completion - use 95% threshold to account for path detection tolerance
      // This prevents the issue where visually complete paths show as incomplete
      if (progress >= 0.99) {
        _completeLevel();
      }

      notifyListeners();
    } else {
      // User went outside valid path - stop drawing and show error
      _stopDrawingWithError("Stay on the line!");
    }
  }

  /// Handle pan end - finish drawing stroke
  void onPanEnd(DragEndDetails details) {
    if (!isDrawing) return;

    // If not completed and user lifted finger, reset
    if (!isGameCompleted) {
      _stopDrawingWithError("Complete the full outline in one stroke!");
    }

    isDrawing = false;
    notifyListeners();
  }

  /// Reset the game state
  void reset() {
    isDrawing = false;
    isGameCompleted = false;
    progress = 0.0;
    errorMessage = null;
    userPath.clear();
    drawnRanges = List.generate(pathSegments.length, (_) => []);
    _activeSegmentIndex = null;
    _lastDistanceOnSegment = null;
    _drawingForward = null;
    _drawnSegments.clear();
    onGameReset?.call();
    notifyListeners();
  }

  /// Check if a point is on or near the SVG path
  bool _isPointOnPath(Offset point) {
    if (svgPath == null) return false;

    // Optimization: Check active segment first (most likely to be on it)
    // Use fine-grained sampling for smooth movement without stuttering
    if (_activeSegmentIndex != null &&
        _activeSegmentIndex! < pathSegments.length) {
      final pathMetric = pathSegments[_activeSegmentIndex!];
      final length = pathMetric.length;

      // Use very fine sampling (0.5 steps) for smooth, accurate detection
      // Slightly relaxed tolerance for active segment to prevent stuttering
      double activeTolerance = tolerance * 1.2;
      for (double distance = 0; distance < length; distance += 0.5) {
        final ui.Tangent? tangent = pathMetric.getTangentForOffset(distance);
        if (tangent != null) {
          final double currentDistance = (point - tangent.position).distance;
          if (currentDistance <= activeTolerance) {
            return true;
          }
        }
      }
    }

    // If not on active segment, check all segments with fine sampling
    for (ui.PathMetric pathMetric in pathSegments) {
      final length = pathMetric.length;

      // Use fine steps (0.5) for accurate detection across all segments
      for (double distance = 0; distance < length; distance += 0.5) {
        final ui.Tangent? tangent = pathMetric.getTangentForOffset(distance);
        if (tangent != null) {
          final double currentDistance = (point - tangent.position).distance;
          if (currentDistance <= tolerance) {
            return true;
          }
        }
      }
    }
    return false;
  }

  /// Initialize segment with auto-fill to nearest endpoint
  /// When user starts from middle, auto-fill to the closest endpoint
  void _initializeSegmentWithAutoFill(Offset point) {
    // Find the closest point on the path
    int? bestSegmentIndex;
    double? bestDistance;
    double bestMinDist = double.infinity;

    for (
      int segmentIndex = 0;
      segmentIndex < pathSegments.length;
      segmentIndex++
    ) {
      final pathMetric = pathSegments[segmentIndex];
      final length = pathMetric.length;

      // Use very fine steps (0.5) for accurate starting point detection
      for (double distance = 0; distance <= length; distance += 0.5) {
        final ui.Tangent? tangent = pathMetric.getTangentForOffset(distance);
        if (tangent != null) {
          final double currentDist = (point - tangent.position).distance;
          if (currentDist <= tolerance && currentDist < bestMinDist) {
            bestMinDist = currentDist;
            bestSegmentIndex = segmentIndex;
            bestDistance = distance;
          }
        }
      }
    }

    if (bestSegmentIndex == null || bestDistance == null) return;

    _activeSegmentIndex = bestSegmentIndex;
    _lastDistanceOnSegment = bestDistance;

    final pathMetric = pathSegments[bestSegmentIndex];
    final length = pathMetric.length;

    // Determine which endpoint is closer
    double distToStart = bestDistance;
    double distToEnd = length - bestDistance;

    // Auto-fill from start point to the NEAREST endpoint
    if (distToStart <= distToEnd) {
      // Closer to start - fill from 0 to current position
      _addRange(bestSegmentIndex, 0.0, bestDistance);
      _drawingForward = true; // Will draw toward the end
    } else {
      // Closer to end - fill from current position to end
      _addRange(bestSegmentIndex, bestDistance, length);
      _drawingForward = false; // Will draw toward the start
    }
  }

  /// Add a range to a segment, merging with existing overlapping ranges
  void _addRange(int segmentIndex, double start, double end) {
    if (segmentIndex >= drawnRanges.length) return;

    List<List<double>> ranges = drawnRanges[segmentIndex];

    // Find overlapping or adjacent ranges and merge
    List<List<double>> newRanges = [];

    for (var range in ranges) {
      // Check if ranges overlap or are adjacent (within 2 pixels for smoother drawing)
      if (start <= range[1] + 2 && end >= range[0] - 2) {
        // Merge ranges
        start = start < range[0] ? start : range[0];
        end = end > range[1] ? end : range[1];
      } else {
        newRanges.add(range);
      }
    }

    newRanges.add([start, end]);

    // Sort ranges by start position
    newRanges.sort((a, b) => a[0].compareTo(b[0]));

    // Merge any remaining overlapping ranges after sorting
    List<List<double>> finalRanges = [];
    for (var range in newRanges) {
      if (finalRanges.isEmpty || finalRanges.last[1] < range[0] - 2) {
        finalRanges.add(range);
      } else {
        finalRanges.last[1] =
            finalRanges.last[1] > range[1] ? finalRanges.last[1] : range[1];
      }
    }

    drawnRanges[segmentIndex] = finalRanges;
  }

  /// Fill path between two points with gap auto-fill and strict single-segment control
  /// Implements: gap auto-fill for fast movements, strict single-line filling, partial filling
  void _fillPathBetweenOnActiveSegment(Offset startPoint, Offset endPoint) {
    // Calculate the screen distance between the two touch points
    double screenDistance = (endPoint - startPoint).distance;

    // STRICT SINGLE-SEGMENT RULE: Only work on the active segment
    if (_activeSegmentIndex == null || _lastDistanceOnSegment == null) {
      return;
    }

    // Find where the end point is on the ACTIVE segment only
    double? endDistOnActive = _findClosestDistanceOnSegment(
      endPoint,
      _activeSegmentIndex!,
    );

    // If point is not on active segment, check if we should transition
    if (endDistOnActive == null) {
      // Only transition if we're at an endpoint and there's a connected segment
      _checkAndTransitionAtEndpoint(endPoint, screenDistance);
      return;
    }

    // Calculate path distance on the active segment
    double pathDistance = (endDistOnActive - _lastDistanceOnSegment!).abs();
    final length = pathSegments[_activeSegmentIndex!].length;

    // Check if movement is in the correct direction
    bool movingForward = endDistOnActive > _lastDistanceOnSegment!;

    // Set drawing direction on first movement
    if (_drawingForward == null) {
      _drawingForward = movingForward;
    }

    // ADJACENT POINT CHECK: Only fill if points are truly adjacent
    // Use strict multiplier to prevent filling multiple segments at once
    // This ensures user must trace each segment accurately
    double maxAllowedPathDistance = screenDistance * 1.8 + tolerance * 2;

    // If path distance is much larger than screen distance, points aren't adjacent
    if (pathDistance > maxAllowedPathDistance) {
      // Not adjacent - don't fill this gap
      return;
    }

    // Additional smoothness: allow small jumps for very close points
    if (screenDistance < tolerance * 0.8 && pathDistance < tolerance * 1.5) {
      // Very close movement - always fill for smoothness
    }

    // PARTIAL FILLING: Only fill the portion the user actually covers
    double rangeStart =
        _lastDistanceOnSegment! < endDistOnActive
            ? _lastDistanceOnSegment!
            : endDistOnActive;
    double rangeEnd =
        _lastDistanceOnSegment! > endDistOnActive
            ? _lastDistanceOnSegment!
            : endDistOnActive;

    // Auto-fill the gap between last and current position
    _addRange(
      _activeSegmentIndex!,
      rangeStart.clamp(0, length),
      rangeEnd.clamp(0, length),
    );

    _lastDistanceOnSegment = endDistOnActive;

    // Mark segment as drawn if it's significantly filled
    if (_getSegmentFilledRatio(_activeSegmentIndex!) > 0.2) {
      _drawnSegments.add(_activeSegmentIndex!);
    }
  }

  /// Check if we're at an endpoint and should transition to a connected segment
  void _checkAndTransitionAtEndpoint(Offset point, double screenDistance) {
    if (_activeSegmentIndex == null || _lastDistanceOnSegment == null) return;

    final activeMetric = pathSegments[_activeSegmentIndex!];
    final activeLength = activeMetric.length;

    // Check if we're AT an endpoint (relaxed for smooth transitions)
    bool nearStart = _lastDistanceOnSegment! < tolerance * 2.5;
    bool nearEnd = _lastDistanceOnSegment! > activeLength - tolerance * 2.5;

    if (!nearStart && !nearEnd) {
      // Not at an endpoint - don't transition
      return;
    }

    // Get the endpoint position
    Offset? endpointPos;
    if (nearEnd) {
      final tangent = activeMetric.getTangentForOffset(activeLength);
      endpointPos = tangent?.position;
    } else if (nearStart) {
      final tangent = activeMetric.getTangentForOffset(0);
      endpointPos = tangent?.position;
    }

    if (endpointPos == null) return;

    // Find ONE connected segment
    int? bestNewSegment;
    double? bestDistanceOnNewSegment;
    double bestMinDist = double.infinity;

    for (
      int segmentIndex = 0;
      segmentIndex < pathSegments.length;
      segmentIndex++
    ) {
      if (segmentIndex == _activeSegmentIndex) continue;

      // Skip already drawn segments
      if (_drawnSegments.contains(segmentIndex)) continue;

      final pathMetric = pathSegments[segmentIndex];
      final length = pathMetric.length;

      // Check if this segment connects to our endpoint
      final startTangent = pathMetric.getTangentForOffset(0);
      final endTangent = pathMetric.getTangentForOffset(length);

      bool connectsAtStart =
          startTangent != null &&
          (startTangent.position - endpointPos).distance < tolerance * 3.0;
      bool connectsAtEnd =
          endTangent != null &&
          (endTangent.position - endpointPos).distance < tolerance * 3.0;

      if (!connectsAtStart && !connectsAtEnd) continue;

      // Check if the current point is on this segment near the connection
      double? distOnSegment = _findClosestDistanceOnSegment(
        point,
        segmentIndex,
      );

      if (distOnSegment != null) {
        // Must be near the connection point (relaxed for smooth transitions)
        double expectedDist = connectsAtStart ? 0 : length;
        double distFromConnection = (distOnSegment - expectedDist).abs();

        if (distFromConnection < tolerance * 3.5) {
          final currentDist = _getDistanceFromPoint(
            point,
            segmentIndex,
            distOnSegment,
          );
          if (currentDist < bestMinDist) {
            bestMinDist = currentDist;
            bestNewSegment = segmentIndex;
            bestDistanceOnNewSegment = distOnSegment;
          }
        }
      }
    }

    // Transition if found
    if (bestNewSegment != null && bestDistanceOnNewSegment != null) {
      // Fill to end of current segment
      final length = pathSegments[_activeSegmentIndex!].length;
      if (nearEnd) {
        _addRange(_activeSegmentIndex!, _lastDistanceOnSegment!, length);
      } else if (nearStart) {
        _addRange(_activeSegmentIndex!, 0, _lastDistanceOnSegment!);
      }

      // Mark old segment as completed
      _drawnSegments.add(_activeSegmentIndex!);

      // Switch to new segment
      _activeSegmentIndex = bestNewSegment;
      _lastDistanceOnSegment = bestDistanceOnNewSegment;
      _drawingForward = null;

      // Auto-fill from touch point to nearest endpoint
      final newMetric = pathSegments[bestNewSegment];
      final newLength = newMetric.length;
      final startTangent = newMetric.getTangentForOffset(0);

      bool connectsAtStart =
          startTangent != null &&
          (startTangent.position - endpointPos).distance < tolerance * 3.0;

      double distToStart = bestDistanceOnNewSegment;
      double distToEnd = newLength - bestDistanceOnNewSegment;

      if (connectsAtStart) {
        if (distToStart <= distToEnd) {
          _addRange(bestNewSegment, 0, bestDistanceOnNewSegment);
        } else {
          _addRange(bestNewSegment, bestDistanceOnNewSegment, newLength);
        }
      } else {
        if (distToEnd <= distToStart) {
          _addRange(bestNewSegment, bestDistanceOnNewSegment, newLength);
        } else {
          _addRange(bestNewSegment, 0, bestDistanceOnNewSegment);
        }
      }
    }
  }

  /// Calculate what ratio of a segment has been filled
  double _getSegmentFilledRatio(int segmentIndex) {
    if (segmentIndex >= pathSegments.length ||
        segmentIndex >= drawnRanges.length) {
      return 0.0;
    }

    final segmentLength = pathSegments[segmentIndex].length;
    if (segmentLength == 0) return 0.0;

    double filledLength = 0;
    for (var range in drawnRanges[segmentIndex]) {
      filledLength += range[1] - range[0];
    }

    return filledLength / segmentLength;
  }

  /// Helper to get screen distance from a point to a specific position on a segment
  double _getDistanceFromPoint(
    Offset point,
    int segmentIndex,
    double distanceOnPath,
  ) {
    final pathMetric = pathSegments[segmentIndex];
    final tangent = pathMetric.getTangentForOffset(distanceOnPath);
    if (tangent == null) return double.infinity;
    return (point - tangent.position).distance;
  }

  /// Find the closest distance along a segment for a given point
  double? _findClosestDistanceOnSegment(Offset point, int segmentIndex) {
    final pathMetric = pathSegments[segmentIndex];
    final length = pathMetric.length;

    double? closestDistance;
    double minDist = double.infinity;

    // Use consistent fine sampling (0.5 steps) for accurate distance finding
    // This prevents stuttering and ensures smooth movement
    for (double distance = 0; distance <= length; distance += 0.5) {
      final ui.Tangent? tangent = pathMetric.getTangentForOffset(distance);
      if (tangent != null) {
        final double currentDist = (point - tangent.position).distance;
        if (currentDist <= tolerance * 1.3 && currentDist < minDist) {
          minDist = currentDist;
          closestDistance = distance;
        }
      }
    }

    return closestDistance;
  }

  /// Update progress based on drawn ranges (continuous line tracking)
  void _updateProgress() {
    if (totalPathLength == 0) return;

    double drawnLength = 0;
    double actualTotalLength = 0;

    // Calculate both drawn length and actual total length from path segments
    // This handles cases where SVGs have overlapping paths
    for (
      int segmentIndex = 0;
      segmentIndex < pathSegments.length;
      segmentIndex++
    ) {
      final segmentLength = pathSegments[segmentIndex].length;
      actualTotalLength += segmentLength;

      // Sum up all drawn ranges for this segment
      for (var range in drawnRanges[segmentIndex]) {
        drawnLength += range[1] - range[0];
      }
    }

    // Use actualTotalLength if it differs from totalPathLength
    // This happens when the SVG has multiple overlapping paths
    final targetLength =
        actualTotalLength > 0 ? actualTotalLength : totalPathLength;
    progress = (drawnLength / targetLength).clamp(0.0, 1.0);
  }

  /// Complete the level successfully
  void _completeLevel() {
    isGameCompleted = true;
    isDrawing = false;
    progress = 1.0;
    errorMessage = null;
    onLevelComplete?.call();
  }

  /// Stop drawing with error message
  void _stopDrawingWithError(String message) {
    isDrawing = false;
    errorMessage = message;

    // Auto-reset after showing error briefly
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (errorMessage == message) {
        // Only reset if error hasn't changed
        reset();
      }
    });

    notifyListeners();
  }

  /// Get completion percentage as integer
  int get completionPercentage => (progress * 100).round();

  /// Check if game has error
  bool get hasError => errorMessage != null;

  /// Get drawn ranges for painter (for visual rendering)
  List<List<List<double>>> get getDrawnRanges => drawnRanges;
}
