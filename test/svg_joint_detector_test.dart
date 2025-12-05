import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:singlelinedraw/svg_joint_detector.dart';

/// Test suite for SvgJointDetector
/// Run with: flutter test test/svg_joint_detector_test.dart
void main() {
  group('SvgJointDetector - Basic Detection', () {
    test('Detects joints in simple triangle', () {
      const pathData = 'M 50 50 L 150 50 L 100 150 Z';
      final joints = SvgJointDetector.detectJoints(pathData, includeControlPoints: false);
      
      // Z command adds closing point back to start
      expect(joints.length, 4);
      expect(joints[0], const Offset(50, 50));
      expect(joints[1], const Offset(150, 50));
      expect(joints[2], const Offset(100, 150));
    });

    test('Detects joints in square', () {
      const pathData = 'M 50 50 L 150 50 L 150 150 L 50 150 Z';
      final joints = SvgJointDetector.detectJoints(pathData, includeControlPoints: false);
      
      // Z command adds closing point
      expect(joints.length, 5);
    });

    test('Handles horizontal and vertical commands', () {
      const pathData = 'M 50 50 H 150 V 150 H 50 Z';
      final joints = SvgJointDetector.detectJoints(pathData, includeControlPoints: false);
      
      // Z command adds closing point
      expect(joints.length, 5);
      expect(joints[0], const Offset(50, 50));
      expect(joints[1], const Offset(150, 50));
      expect(joints[2], const Offset(150, 150));
      expect(joints[3], const Offset(50, 150));
    });

    test('Handles relative commands', () {
      const pathData = 'm 50 50 l 100 0 l 0 100 l -100 0 z';
      final joints = SvgJointDetector.detectJoints(pathData, includeControlPoints: false);
      
      // z command adds closing point
      expect(joints.length, 5);
    });
  });

  group('SvgJointDetector - Curves', () {
    test('Detects endpoints in quadratic bezier', () {
      const pathData = 'M 50 100 Q 100 50 150 100';
      final joints = SvgJointDetector.detectJoints(
        pathData,
        includeControlPoints: false,
      );
      
      expect(joints.length, 2);
      expect(joints[0], const Offset(50, 100));
      expect(joints[1], const Offset(150, 100));
    });

    test('Includes control points when requested', () {
      const pathData = 'M 50 100 Q 100 50 150 100';
      final joints = SvgJointDetector.detectJoints(
        pathData,
        includeControlPoints: true,
      );
      
      expect(joints.length, 3);
      expect(joints[0], const Offset(50, 100));
      expect(joints[1], const Offset(100, 50)); // Control point
      expect(joints[2], const Offset(150, 100));
    });

    test('Detects cubic bezier endpoints', () {
      const pathData = 'M 50 100 C 50 50 150 50 150 100';
      final joints = SvgJointDetector.detectJoints(
        pathData,
        includeControlPoints: false,
      );
      
      expect(joints.length, 2);
    });

    test('Includes cubic bezier control points', () {
      const pathData = 'M 50 100 C 50 50 150 50 150 100';
      final joints = SvgJointDetector.detectJoints(
        pathData,
        includeControlPoints: true,
      );
      
      expect(joints.length, 4); // Start + 2 control points + end
    });
  });

  group('SvgJointDetector - Duplicate Filtering', () {
    test('Filters duplicate joints', () {
      const pathData = 'M 50 50 L 50.5 50.5 L 100 100';
      final joints = SvgJointDetector.detectJoints(
        pathData,
        duplicateTolerance: 1.0,
      );
      
      // Second point should be filtered as duplicate of first
      expect(joints.length, 2);
    });

    test('Keeps distinct joints', () {
      const pathData = 'M 50 50 L 100 100 L 150 150';
      final joints = SvgJointDetector.detectJoints(
        pathData,
        duplicateTolerance: 1.0,
      );
      
      expect(joints.length, 3);
    });
  });

  group('SvgJointDetector - Path Analysis', () {
    test('Analyzes simple path correctly', () {
      const pathData = 'M 0 0 L 100 0 L 100 100 L 0 100 Z';
      final analysis = SvgJointDetector.analyzePathJoints(pathData);
      
      // Z adds closing point
      expect(analysis.joints.length, 5);
      // With 5 joints, we have 4 segments
      expect(analysis.segments.length, 4);
      expect(analysis.totalLength, greaterThan(0));
      expect(analysis.boundingBox, isNotNull);
      expect(analysis.center, isNotNull);
    });

    test('Calculates bounding box correctly', () {
      const pathData = 'M 50 50 L 150 50 L 100 150 Z';
      final analysis = SvgJointDetector.analyzePathJoints(pathData);
      
      expect(analysis.boundingBox, isNotNull);
      expect(analysis.boundingBox!.left, 50);
      expect(analysis.boundingBox!.top, 50);
      expect(analysis.boundingBox!.right, 150);
      expect(analysis.boundingBox!.bottom, 150);
    });

    test('Calculates center point correctly', () {
      const pathData = 'M 0 0 L 100 0 L 100 100 L 0 100 Z';
      final analysis = SvgJointDetector.analyzePathJoints(pathData);
      
      expect(analysis.center, isNotNull);
      expect(analysis.center!.dx, 50);
      expect(analysis.center!.dy, 50);
    });
  });

  group('SvgJointDetector - Segments', () {
    test('Generates segments from joints', () {
      final joints = [
        const Offset(0, 0),
        const Offset(100, 0),
        const Offset(100, 100),
      ];
      
      final segments = SvgJointDetector.getSegments(joints);
      
      expect(segments.length, 2);
      expect(segments[0].start, const Offset(0, 0));
      expect(segments[0].end, const Offset(100, 0));
      expect(segments[1].start, const Offset(100, 0));
      expect(segments[1].end, const Offset(100, 100));
    });

    test('Calculates segment length correctly', () {
      final joints = [
        const Offset(0, 0),
        const Offset(3, 4),
      ];
      
      final segments = SvgJointDetector.getSegments(joints);
      
      expect(segments.length, 1);
      expect(segments[0].length, 5.0); // 3-4-5 triangle
    });

    test('Calculates segment angle correctly', () {
      final joints = [
        const Offset(0, 0),
        const Offset(100, 0), // Horizontal line
      ];
      
      final segments = SvgJointDetector.getSegments(joints);
      
      expect(segments[0].angle, 0.0); // 0 radians = horizontal
    });

    test('Calculates segment midpoint correctly', () {
      final joints = [
        const Offset(0, 0),
        const Offset(100, 100),
      ];
      
      final segments = SvgJointDetector.getSegments(joints);
      
      expect(segments[0].midpoint, const Offset(50, 50));
    });
  });

  group('SvgJointDetector - Edge Cases', () {
    test('Handles empty path', () {
      const pathData = '';
      final joints = SvgJointDetector.detectJoints(pathData);
      
      expect(joints, isEmpty);
    });

    test('Handles single move command', () {
      const pathData = 'M 50 50';
      final joints = SvgJointDetector.detectJoints(pathData);
      
      expect(joints.length, 1);
      expect(joints[0], const Offset(50, 50));
    });

    test('Handles path with only close command', () {
      const pathData = 'M 50 50 Z';
      final joints = SvgJointDetector.detectJoints(pathData);
      
      expect(joints.length, greaterThanOrEqualTo(1));
    });
  });

  group('SvgJointDetector - Real World Paths', () {
    test('Handles complex star shape', () {
      const pathData = 'M 100 50 L 120 90 L 160 90 L 130 110 '
          'L 145 150 L 100 125 L 55 150 L 70 110 L 40 90 L 80 90 Z';
      final joints = SvgJointDetector.detectJoints(pathData);
      
      // Z adds closing point
      expect(joints.length, 11);
    });

    test('Handles mixed commands path', () {
      const pathData = 'M 50 50 H 150 V 150 C 150 200 50 200 50 150 Z';
      final joints = SvgJointDetector.detectJoints(
        pathData,
        includeControlPoints: false,
      );
      
      expect(joints.length, greaterThan(2));
    });
  });
}
