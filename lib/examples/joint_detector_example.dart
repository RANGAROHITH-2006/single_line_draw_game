import 'package:flutter/material.dart';
import '../svg_joint_detector.dart';

/// Example demonstrating how to use the SvgJointDetector utility
/// to detect and visualize all joints in SVG paths

void main() {
  runApp(const JointDetectorExampleApp());
}

class JointDetectorExampleApp extends StatelessWidget {
  const JointDetectorExampleApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SVG Joint Detector Example',
      theme: ThemeData.dark(),
      home: const JointDetectorDemo(),
    );
  }
}

class JointDetectorDemo extends StatefulWidget {
  const JointDetectorDemo({Key? key}) : super(key: key);

  @override
  State<JointDetectorDemo> createState() => _JointDetectorDemoState();
}

class _JointDetectorDemoState extends State<JointDetectorDemo> {
  // Example SVG paths to demonstrate the joint detector
  final List<SvgPathExample> examples = [
    SvgPathExample(
      name: 'Simple Triangle',
      pathData: 'M 50 50 L 150 50 L 100 150 Z',
      description: 'Three vertices forming a closed triangle',
    ),
    SvgPathExample(
      name: 'Square',
      pathData: 'M 50 50 L 150 50 L 150 150 L 50 150 Z',
      description: 'Four vertices forming a square',
    ),
    SvgPathExample(
      name: 'Star',
      pathData: 'M 100 50 L 120 90 L 160 90 L 130 110 L 145 150 L 100 125 L 55 150 L 70 110 L 40 90 L 80 90 Z',
      description: 'Multi-point star shape',
    ),
    SvgPathExample(
      name: 'Curved Path',
      pathData: 'M 50 100 Q 100 50 150 100 T 250 100',
      description: 'Quadratic Bezier curves',
    ),
    SvgPathExample(
      name: 'Complex Shape with Curves',
      pathData: 'M 50 100 C 50 50 150 50 150 100 S 250 150 250 100',
      description: 'Cubic Bezier curves',
    ),
    SvgPathExample(
      name: 'Mixed Commands',
      pathData: 'M 50 50 H 150 V 150 L 50 150 Z',
      description: 'Mix of H (horizontal) and V (vertical) commands',
    ),
  ];

  int currentExampleIndex = 0;
  bool showLabels = false;
  bool includeControlPoints = true;

  SvgPathExample get currentExample => examples[currentExampleIndex];

  @override
  Widget build(BuildContext context) {
    // Detect joints for the current path
    final joints = SvgJointDetector.detectJoints(
      currentExample.pathData,
      includeControlPoints: includeControlPoints,
      duplicateTolerance: 1.0,
    );

    // Get detailed analysis
    final analysis = SvgJointDetector.analyzePathJoints(
      currentExample.pathData,
      includeControlPoints: includeControlPoints,
      duplicateTolerance: 1.0,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('SVG Joint Detector Demo'),
        actions: [
          IconButton(
            icon: Icon(showLabels ? Icons.label_off : Icons.label),
            onPressed: () => setState(() => showLabels = !showLabels),
            tooltip: showLabels ? 'Hide Labels' : 'Show Labels',
          ),
        ],
      ),
      body: Column(
        children: [
          // Example selector
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[900],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            currentExample.name,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            currentExample.description,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[400],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: currentExampleIndex > 0
                          ? () => setState(() => currentExampleIndex--)
                          : null,
                    ),
                    Text('${currentExampleIndex + 1}/${examples.length}'),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward),
                      onPressed: currentExampleIndex < examples.length - 1
                          ? () => setState(() => currentExampleIndex++)
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  title: const Text('Include Control Points'),
                  subtitle: const Text('Show Bezier curve control points as joints'),
                  value: includeControlPoints,
                  onChanged: (value) => setState(() => includeControlPoints = value ?? true),
                  dense: true,
                ),
              ],
            ),
          ),

          // Canvas for visualizing joints
          Expanded(
            child: Container(
              color: Colors.black,
              child: CustomPaint(
                painter: JointVisualizationPainter(
                  pathData: currentExample.pathData,
                  joints: joints,
                  showLabels: showLabels,
                ),
                size: Size.infinite,
              ),
            ),
          ),

          // Analysis information
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[900],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Analysis Results',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                _buildInfoRow('Total Joints', analysis.joints.length.toString()),
                _buildInfoRow('Segments', analysis.segments.length.toString()),
                _buildInfoRow('Approximate Length', analysis.totalLength.toStringAsFixed(2)),
                _buildInfoRow('Average Segment', 
                    analysis.segments.isNotEmpty ? (analysis.totalLength / analysis.segments.length).toStringAsFixed(2) : '0'),
                _buildInfoRow('Bounding Box', 
                    analysis.boundingBox != null ? '${analysis.boundingBox!.width.toStringAsFixed(0)} × ${analysis.boundingBox!.height.toStringAsFixed(0)}' : 'N/A'),
                _buildInfoRow('Center', 
                    analysis.center != null ? '(${analysis.center!.dx.toStringAsFixed(1)}, ${analysis.center!.dy.toStringAsFixed(1)})' : 'N/A'),
                const SizedBox(height: 8),
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  'Path Data: ${currentExample.pathData}',
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: Colors.grey[400],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$label:',
            style: TextStyle(color: Colors.grey[400]),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter to visualize the path and its joints
class JointVisualizationPainter extends CustomPainter {
  final String pathData;
  final List<Offset> joints;
  final bool showLabels;

  JointVisualizationPainter({
    required this.pathData,
    required this.joints,
    required this.showLabels,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw the path in the background
    _drawPath(canvas, size);

    // Calculate scale and offset to center the path
    if (joints.isEmpty) return;

    // Find bounding box of joints
    double minX = joints.first.dx;
    double maxX = joints.first.dx;
    double minY = joints.first.dy;
    double maxY = joints.first.dy;

    for (var joint in joints) {
      if (joint.dx < minX) minX = joint.dx;
      if (joint.dx > maxX) maxX = joint.dx;
      if (joint.dy < minY) minY = joint.dy;
      if (joint.dy > maxY) maxY = joint.dy;
    }

    // Calculate scale to fit in canvas with padding
    final padding = 60.0;
    final pathWidth = maxX - minX;
    final pathHeight = maxY - minY;
    final scaleX = (size.width - padding * 2) / pathWidth;
    final scaleY = (size.height - padding * 2) / pathHeight;
    final scale = scaleX < scaleY ? scaleX : scaleY;

    // Calculate offset to center
    final scaledWidth = pathWidth * scale;
    final scaledHeight = pathHeight * scale;
    final offsetX = (size.width - scaledWidth) / 2 - minX * scale;
    final offsetY = (size.height - scaledHeight) / 2 - minY * scale;

    // Transform joints
    final transformedJoints = joints.map((j) {
      return Offset(
        j.dx * scale + offsetX,
        j.dy * scale + offsetY,
      );
    }).toList();

    // Render joints with visualization
    if (showLabels) {
      SvgJointDetector.renderJointsWithLabels(
        canvas,
        transformedJoints,
        color: const Color(0xFFFFD700),
        radius: 6.0,
      );
    } else {
      SvgJointDetector.renderJoints(
        canvas,
        transformedJoints,
        color: const Color(0xFFFFD700),
        radius: 6.0,
      );
    }
  }

  void _drawPath(Canvas canvas, Size size) {
    // Parse path data and draw the actual path
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // This is a simplified visualization - in a real app you would use
    // the path_drawing package to create a Path from the pathData
    final pathPaint = Paint()
      ..color = Colors.blue.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    // Draw connection lines between joints for visualization
    final segments = SvgJointDetector.getSegments(
      SvgJointDetector.detectJoints(
        pathData,
        includeControlPoints: false,
      ),
    );

    // (In a complete implementation, you would render the actual SVG path here)
  }

  @override
  bool shouldRepaint(JointVisualizationPainter oldDelegate) {
    return oldDelegate.pathData != pathData ||
        oldDelegate.joints != joints ||
        oldDelegate.showLabels != showLabels;
  }
}

/// Data class for example SVG paths
class SvgPathExample {
  final String name;
  final String pathData;
  final String description;

  const SvgPathExample({
    required this.name,
    required this.pathData,
    required this.description,
  });
}
