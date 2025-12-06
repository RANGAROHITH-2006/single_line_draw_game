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
  double tolerance = 16.0; // Hit detection tolerance in pixels

  // Continuous range-based tracking (instead of discrete dots)
  // Each segment has a list of drawn ranges [start, end] along its length
  List<List<List<double>>> drawnRanges =
      []; // [segmentIndex][rangeIndex][start, end]

  // Track the currently active segment index to prevent filling multiple edges at vertices
  int? _activeSegmentIndex;
  double? _lastDistanceOnSegment;
  
  // Track initial touch point to determine movement direction
  Offset? _initialTouchPoint;
  bool _directionDetermined = false;
  
  // Track if we're actively drawing a segment to completion (prevents switching mid-line)
  bool _isDrawingSegmentToCompletion = false;
  double? _targetVertexDistance; // The vertex we're drawing towards (0 or length)

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
    vertexSegments = SvgPathParser.extractSegmentsWithVertices(transformedPath, vertices);
    
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
          
          vertexSegments.add(PathSegmentInfo(
            pathMetricIndex: i,
            startVertex: startTangent.position,
            endVertex: endTangent.position,
            startDistance: sampleDistances[j],
            endDistance: sampleDistances[j + 1],
            startVertexIndex: transformedVertices.length - 2,
            endVertexIndex: transformedVertices.length - 1,
          ));
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

    // Check if starting position is on or near the path
    if (_isPointOnPath(localPosition)) {
      isDrawing = true;
      userPath.clear();
      userPath.add(localPosition);
      // Reset ranges for all segments
      drawnRanges = List.generate(pathSegments.length, (_) => []);
      // Reset active segment tracking
      _activeSegmentIndex = null;
      _lastDistanceOnSegment = null;
      _initialTouchPoint = localPosition;
      _directionDetermined = false;
      _isDrawingSegmentToCompletion = false;
      _targetVertexDistance = null;
      progress = 0.0;
      errorMessage = null;

      // Don't mark any segment yet - wait for movement direction
      // This prevents filling multiple lines at multi-vertex connections

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

      // If direction not yet determined, determine it now based on movement
      if (!_directionDetermined && _initialTouchPoint != null && userPath.length > 1) {
        final movementVector = localPosition - _initialTouchPoint!;
        final movementDistance = movementVector.distance;
        
        // Require clear directional movement before activating (prevent accidental activation at vertices)
        if (movementDistance > tolerance * 1.0) {
          _determineAndActivateSegmentByDirection(_initialTouchPoint!, localPosition, movementVector);
          _directionDetermined = true;
        }
      }

      // Fill in segments between last and current position
      if (userPath.length > 1 && _directionDetermined) {
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
    _initialTouchPoint = null;
    _directionDetermined = false;
    _isDrawingSegmentToCompletion = false;
    _targetVertexDistance = null;
    onGameReset?.call();
    notifyListeners();
  }

  /// Check if a point is on or near the SVG path
  bool _isPointOnPath(Offset point) {
    if (svgPath == null) return false;

    for (ui.PathMetric pathMetric in pathSegments) {
      final length = pathMetric.length;

      // Check points along the path with smaller steps for better accuracy
      for (double distance = 0; distance <= length; distance += 0.5) {
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

  /// Determine which segment to activate based on movement direction at a vertex
  /// This prevents filling multiple lines when starting from a multi-connection vertex
  void _determineAndActivateSegmentByDirection(Offset startPoint, Offset currentPoint, Offset movementVector) {
    // Find all segments that contain or are near the start point
    List<_SegmentCandidate> candidates = [];
    
    for (int segmentIndex = 0; segmentIndex < pathSegments.length; segmentIndex++) {
      final pathMetric = pathSegments[segmentIndex];
      final length = pathMetric.length;
      
      // Check if start point is near the beginning or end of this segment
      final startTangent = pathMetric.getTangentForOffset(0);
      final endTangent = pathMetric.getTangentForOffset(length);
      
      double? distanceOnSegment;
      bool isAtStart = false;
      bool isAtEnd = false;
      
      if (startTangent != null) {
        final distToStart = (startPoint - startTangent.position).distance;
        if (distToStart <= tolerance * 0.8) {
          distanceOnSegment = 0;
          isAtStart = true;
        }
      }
      
      if (endTangent != null && distanceOnSegment == null) {
        final distToEnd = (startPoint - endTangent.position).distance;
        if (distToEnd <= tolerance * 0.8) {
          distanceOnSegment = length;
          isAtEnd = true;
        }
      }
      
      // If not at start or end, check if somewhere along the segment
      if (distanceOnSegment == null) {
        distanceOnSegment = _findClosestDistanceOnSegment(startPoint, segmentIndex);
      }
      
      if (distanceOnSegment != null) {
        // Calculate the direction of this segment from the start point
        Offset segmentDirection;
        
        if (isAtStart) {
          // Direction from start towards the segment (use larger lookahead for clearer direction)
          final nextTangent = pathMetric.getTangentForOffset((tolerance * 2).clamp(0, length));
          if (nextTangent != null) {
            segmentDirection = nextTangent.position - startTangent!.position;
          } else {
            continue;
          }
        } else if (isAtEnd) {
          // Direction from end back towards the segment (use larger lookback for clearer direction)
          final prevTangent = pathMetric.getTangentForOffset((length - tolerance * 2).clamp(0, length));
          if (prevTangent != null) {
            segmentDirection = endTangent!.position - prevTangent.position;
          } else {
            continue;
          }
        } else {
          // Direction along the segment at this point
          final tangent = pathMetric.getTangentForOffset(distanceOnSegment);
          if (tangent != null && tangent.vector.distance > 0) {
            segmentDirection = tangent.vector;
          } else {
            continue;
          }
        }
        
        // Normalize directions
        if (segmentDirection.distance > 0) {
          segmentDirection = segmentDirection / segmentDirection.distance;
        } else {
          continue;
        }
        
        Offset normalizedMovement = movementVector.distance > 0 
            ? movementVector / movementVector.distance 
            : Offset.zero;
        
        // Calculate dot product to measure alignment
        // Dot product ranges from -1 (opposite) to 1 (same direction)
        double dotProduct = segmentDirection.dx * normalizedMovement.dx + 
                           segmentDirection.dy * normalizedMovement.dy;
        
        // Also try opposite direction (for segments that go the other way)
        double dotProductReverse = -dotProduct;
        double bestDot = dotProduct.abs() > dotProductReverse.abs() ? dotProduct : dotProductReverse;
        
        candidates.add(_SegmentCandidate(
          segmentIndex: segmentIndex,
          distanceOnSegment: distanceOnSegment,
          directionAlignment: bestDot,
          isAtVertex: isAtStart || isAtEnd,
          vertexEnd: isAtStart ? 0 : (isAtEnd ? length : distanceOnSegment),
        ));
      }
    }
    
    // Select the segment that best aligns with the movement direction
    if (candidates.isNotEmpty) {
      // Filter out segments with poor alignment (less than 0.5) - be strict to avoid multi-segment activation
      final filteredCandidates = candidates.where((c) => c.directionAlignment > 0.5).toList();
      
      // Use filtered list if not empty, otherwise use all candidates
      final finalCandidates = filteredCandidates.isNotEmpty ? filteredCandidates : candidates;
      
      // Sort by direction alignment (highest first)
      finalCandidates.sort((a, b) => b.directionAlignment.compareTo(a.directionAlignment));
      
      final best = finalCandidates.first;
      _activeSegmentIndex = best.segmentIndex;
      _lastDistanceOnSegment = best.distanceOnSegment;
      _isDrawingSegmentToCompletion = true;
      
      final pathMetric = pathSegments[best.segmentIndex];
      final length = pathMetric.length;
      
      // If starting at a vertex, set up for drawing but don't fill yet
      if (best.isAtVertex) {
        // Determine which vertex we started from and set target to opposite end
        double startVertex = best.vertexEnd < 0.5 ? 0.0 : length;
        _targetVertexDistance = startVertex < 0.5 ? length : 0.0;
        _lastDistanceOnSegment = startVertex;
        
        // Don't add any range yet - wait for actual movement to prevent auto-fill
      } else {
        // Starting mid-segment, fill from nearest vertex
        _markSegmentAsDrawnAndSetActiveFromVertex(startPoint);
        // Target is the opposite end from where we started
        if (_lastDistanceOnSegment != null) {
          _targetVertexDistance = _lastDistanceOnSegment! < length / 2 ? length : 0.0;
        }
      }
    }
  }
  
  /// Mark a point on the path as drawn and set the active segment
  /// When starting from middle of a segment, fills from the nearest vertex ON THE SAME PATH
  void _markSegmentAsDrawnAndSetActiveFromVertex(Offset point) {
    // Find the closest point on the path
    int? bestSegmentIndex;
    double? bestDistance;
    double bestMinDist = double.infinity;

    for (int segmentIndex = 0; segmentIndex < pathSegments.length; segmentIndex++) {
      final pathMetric = pathSegments[segmentIndex];
      final length = pathMetric.length;

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

    // Find the nearest vertex ON THIS SAME PATH SEGMENT only
    // This ensures we don't fill towards vertices on other paths
    double nearestVertexPathDist = 0;
    double nearestVertexScreenDist = double.infinity;

    // Always consider start of this path segment as a vertex
    final startTangent = pathMetric.getTangentForOffset(0);
    if (startTangent != null) {
      final distToStart = (point - startTangent.position).distance;
      if (distToStart < nearestVertexScreenDist) {
        nearestVertexScreenDist = distToStart;
        nearestVertexPathDist = 0;
      }
    }

    // Always consider end of this path segment as a vertex
    final endTangent = pathMetric.getTangentForOffset(length);
    if (endTangent != null) {
      final distToEnd = (point - endTangent.position).distance;
      if (distToEnd < nearestVertexScreenDist) {
        nearestVertexScreenDist = distToEnd;
        nearestVertexPathDist = length;
      }
    }

    // Check intermediate vertices ONLY if they are on THIS path segment
    // Use a strict tolerance to ensure vertex is actually on this path
    for (final vertex in transformedVertices) {
      final vertexDistOnPath = _findClosestDistanceOnSegmentStrict(vertex, bestSegmentIndex, 8.0);
      if (vertexDistOnPath != null) {
        final distToVertex = (point - vertex).distance;
        if (distToVertex < nearestVertexScreenDist) {
          nearestVertexScreenDist = distToVertex;
          nearestVertexPathDist = vertexDistOnPath;
        }
      }
    }

    // Fill from nearest vertex (on same path) to touch point
    // Use exact vertex position to avoid gaps
    double exactVertexPos = nearestVertexPathDist;
    if (nearestVertexPathDist < tolerance) {
      exactVertexPos = 0.0; // Snap to start
    } else if (nearestVertexPathDist > length - tolerance) {
      exactVertexPos = length; // Snap to end
    }
    
    double rangeStart = bestDistance < exactVertexPos ? bestDistance : exactVertexPos;
    double rangeEnd = bestDistance > exactVertexPos ? bestDistance : exactVertexPos;
    
    // Don't extend range - use exact positions to prevent gaps
    rangeStart = rangeStart.clamp(0.0, length);
    rangeEnd = rangeEnd.clamp(0.0, length);
    
    _addRange(bestSegmentIndex, rangeStart, rangeEnd);
  }
  
  /// Find distance on segment with strict tolerance (for vertex matching on same path)
  double? _findClosestDistanceOnSegmentStrict(Offset point, int segmentIndex, double strictTolerance) {
    final pathMetric = pathSegments[segmentIndex];
    final length = pathMetric.length;

    double? closestDistance;
    double minDist = double.infinity;

    for (double distance = 0; distance <= length; distance += 0.5) {
      final ui.Tangent? tangent = pathMetric.getTangentForOffset(distance);
      if (tangent != null) {
        final double currentDist = (point - tangent.position).distance;
        if (currentDist <= strictTolerance && currentDist < minDist) {
          minDist = currentDist;
          closestDistance = distance;
        }
      }
    }

    return closestDistance;
  }

  /// Add a range to a segment, merging with existing overlapping ranges
  void _addRange(int segmentIndex, double start, double end) {
    if (segmentIndex >= drawnRanges.length) return;

    List<List<double>> ranges = drawnRanges[segmentIndex];

    // Find overlapping or adjacent ranges and merge
    List<List<double>> newRanges = [];

    for (var range in ranges) {
      // Check if ranges overlap or are adjacent (within 0.5 pixels)
      if (start <= range[1] + 0.5 && end >= range[0] - 0.5) {
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
      if (finalRanges.isEmpty || finalRanges.last[1] < range[0] - 0.5) {
        finalRanges.add(range);
      } else {
        finalRanges.last[1] =
            finalRanges.last[1] > range[1] ? finalRanges.last[1] : range[1];
      }
    }

    drawnRanges[segmentIndex] = finalRanges;
  }

  /// Fill path between two points, staying on the active segment or transitioning to a new one
  /// This prevents filling multiple edges at vertices
  void _fillPathBetweenOnActiveSegment(Offset startPoint, Offset endPoint) {
    // Calculate the screen distance between the two touch points
    double screenDistance = (endPoint - startPoint).distance;

    // If points are too far apart on screen, don't fill (user may have lifted finger)
    if (screenDistance > tolerance * 3) {
      return;
    }

    // STRICT MODE: Once a segment is active, user MUST complete it to a vertex before switching
    if (_activeSegmentIndex != null) {
      // Check if current point is on the active segment (use lenient tolerance)
      double? endDistOnActive = _findClosestDistanceOnSegmentLenient(endPoint, _activeSegmentIndex!);
      
      if (endDistOnActive == null) {
        // User went off the active segment
        // Check completion percentage
        double completionPercentage = _getActiveSegmentCompletionPercentage();
        
        if (completionPercentage < 0.80) {
          // Less than 80% complete - don't allow switching
          _stopDrawingWithError("Complete at least 80% of the current line first!");
          return;
        }
        
        // >= 80% complete - auto-complete the remaining part
        _autoCompleteActiveSegmentToVertex();
        
        // Reset for next line
        _activeSegmentIndex = null;
        _lastDistanceOnSegment = null;
        _directionDetermined = false;
        _initialTouchPoint = endPoint;
        return;
      }

      // User is still on the active segment - continue drawing
      if (_lastDistanceOnSegment != null) {
        // Fill from last to current position on this segment
        final length = pathSegments[_activeSegmentIndex!].length;
        double rangeStart =
            (_lastDistanceOnSegment! < endDistOnActive
                ? _lastDistanceOnSegment!
                : endDistOnActive);
        double rangeEnd =
            (_lastDistanceOnSegment! > endDistOnActive
                ? _lastDistanceOnSegment!
                : endDistOnActive);
        _addRange(
          _activeSegmentIndex!,
          rangeStart.clamp(0, length),
          rangeEnd.clamp(0, length),
        );
        _lastDistanceOnSegment = endDistOnActive;
        
        // Check if we've reached near a vertex - auto-complete the line
        bool nearStart = endDistOnActive < tolerance * 2;
        bool nearEnd = endDistOnActive > length - tolerance * 2;
        
        if (nearStart || nearEnd) {
          // Auto-complete to the exact vertex
          if (nearStart) {
            _addRange(_activeSegmentIndex!, 0.0, endDistOnActive);
            _lastDistanceOnSegment = 0.0;
          } else if (nearEnd) {
            _addRange(_activeSegmentIndex!, endDistOnActive, length);
            _lastDistanceOnSegment = length;
          }
          
          // Mark segment as complete and reset so user must start next line explicitly
          _activeSegmentIndex = null;
          _lastDistanceOnSegment = null;
          _directionDetermined = false;
          _initialTouchPoint = endPoint;
        }
        
        return;
      }
    }
    
    // If no active segment, do nothing (direction determination will set it)
  }

  /// Find the closest distance along a segment for a given point
  double? _findClosestDistanceOnSegment(Offset point, int segmentIndex) {
    final pathMetric = pathSegments[segmentIndex];
    final length = pathMetric.length;

    double? closestDistance;
    double minDist = double.infinity;

    for (double distance = 0; distance <= length; distance += 0.5) {
      final ui.Tangent? tangent = pathMetric.getTangentForOffset(distance);
      if (tangent != null) {
        final double currentDist = (point - tangent.position).distance;
        if (currentDist <= tolerance && currentDist < minDist) {
          minDist = currentDist;
          closestDistance = distance;
        }
      }
    }

    return closestDistance;
  }

  /// Find the closest distance along a segment with lenient tolerance (for active segment)
  /// Uses 2x tolerance to ensure continuous filling even if finger is slightly off
  double? _findClosestDistanceOnSegmentLenient(Offset point, int segmentIndex) {
    final pathMetric = pathSegments[segmentIndex];
    final length = pathMetric.length;

    double? closestDistance;
    double minDist = double.infinity;

    for (double distance = 0; distance <= length; distance += 0.5) {
      final ui.Tangent? tangent = pathMetric.getTangentForOffset(distance);
      if (tangent != null) {
        final double currentDist = (point - tangent.position).distance;
        if (currentDist <= tolerance * 2 && currentDist < minDist) {
          minDist = currentDist;
          closestDistance = distance;
        }
      }
    }

    return closestDistance;
  }

  /// Check if the active segment is fully drawn to at least one vertex
  bool _isActiveSegmentCompleteToVertex() {
    if (_activeSegmentIndex == null || drawnRanges.isEmpty) return false;
    
    final ranges = drawnRanges[_activeSegmentIndex!];
    if (ranges.isEmpty) return false;
    
    final length = pathSegments[_activeSegmentIndex!].length;
    
    // Check if any range reaches either vertex (0 or length)
    for (var range in ranges) {
      bool reachesStart = range[0] <= 1.0;
      bool reachesEnd = range[1] >= length - 1.0;
      
      if (reachesStart || reachesEnd) {
        return true;
      }
    }
    
    return false;
  }
  
  /// Get the completion percentage of the active segment (0.0 to 1.0)
  double _getActiveSegmentCompletionPercentage() {
    if (_activeSegmentIndex == null || _activeSegmentIndex! >= drawnRanges.length) return 0.0;
    
    final ranges = drawnRanges[_activeSegmentIndex!];
    if (ranges.isEmpty) return 0.0;
    
    final length = pathSegments[_activeSegmentIndex!].length;
    if (length == 0) return 0.0;
    
    // Sum up all drawn ranges for this segment
    double drawnLength = 0.0;
    for (var range in ranges) {
      drawnLength += range[1] - range[0];
    }
    
    return (drawnLength / length).clamp(0.0, 1.0);
  }
  
  /// Auto-complete the remaining part of active segment to nearest vertex
  void _autoCompleteActiveSegmentToVertex() {
    if (_activeSegmentIndex == null || _lastDistanceOnSegment == null) return;
    
    final length = pathSegments[_activeSegmentIndex!].length;
    final currentPos = _lastDistanceOnSegment!;
    
    // Determine which vertex is closer
    bool closerToStart = currentPos < length / 2;
    
    if (closerToStart) {
      // Complete to start (0)
      _addRange(_activeSegmentIndex!, 0.0, currentPos);
    } else {
      // Complete to end (length)
      _addRange(_activeSegmentIndex!, currentPos, length);
    }
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
    final targetLength = actualTotalLength > 0 ? actualTotalLength : totalPathLength;
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

/// Helper class to store segment candidate information
class _SegmentCandidate {
  final int segmentIndex;
  final double distanceOnSegment;
  final double directionAlignment; // Dot product: -1 to 1
  final bool isAtVertex;
  final double vertexEnd;
  
  _SegmentCandidate({
    required this.segmentIndex,
    required this.distanceOnSegment,
    required this.directionAlignment,
    required this.isAtVertex,
    required this.vertexEnd,
  });
}
