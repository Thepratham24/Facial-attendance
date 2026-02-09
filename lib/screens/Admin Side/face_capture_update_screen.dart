import 'dart:io';
import 'dart:ui'; // For BackdropFilter
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../../services/ml_service.dart';
import '../../main.dart';
import '../../widgets/face_painter.dart'; // 🔴 IMPORT JARURI HAI

class FaceCaptureScreen extends StatefulWidget {
  const FaceCaptureScreen({super.key});

  @override
  State<FaceCaptureScreen> createState() => _FaceCaptureScreenState();
}

class _FaceCaptureScreenState extends State<FaceCaptureScreen> {
  final MLService _mlService = MLService();

  CameraController? _controller;
  late FaceDetector _faceDetector;

  bool _isDetecting = false;
  bool _isCapturing = false;
  bool _faceFound = false;

  // 🔴 Data for Painting
  List<Face> _faces = []; // Chehre ki drawing ke liye

  CameraImage? _latestImage;
  Face? _latestFace;

  @override
  void initState() {
    super.initState();
    _faceDetector = FaceDetector(options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast));
    _initializeCamera();
  }

  void _initializeCamera() async {
    if (cameras.isEmpty) return;

    var camera = cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first
    );

    _controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888
    );

    try {
      await _controller!.initialize();
      if (!mounted) return;
      setState(() {});

      _controller!.startImageStream((image) => _processCameraFrame(image));
    } catch (e) {
      debugPrint("Camera Init Error: $e");
    }
  }

  void _processCameraFrame(CameraImage image) async {
    if (_isDetecting || _isCapturing) return;
    _isDetecting = true;

    try {
      final inputImage = _convertCameraImage(image);
      if (inputImage == null) {
        _isDetecting = false;
        return;
      }

      final faces = await _faceDetector.processImage(inputImage);

      // 🔴 Update Faces List for Drawing
      if (mounted) {
        setState(() {
          _faces = faces;
        });
      }

      if (faces.isNotEmpty) {
        _latestImage = image;
        _latestFace = faces[0];

        if (!_faceFound && mounted) {
          setState(() => _faceFound = true);
        }
      } else {
        _latestImage = null;
        _latestFace = null;

        if (_faceFound && mounted) {
          setState(() => _faceFound = false);
        }
      }
    } catch (e) {
      debugPrint("Detection Error: $e");
    } finally {
      _isDetecting = false;
    }
  }

  Future<void> _onCapturePressed() async {
    if (!_faceFound || _latestImage == null || _latestFace == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No Face Detected! Please align face."), backgroundColor: Colors.red)
      );
      return;
    }

    setState(() => _isCapturing = true);

    try {
      List<double> embedding = await _mlService.getEmbedding(_latestImage!, _latestFace!);
      await _controller!.stopImageStream();

      if (mounted) {
        Navigator.pop(context, embedding);
      }
    } catch (e) {
      debugPrint("Embedding Error: $e");
      setState(() => _isCapturing = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Capture Failed. Try Again.")));
    }
  }

  InputImage? _convertCameraImage(CameraImage image) {
    if (_controller == null) return null;
    try {
      final camera = _controller!.description;
      final sensorOrientation = camera.sensorOrientation;
      InputImageRotation rotation = InputImageRotation.rotation0deg;

      if (Platform.isAndroid) {
        var rotationCompensation = (sensorOrientation + 0) % 360;
        rotation = InputImageRotationValue.fromRawValue(rotationCompensation) ?? InputImageRotation.rotation270deg;
      }

      return InputImage.fromBytes(
          bytes: _mlService.concatenatePlanes(image.planes),
          metadata: InputImageMetadata(
              size: Size(image.width.toDouble(), image.height.toDouble()),
              rotation: rotation,
              format: Platform.isAndroid ? InputImageFormat.nv21 : InputImageFormat.bgra8888,
              bytesPerRow: image.planes[0].bytesPerRow
          )
      );
    } catch (_) { return null; }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 🔴 1. Camera Layer with FacePainter
          if (_controller != null && _controller!.value.isInitialized)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _controller!.value.previewSize!.height,
                  height: _controller!.value.previewSize!.width,
                  child: CameraPreview(
                    _controller!,
                    // 🔴 Yahan 'FacePainter' Lagaya Hai
                    child: CustomPaint(
                      painter: FacePainter(
                          faces: _faces,
                          imageSize: _controller!.value.previewSize!
                      ),
                    ),
                  ),
                ),
              ),
            )
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),

          // 2. Back Button
          Positioned(
            top: 50, left: 20,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                child: const Icon(Icons.arrow_back, color: Colors.white),
              ),
            ),
          ),

          // 3. Status Text
          Positioned(
            top: 60, left: 0, right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: _faceFound ? Colors.green.withOpacity(0.8) : Colors.red.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _faceFound ? "Face Detected" : "Align Face",
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),

          // 4. Bottom Control Panel
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 30, 20, 40),
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.6)),
                  child: Column(
                    children: [
                      Text(
                        _isCapturing ? "Updating..." : "Update Employee Face",
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 20),

                      SizedBox(
                        width: double.infinity, height: 55,
                        child: ElevatedButton(
                          onPressed: (_isCapturing || !_faceFound) ? null : _onCapturePressed,
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                          ),
                          child: Ink(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: _faceFound
                                    ? [const Color(0xFF2E3192), const Color(0xFF1BFFFF)]
                                    : [Colors.grey, Colors.grey.shade700],
                              ),
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: Center(
                              child: _isCapturing
                                  ? const CircularProgressIndicator(color: Colors.white)
                                  : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(Icons.camera_alt, color: Colors.white),
                                  SizedBox(width: 10),
                                  Text("CAPTURE & UPDATE", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16))
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}