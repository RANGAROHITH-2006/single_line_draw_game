import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'dart:math' as math;

/// Represents a vertex in the path graph
/// A vertex can be shared by multiple edges
class PathVertex {
  final int id;
  final Offset position;
  final List<int> connectedEdgeIds; // List of edge IDs connected to this vertex
  
  PathVertex({
    required this.id,
    required this.position,
    List<int>? connectedEdgeIds,
  }) : connectedEdgeIds = connectedEdgeIds ?? [];
  
  /// Check if two vertices are at the same position (within tolerance)
  bool isSamePosition(Offset other, double tolerance) {
    return (position - other).distance < tolerance;
  }
}

/// Represents an edge (line segment or curve) between two vertices
class PathEdge {
  final int id;
  final int startVertexId;
  final int endVertexId;
  final int pathMetricIndex; // Which path metric this edge belongs to
  final double startDistance; // Distance on path metric where edge starts
  final double endDistance; // Distance on path metric where edge ends
  final bool isCurve; // True if this edge is a curve, false if straight line
  
  /// Track which portions of this edge have been drawn
  /// Each range is [start, end] as a percentage (0.0 to 1.0) of the edge length
  final List<List<double>> drawnRanges;
  
  PathEdge({
    required this.id,
    required this.startVertexId,
    required this.endVertexId,
    required this.pathMetricIndex,
    required this.startDistance,
    required this.endDistance,
    this.isCurve = false,
  }) : drawnRanges = [];
  
  double get length => endDistance - startDistance;
  
  /// Calculate what percentage of this edge has been drawn
  double get completionPercentage {
    if (drawnRanges.isEmpty) return 0.0;
    
    double totalDrawn = 0.0;
    for (var range in drawnRanges) {
      totalDrawn += (range[1] - range[0]);
    }
    
    return (totalDrawn).clamp(0.0, 1.0);
  }
  
  /// Check if this edge is fully drawn (>95% for tolerance)
  bool get isComplete => completionPercentage > 0.95;
  
  /// Add a drawn range to this edge and merge overlapping ranges
  void addDrawnRange(double start, double end) {
    if (start >= end) return;
    
    drawnRanges.add([start.clamp(0.0, 1.0), end.clamp(0.0, 1.0)]);
    _mergeOverlappingRanges();
  }
  
  /// Merge overlapping ranges to avoid counting the same section multiple times
  void _mergeOverlappingRanges() {
    if (drawnRanges.length <= 1) return;
    
    // Sort ranges by start position
    drawnRanges.sort((a, b) => a[0].compareTo(b[0]));
    
    List<List<double>> merged = [drawnRanges[0]];
    
    for (int i = 1; i < drawnRanges.length; i++) {
      final current = drawnRanges[i];
      final last = merged.last;
      
      // If current range overlaps or is adjacent to last merged range
      if (current[0] <= last[1]) {
        // Extend the last range
        last[1] = math.max(last[1], current[1]);
      } else {
        // Add as new range
        merged.add([current[0], current[1]]);
      }
    }
    
    drawnRanges.clear();
    drawnRanges.addAll(merged);
  }
  
  /// Clear all drawn ranges
  void reset() {
    drawnRanges.clear();
  }
}

/// Path graph representing the entire drawable path as vertices and edges
/// This structure treats the path as a graph where vertices can be shared between multiple edges
class PathGraph {
  final List<PathVertex> vertices;
  final List<PathEdge> edges;
  final List<ui.PathMetric> pathMetrics;
  
  PathGraph({
    required this.vertices,
    required this.edges,
    required this.pathMetrics,
  });
  
  /// Build a path graph from transformed vertices and path
  static PathGraph buildFromVertices(
    Path transformedPath,
    List<Offset> transformedVertices,
    {double vertexMergeThreshold = 15.0}
  ) {
    final pathMetrics = transformedPath.computeMetrics().toList();
    
    if (pathMetrics.isEmpty) {
      return PathGraph(vertices: [], edges: [], pathMetrics: []);
    }
    
    List<PathVertex> vertices = [];
    List<PathEdge> edges = [];
    int vertexIdCounter = 0;
    int edgeIdCounter = 0;
    
    // Create vertices from transformed vertices, merging duplicates
    Map<int, int> originalToMergedIndex = {};
    
    for (int i = 0; i < transformedVertices.length; i++) {
      final position = transformedVertices[i];
      
      // Check if this position already exists in vertices (within threshold)
      int? existingVertexId;
      for (var vertex in vertices) {
        if (vertex.isSamePosition(position, vertexMergeThreshold)) {
          existingVertexId = vertex.id;
          break;
        }
      }
      
      if (existingVertexId != null) {
        // Reuse existing vertex
        originalToMergedIndex[i] = existingVertexId;
      } else {
        // Create new vertex
        final newVertex = PathVertex(
          id: vertexIdCounter++,
          position: position,
        );
        vertices.add(newVertex);
        originalToMergedIndex[i] = newVertex.id;
      }
    }
    
    // Build edges by connecting consecutive vertices on each path metric
    for (int metricIndex = 0; metricIndex < pathMetrics.length; metricIndex++) {
      final metric = pathMetrics[metricIndex];
      
      // Find vertices on this path metric
      List<_VertexWithDistance> verticesOnPath = [];
      
      for (int i = 0; i < transformedVertices.length; i++) {
        final vertex = transformedVertices[i];
        final distance = _findDistanceOnPath(metric, vertex, 20.0);
        
        if (distance != null) {
          final vertexId = originalToMergedIndex[i]!;
          verticesOnPath.add(_VertexWithDistance(
            vertexId: vertexId,
            position: vertex,
            distance: distance,
          ));
        }
      }
      
      // Sort by distance along path
      verticesOnPath.sort((a, b) => a.distance.compareTo(b.distance));
      
      // Remove duplicate vertex IDs (can happen if merged vertices are on same path)
      final uniqueVertices = <int, _VertexWithDistance>{};
      for (var vd in verticesOnPath) {
        if (!uniqueVertices.containsKey(vd.vertexId)) {
          uniqueVertices[vd.vertexId] = vd;
        }
      }
      verticesOnPath = uniqueVertices.values.toList();
      verticesOnPath.sort((a, b) => a.distance.compareTo(b.distance));
      
      // If no vertices on this metric, create synthetic vertices at start and end
      if (verticesOnPath.isEmpty) {
        final startTangent = metric.getTangentForOffset(0);
        final endTangent = metric.getTangentForOffset(metric.length);
        
        if (startTangent != null && endTangent != null) {
          // Create synthetic start vertex
          final startVertex = PathVertex(
            id: vertexIdCounter++,
            position: startTangent.position,
          );
          vertices.add(startVertex);
          
          // Create synthetic end vertex
          final endVertex = PathVertex(
            id: vertexIdCounter++,
            position: endTangent.position,
          );
          vertices.add(endVertex);
          
          // Create edge between them
          final edge = PathEdge(
            id: edgeIdCounter++,
            startVertexId: startVertex.id,
            endVertexId: endVertex.id,
            pathMetricIndex: metricIndex,
            startDistance: 0,
            endDistance: metric.length,
            isCurve: metric.length > 50, // Heuristic: long segments are likely curves
          );
          edges.add(edge);
          
          startVertex.connectedEdgeIds.add(edge.id);
          endVertex.connectedEdgeIds.add(edge.id);
        }
        continue;
      }
      
      // Create edges between consecutive vertices on this path metric
      for (int i = 0; i < verticesOnPath.length - 1; i++) {
        final startVD = verticesOnPath[i];
        final endVD = verticesOnPath[i + 1];
        
        final edge = PathEdge(
          id: edgeIdCounter++,
          startVertexId: startVD.vertexId,
          endVertexId: endVD.vertexId,
          pathMetricIndex: metricIndex,
          startDistance: startVD.distance,
          endDistance: endVD.distance,
          isCurve: _isPathCurved(metric, startVD.distance, endVD.distance),
        );
        edges.add(edge);
        
        // Update vertex connections
        vertices.firstWhere((v) => v.id == startVD.vertexId).connectedEdgeIds.add(edge.id);
        vertices.firstWhere((v) => v.id == endVD.vertexId).connectedEdgeIds.add(edge.id);
      }
    }
    
    return PathGraph(
      vertices: vertices,
      edges: edges,
      pathMetrics: pathMetrics,
    );
  }
  
  /// Get vertex by ID
  PathVertex? getVertex(int id) {
    try {
      return vertices.firstWhere((v) => v.id == id);
    } catch (e) {
      return null;
    }
  }
  
  /// Get edge by ID
  PathEdge? getEdge(int id) {
    try {
      return edges.firstWhere((e) => e.id == id);
    } catch (e) {
      return null;
    }
  }
  
  /// Get all edges connected to a vertex
  List<PathEdge> getEdgesForVertex(int vertexId) {
    final vertex = getVertex(vertexId);
    if (vertex == null) return [];
    
    return vertex.connectedEdgeIds
        .map((edgeId) => getEdge(edgeId))
        .whereType<PathEdge>()
        .toList();
  }
  
  /// Find the nearest edge to a given point
  PathEdge? findNearestEdge(Offset point, {double maxDistance = 20.0}) {
    PathEdge? nearestEdge;
    double minDistance = maxDistance;
    
    for (var edge in edges) {
      final startVertex = getVertex(edge.startVertexId);
      final endVertex = getVertex(edge.endVertexId);
      
      if (startVertex == null || endVertex == null) continue;
      
      final distance = _perpendicularDistance(
        point,
        startVertex.position,
        endVertex.position,
      );
      
      if (distance < minDistance) {
        minDistance = distance;
        nearestEdge = edge;
      }
    }
    
    return nearestEdge;
  }
  
  /// Calculate total completion percentage
  double get completionPercentage {
    if (edges.isEmpty) return 0.0;
    
    double totalLength = 0.0;
    double totalDrawn = 0.0;
    
    for (var edge in edges) {
      totalLength += edge.length;
      totalDrawn += edge.length * edge.completionPercentage;
    }
    
    return totalLength > 0 ? totalDrawn / totalLength : 0.0;
  }
  
  /// Check if all edges are complete
  bool get isComplete => completionPercentage > 0.95;
  
  /// Reset all edge progress
  void reset() {
    for (var edge in edges) {
      edge.reset();
    }
  }
  
  /// Find distance along path metric for a point
  static double? _findDistanceOnPath(ui.PathMetric metric, Offset point, double tolerance) {
    final length = metric.length;
    final step = math.min(5.0, length / 20);
    
    for (double dist = 0; dist <= length; dist += step) {
      final tangent = metric.getTangentForOffset(dist);
      if (tangent != null) {
        if ((tangent.position - point).distance < tolerance) {
          return dist;
        }
      }
    }
    
    return null;
  }
  
  /// Check if a path segment is curved or straight
  static bool _isPathCurved(ui.PathMetric metric, double startDist, double endDist) {
    final numSamples = 5;
    final step = (endDist - startDist) / numSamples;
    
    List<Offset> samplePoints = [];
    for (int i = 0; i <= numSamples; i++) {
      final dist = startDist + (i * step);
      final tangent = metric.getTangentForOffset(dist);
      if (tangent != null) {
        samplePoints.add(tangent.position);
      }
    }
    
    if (samplePoints.length < 3) return false;
    
    // Check if points are roughly collinear
    final start = samplePoints.first;
    final end = samplePoints.last;
    double maxDeviation = 0.0;
    
    for (var point in samplePoints) {
      final deviation = _perpendicularDistance(point, start, end);
      maxDeviation = math.max(maxDeviation, deviation);
    }
    
    // If max deviation is > 3 pixels, consider it a curve
    return maxDeviation > 3.0;
  }
  
  /// Calculate perpendicular distance from point to line segment
  static double _perpendicularDistance(Offset point, Offset lineStart, Offset lineEnd) {
    final dx = lineEnd.dx - lineStart.dx;
    final dy = lineEnd.dy - lineStart.dy;
    
    final lengthSquared = dx * dx + dy * dy;
    
    if (lengthSquared == 0) {
      return (point - lineStart).distance;
    }
    
    final t = ((point.dx - lineStart.dx) * dx + (point.dy - lineStart.dy) * dy) / lengthSquared;
    
    final Offset closest;
    if (t < 0) {
      closest = lineStart;
    } else if (t > 1) {
      closest = lineEnd;
    } else {
      closest = Offset(
        lineStart.dx + t * dx,
        lineStart.dy + t * dy,
      );
    }
    
    return (point - closest).distance;
  }
}

/// Helper class for building path graph
class _VertexWithDistance {
  final int vertexId;
  final Offset position;
  final double distance;
  
  _VertexWithDistance({
    required this.vertexId,
    required this.position,
    required this.distance,
  });
}
