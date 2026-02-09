import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../constants/app_colors.dart';

class FacePainter extends CustomPainter {
  final List<Face> faces;
  final Size imageSize;

  FacePainter({required this.faces, required this.imageSize});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = AppColors.scannerColor;

    for (var face in faces) {
      double scaleX = size.width / imageSize.height;
      double scaleY = size.height / imageSize.width;

      Rect rect = Rect.fromLTRB(
          face.boundingBox.left * scaleX,
          face.boundingBox.top * scaleY,
          face.boundingBox.right * scaleX,
          face.boundingBox.bottom * scaleY
      );

      // Draw rounded rect for scanner look
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(10)), paint);
    }
  }

  @override
  bool shouldRepaint(FacePainter oldDelegate) => true;
}