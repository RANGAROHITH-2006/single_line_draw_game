import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xml/xml.dart';
import 'package:path_drawing/path_drawing.dart';
import 'dart:ui' as ui;

/// SVG Path Parser
/// Handles loading SVG files and converting path data to Flutter Path objects
/// Also manages scaling and transformation for proper display on screen
class SvgPathParser {
  /// Load and parse SVG file from assets
  static Future<SvgPathData> loadSvgPath(String assetPath) async {
    try {
      // Load the SVG file as string
      final svgString = await rootBundle.loadString(assetPath);
      
      // Parse the XML
      final document = XmlDocument.parse(svgString);
      
      // Get viewBox dimensions from SVG element
      final svgElement = document.findAllElements('svg').first;
      double svgViewBoxWidth = 100;
      double svgViewBoxHeight = 100;
      
      final viewBox = svgElement.getAttribute('viewBox');
      if (viewBox != null) {
        final parts = viewBox.split(' ');
        if (parts.length >= 4) {
          svgViewBoxWidth = double.parse(parts[2]);
          svgViewBoxHeight = double.parse(parts[3]);
        }
      }
      
      // Find all path elements and combine them
      final pathElements = document.findAllElements('path');
      Path combinedPath = Path();
      
      for (var pathElement in pathElements) {
        final pathData = pathElement.getAttribute('d');
        if (pathData != null) {
          // Parse the SVG path data into a Flutter Path
          final parsedPath = parseSvgPathData(pathData);
          combinedPath.addPath(parsedPath, Offset.zero);
        }
      }
      
      return SvgPathData(
        path: combinedPath,
        viewBoxWidth: svgViewBoxWidth,
        viewBoxHeight: svgViewBoxHeight,
      );
    } catch (e) {
      throw Exception('Error loading SVG path from $assetPath: $e');
    }
  }
  
  /// Transform and scale path to fit within container dimensions
  static Path transformPath(
    Path originalPath,
    double viewBoxWidth,
    double viewBoxHeight,
    double containerWidth,
    double containerHeight,
  ) {
    // Calculate scale to fit properly while maintaining aspect ratio
    double scaleX = containerWidth / viewBoxWidth;
    double scaleY = containerHeight / viewBoxHeight;
    double scale = scaleX < scaleY ? scaleX : scaleY;
    
    // Center the path in the container
    double scaledSvgWidth = viewBoxWidth * scale;
    double scaledSvgHeight = viewBoxHeight * scale;
    Offset offset = Offset(
      (containerWidth - scaledSvgWidth) / 2,
      (containerHeight - scaledSvgHeight) / 2,
    );
    
    // Create a matrix for scaling and translation
    final matrix = Matrix4.identity()
      ..translate(offset.dx, offset.dy)
      ..scale(scale, scale);
    
    // Apply transformation to the path
    return originalPath.transform(matrix.storage);
  }
  
  /// Get total length of all path segments
  static double getPathLength(Path path) {
    final pathMetrics = path.computeMetrics();
    double totalLength = 0;
    for (var metric in pathMetrics) {
      totalLength += metric.length;
    }
    return totalLength;
  }
  
  /// Get all path segments with their metrics
  static List<ui.PathMetric> getPathSegments(Path path) {
    return path.computeMetrics().toList();
  }
}

/// Data class to hold SVG path information
class SvgPathData {
  final Path path;
  final double viewBoxWidth;
  final double viewBoxHeight;
  
  const SvgPathData({
    required this.path,
    required this.viewBoxWidth,
    required this.viewBoxHeight,
  });
}