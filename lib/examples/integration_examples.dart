/**
 * Integration Guide: Using SvgJointDetector with Existing Game Code
 * 
 * This guide shows how to integrate the joint detector with your existing
 * singlelinedraw game without disturbing any current functionality.
 */

import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import '../svg_joint_detector.dart';

/// ==============================================================================
/// EXAMPLE 1: Add Joint Visualization to Existing Game
/// ==============================================================================

/// Modify your GamePainter to optionally show joints
class EnhancedGamePainter extends CustomPainter {
  final Path? svgPath;
  final List<Offset> userPath;
  final List<List<List<double>>> drawnRanges;
  final List<ui.PathMetric> pathSegments;
  final double progress;
  final bool isGameCompleted;
  final bool hasError;
  final List<Offset> vertices;
  final bool showVertices;
  
  // NEW: Add option to show detected joints
  final bool showDetectedJoints;
  final String? svgPathData; // Store original SVG path string
  
  EnhancedGamePainter({
    required this.svgPath,
    required this.userPath,
    required this.drawnRanges,
    required this.pathSegments,
    required this.progress,
    required this.isGameCompleted,
    required this.hasError,
    this.vertices = const [],
    this.showVertices = false,
    this.showDetectedJoints = false, // NEW
    this.svgPathData, // NEW
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    // ... existing game painter code ...
    
    // NEW: Optionally show detected joints
    if (showDetectedJoints && svgPathData != null) {
      final joints = SvgJointDetector.detectJoints(
        svgPathData!,
        includeControlPoints: false,
        duplicateTolerance: 2.0,
      );
      
      SvgJointDetector.renderJoints(
        canvas,
        joints,
        radius: 4.0,
        color: Colors.cyan,
        strokeWidth: 2.0,
      );
    }
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// ==============================================================================
/// EXAMPLE 2: Analyze Level Difficulty Based on Joints
/// ==============================================================================

class LevelComplexityAnalyzer {
  /// Analyzes a level's SVG path and returns complexity metrics
  static Map<String, dynamic> analyzeLevelComplexity(String svgPath) {
    final analysis = SvgJointDetector.analyzePathJoints(
      svgPath,
      includeControlPoints: false,
      duplicateTolerance: 1.0,
    );
    
    // Calculate complexity score
    double complexityScore = 0;
    
    // More joints = more complex
    complexityScore += analysis.joints.length * 10;
    
    // Longer path = more complex
    complexityScore += (analysis.totalLength / 100).round();
    
    // Sharp angle changes increase complexity
    int sharpAngles = 0;
    for (int i = 0; i < analysis.segments.length - 1; i++) {
      double angle1 = analysis.segments[i].angle;
      double angle2 = analysis.segments[i + 1].angle;
      double angleDiff = (angle1 - angle2).abs();
      
      if (angleDiff > 1.5) { // ~85 degrees
        sharpAngles++;
      }
    }
    complexityScore += sharpAngles * 15;
    
    return {
      'complexity_score': complexityScore,
      'joint_count': analysis.joints.length,
      'segment_count': analysis.segments.length,
      'path_length': analysis.totalLength,
      'sharp_angles': sharpAngles,
      'difficulty': complexityScore < 100 ? 'Easy' : 
                    complexityScore < 200 ? 'Medium' : 
                    complexityScore < 300 ? 'Hard' : 'Expert',
    };
  }
  
  /// Example usage with your levels data
  static void analyzeLevels() {
    final levels = [
      'assets/svg/Level1.svg',
      'assets/svg/Level2.svg',
      'assets/svg/Level3.svg',
      // ... more levels
    ];
    
    for (int i = 0; i < levels.length; i++) {
      // In practice, you'd load the SVG and extract the path data
      // For demonstration:
      String pathData = 'M 50 50 L 150 50 L 100 150 Z'; // Load from SVG
      
      var analysis = analyzeLevelComplexity(pathData);
      print('Level ${i + 1}: ${analysis['difficulty']} '
            '(Score: ${analysis['complexity_score']}, '
            'Joints: ${analysis['joint_count']})');
    }
  }
}

/// ==============================================================================
/// EXAMPLE 3: Generate Hint System Using Joints
/// ==============================================================================

class HintSystem {
  /// Generates hint markers at key joints for players
  static List<Offset> getHintPoints(
    String svgPathData, {
    int maxHints = 3,
  }) {
    final joints = SvgJointDetector.detectJoints(
      svgPathData,
      includeControlPoints: false,
      duplicateTolerance: 2.0,
    );
    
    // Return evenly spaced hints
    if (joints.length <= maxHints) {
      return joints;
    }
    
    List<Offset> hints = [];
    int step = joints.length ~/ maxHints;
    
    for (int i = 0; i < maxHints; i++) {
      hints.add(joints[i * step]);
    }
    
    return hints;
  }
  
  /// Render animated hint dots
  static void renderHints(
    Canvas canvas,
    List<Offset> hintPoints,
    double animationValue,
  ) {
    for (int i = 0; i < hintPoints.length; i++) {
      // Animate each hint with a delay
      double offset = (i / hintPoints.length) * 0.3;
      double scale = ((animationValue + offset) % 1.0);
      
      final paint = Paint()
        ..color = Colors.yellow.withOpacity(1.0 - scale)
        ..style = PaintingStyle.fill;
      
      canvas.drawCircle(
        hintPoints[i],
        5.0 + scale * 10.0,
        paint,
      );
    }
  }
}

/// ==============================================================================
/// EXAMPLE 4: Validate User's Path Against Expected Joints
/// ==============================================================================

class PathValidator {
  /// Check if user has traced through all important joints
  static bool validateUserPath(
    List<Offset> userPath,
    String expectedSvgPath,
    double tolerance,
  ) {
    final expectedJoints = SvgJointDetector.detectJoints(
      expectedSvgPath,
      includeControlPoints: false,
      duplicateTolerance: 2.0,
    );
    
    // Check if user path passes through each joint
    Set<int> visitedJoints = {};
    
    for (var userPoint in userPath) {
      for (int i = 0; i < expectedJoints.length; i++) {
        if ((userPoint - expectedJoints[i]).distance < tolerance) {
          visitedJoints.add(i);
        }
      }
    }
    
    // All joints must be visited
    return visitedJoints.length == expectedJoints.length;
  }
  
  /// Get completion percentage
  static double getCompletionPercentage(
    List<Offset> userPath,
    String expectedSvgPath,
    double tolerance,
  ) {
    final expectedJoints = SvgJointDetector.detectJoints(
      expectedSvgPath,
      includeControlPoints: false,
      duplicateTolerance: 2.0,
    );
    
    if (expectedJoints.isEmpty) return 0.0;
    
    Set<int> visitedJoints = {};
    
    for (var userPoint in userPath) {
      for (int i = 0; i < expectedJoints.length; i++) {
        if ((userPoint - expectedJoints[i]).distance < tolerance) {
          visitedJoints.add(i);
        }
      }
    }
    
    return visitedJoints.length / expectedJoints.length;
  }
}

/// ==============================================================================
/// EXAMPLE 5: Debug Overlay for Development
/// ==============================================================================

class DebugJointOverlay extends StatelessWidget {
  final String svgPathData;
  final bool enabled;
  
  const DebugJointOverlay({
    Key? key,
    required this.svgPathData,
    this.enabled = false,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    if (!enabled) return const SizedBox.shrink();
    
    return Positioned.fill(
      child: CustomPaint(
        painter: _DebugJointPainter(svgPathData),
      ),
    );
  }
}

class _DebugJointPainter extends CustomPainter {
  final String svgPathData;
  
  _DebugJointPainter(this.svgPathData);
  
  @override
  void paint(Canvas canvas, Size size) {
    // Get analysis
    final analysis = SvgJointDetector.analyzePathJoints(svgPathData);
    
    // Render joints with labels
    SvgJointDetector.renderJointsWithLabels(
      canvas,
      analysis.joints,
      radius: 6.0,
      color: Colors.red,
      textStyle: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.bold,
        backgroundColor: Colors.black,
      ),
    );
    
    // Draw segment lines
    final paint = Paint()
      ..color = Colors.green.withOpacity(0.5)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    
    for (var segment in analysis.segments) {
      canvas.drawLine(segment.start, segment.end, paint);
    }
    
    // Draw bounding box
    if (analysis.boundingBox != null) {
      final boxPaint = Paint()
        ..color = Colors.blue.withOpacity(0.3)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;
      
      canvas.drawRect(analysis.boundingBox!, boxPaint);
    }
  }
  
  @override
  bool shouldRepaint(_DebugJointPainter oldDelegate) => 
      oldDelegate.svgPathData != svgPathData;
}

/// ==============================================================================
/// EXAMPLE 6: Auto-Generate Level Thumbnails Based on Joints
/// ==============================================================================

class LevelThumbnailGenerator {
  /// Generate a simplified thumbnail representation using joints
  static Widget generateThumbnail(
    String svgPathData, {
    double size = 100,
    Color color = Colors.white,
  }) {
    return CustomPaint(
      size: Size(size, size),
      painter: _ThumbnailPainter(svgPathData, color),
    );
  }
}

class _ThumbnailPainter extends CustomPainter {
  final String svgPathData;
  final Color color;
  
  _ThumbnailPainter(this.svgPathData, this.color);
  
  @override
  void paint(Canvas canvas, Size size) {
    final analysis = SvgJointDetector.analyzePathJoints(svgPathData);
    
    if (analysis.boundingBox == null || analysis.joints.isEmpty) return;
    
    // Scale joints to fit thumbnail
    final bbox = analysis.boundingBox!;
    final scale = (size.width * 0.8) / bbox.width.clamp(1, double.infinity);
    
    final transformedJoints = analysis.joints.map((j) {
      return Offset(
        (j.dx - bbox.left) * scale + size.width * 0.1,
        (j.dy - bbox.top) * scale + size.height * 0.1,
      );
    }).toList();
    
    // Draw simplified path
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    
    final path = Path();
    if (transformedJoints.isNotEmpty) {
      path.moveTo(transformedJoints[0].dx, transformedJoints[0].dy);
      for (int i = 1; i < transformedJoints.length; i++) {
        path.lineTo(transformedJoints[i].dx, transformedJoints[i].dy);
      }
    }
    
    canvas.drawPath(path, paint);
  }
  
  @override
  bool shouldRepaint(_ThumbnailPainter oldDelegate) =>
      oldDelegate.svgPathData != svgPathData || oldDelegate.color != color;
}

/// ==============================================================================
/// Usage in Your Game
/// ==============================================================================

/*
// In your game level screen:
class LevelScreen extends StatefulWidget {
  final String svgPath;
  
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Your existing game canvas
        CustomPaint(
          painter: EnhancedGamePainter(
            svgPath: loadedPath,
            svgPathData: rawSvgPathData, // NEW: Pass the raw SVG data
            showDetectedJoints: debugMode, // NEW: Show joints in debug mode
            // ... other existing parameters
          ),
        ),
        
        // Debug overlay (only in development)
        if (kDebugMode)
          DebugJointOverlay(
            svgPathData: rawSvgPathData,
            enabled: true,
          ),
      ],
    );
  }
}

// In your level selector:
class LevelButton extends StatelessWidget {
  final String svgPathData;
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Thumbnail generated from joints
        LevelThumbnailGenerator.generateThumbnail(svgPathData),
        
        // Show difficulty calculated from joints
        Text(
          LevelComplexityAnalyzer.analyzeLevelComplexity(svgPathData)['difficulty'],
        ),
      ],
    );
  }
}
*/
