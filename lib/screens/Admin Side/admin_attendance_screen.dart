import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart'; // WriteBuffer
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:intl/intl.dart';
import 'dart:ui';

import '../../main.dart';
import '../../services/api_service.dart';
import '../../services/ml_service.dart';
import '../../widgets/face_painter.dart';
import '../Result_StartLogin Side/result_screen.dart';

class AdminAttendanceScreen extends StatefulWidget {
  const AdminAttendanceScreen({super.key});

  @override
  State<AdminAttendanceScreen> createState() => _AdminAttendanceScreenState();
}

class _AdminAttendanceScreenState extends State<AdminAttendanceScreen> with WidgetsBindingObserver {
  final MLService _mlService = MLService();
  final ApiService _apiService = ApiService();

  CameraController? _controller;
  CameraDescription? _cameraDescription;
  late FaceDetector _faceDetector;
  List<Face> _faces = [];

  bool _isNavigating = false;
  bool _isDetecting = false;
  bool _isProcessing = false;
  bool _canScan = false;
  bool _isForceCheckout = false;

  // 🔴 FAST PERFORMANCE FIX: Time Tracker
  DateTime _lastScanTime = DateTime(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _faceDetector = FaceDetector(options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast, // Keep it fast
        enableContours: false,
        enableClassification: false
    ));

    _initializeCamera();

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _canScan = true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;

    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      if (mounted) setState(() => _controller = null);
      _controller?.dispose();
    }
    else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  void _initializeCamera() async {
    if (cameras.isEmpty) return;

    if (_controller != null) {
      await _controller?.dispose();
    }

    _cameraDescription = cameras.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    _controller = CameraController(
      _cameraDescription!,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );

    try {
      await _controller!.initialize();
      if (!mounted) return;
      setState(() {});

      _controller!.startImageStream((image) {
        // 🔴 🔴 PERFORMANCE FIX: THROTTLING 🔴 🔴
        // Check if 800 milliseconds have passed since last scan
        // Isse GC load 90% kam ho jayega
        if (DateTime.now().difference(_lastScanTime).inMilliseconds < 800) {
          return; // Skip this frame
        }

        if (_canScan && !_isDetecting && !_isNavigating && !_isProcessing) {
          _lastScanTime = DateTime.now(); // Update time
          _doFaceDetection(image);
        }
      });
    } catch (e) {
      debugPrint("Camera Error: $e");
    }
  }

  Future<void> _stopCamera() async {
    if (_controller == null) return;
    final oldController = _controller;
    _controller = null;
    if (mounted) setState(() {});

    try {
      await oldController!.stopImageStream();
      await oldController.dispose();
    } catch (e) {}
  }

  Future<void> _doFaceDetection(CameraImage image) async {
    // Double check locks
    if (_isDetecting || _isNavigating || !mounted) return;
    _isDetecting = true;

    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) {
        _isDetecting = false;
        return;
      }

      final faces = await _faceDetector.processImage(inputImage);
      if (mounted) setState(() => _faces = faces);

      if (faces.isEmpty) {
        _isDetecting = false;
        return;
      }

      // Face Detected -> Start Process
      if (mounted && !_isProcessing) {
        setState(() => _isProcessing = true);
      }

      List<double> embedding = await _mlService.getEmbedding(image, faces[0]);
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);

      // 🔴 Current Device Time
      String currentTime = DateTime.now().toIso8601String();

      Map<String, dynamic> result;
      if (_isForceCheckout) {
        result = await _apiService.forceCheckOut(
          faceEmbedding: embedding,
          latitude: pos.latitude,
          longitude: pos.longitude,
          isFromAdminPhone: true,
          deviceDate: currentTime,
        );
      } else {
        result = await _apiService.markAttendance(
          faceEmbedding: embedding,
          latitude: pos.latitude,
          longitude: pos.longitude,
          isFromAdminPhone: true,
          deviceDate: currentTime,
        );
      }

      bool isSuccess = result['success'] == true;
      String backendMessage = result['message'] ?? "Unknown Response";

      if (isSuccess) {
        _isNavigating = true;
        await _stopCamera();

        String finalName = _getSafeName(result);

        if (mounted) {
          await Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => ResultScreen(
                  name: finalName,
                  imagePath: "",
                  punchStatus: backendMessage,
                  punchTime: DateFormat('hh:mm a').format(DateTime.now())
              ))
          );
        }
      } else {
        if (mounted) _showTopNotification(backendMessage, true);

        // 🔴 Wait before unlocking (Memory cleanup time)
        await Future.delayed(const Duration(seconds: 2));

        if (mounted) setState(() {
          _isProcessing = false;
          _isDetecting = false;
        });
      }

    } catch (e) {
      debugPrint("Error: $e");
      if (mounted) setState(() => _isProcessing = false);
    } finally {
      if (mounted && !_isNavigating && !_isProcessing) _isDetecting = false;
    }
  }

  String _getSafeName(Map<String, dynamic> response) {
    try {
      var data = response['data'];
      if (data == null) return "Verified User";
      if (data['employee'] != null && data['employee'] is Map) {
        return data['employee']['name'] ?? "Verified User";
      }
      if (data['name'] != null) return data['name'];
      if (data['record'] != null && data['record']['employeeId'] != null) {
        var emp = data['record']['employeeId'];
        if (emp is Map) return emp['name'] ?? "Verified User";
      }
      return "Verified User";
    } catch (_) { return "Verified User"; }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    if (_controller == null || _cameraDescription == null) return null;

    final rotation = InputImageRotationValue.fromRawValue(_cameraDescription!.sensorOrientation);
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null || (Platform.isAndroid && format != InputImageFormat.nv21)) return null;

    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    final metadata = InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: format,
      bytesPerRow: image.planes[0].bytesPerRow,
    );

    return InputImage.fromBytes(bytes: bytes, metadata: metadata);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            if (_controller != null && _controller!.value.isInitialized && !_isNavigating)
              SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _controller!.value.previewSize!.height,
                    height: _controller!.value.previewSize!.width,
                    child: CameraPreview(_controller!, child: CustomPaint(painter: FacePainter(faces: _faces, imageSize: _controller!.value.previewSize!))),
                  ),
                ),
              )
            else
              const Center(child: CircularProgressIndicator(color: Colors.white)),

            Positioned(
              top: 50, left: 20,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
                style: IconButton.styleFrom(backgroundColor: Colors.black45),
              ),
            ),

            Positioned(
              top: 50, right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(30), border: _isForceCheckout ? Border.all(color: Colors.redAccent, width: 2) : null),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("Force Out", style: TextStyle(color: _isForceCheckout ? Colors.redAccent : Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(width: 5),
                    Transform.scale(scale: 0.8, child: Switch(value: _isForceCheckout, activeColor: Colors.red, onChanged: (v) => setState(() => _isForceCheckout = v))),
                  ],
                ),
              ),
            ),

            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 30, 20, 40),
                decoration: BoxDecoration(color: _isForceCheckout ? Colors.red.withOpacity(0.8) : Colors.black.withOpacity(0.7), borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _isProcessing
                        ? const SizedBox(height: 30, width: 30, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                        : Icon(_isForceCheckout ? Icons.logout : Icons.face, color: Colors.white, size: 40),
                    const SizedBox(height: 15),
                    Text(
                      _isProcessing ? "Processing..." : (_isForceCheckout ? "FORCE CHECK-OUT MODE" : "Face Recognition Active"),
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 5),
                    Text(_faces.isEmpty ? "Align face in center" : "Face Detected!", style: TextStyle(color: _faces.isEmpty ? Colors.white54 : Colors.greenAccent, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTopNotification(String m, bool err) {
    if (!mounted) return;
    OverlayEntry entry = OverlayEntry(builder: (c) => Positioned(
        top: 130, left: 20, right: 20,
        child: Material(
            color: Colors.transparent,
            child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(color: err ? Colors.redAccent : Colors.green, borderRadius: BorderRadius.circular(30)),
                child: Row(children: [Icon(err ? Icons.error_outline : Icons.check_circle, color: Colors.white), const SizedBox(width: 10), Expanded(child: Text(m, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))])
            )
        )
    ));
    Overlay.of(context).insert(entry);
    Future.delayed(const Duration(seconds: 2), () => entry.remove());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final camera = _controller;
    _controller = null;
    if (camera != null) camera.dispose();
    _faceDetector.close();
    super.dispose();
  }
}



















//
//
//
//
//
//
//
//
//
//
//
//
// import 'dart:async';
// import 'dart:io';
// import 'package:camera/camera.dart';
// import 'package:flutter/foundation.dart'; // WriteBuffer
// import 'package:flutter/material.dart';
// import 'package:geolocator/geolocator.dart';
// import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
// import 'package:intl/intl.dart';
// import 'dart:ui';
//
// import '../../main.dart';
// import '../../services/api_service.dart';
// import '../../services/ml_service.dart';
// import '../../widgets/face_painter.dart';
// import '../Result_StartLogin Side/result_screen.dart';
//
// class AdminAttendanceScreen extends StatefulWidget {
//   const AdminAttendanceScreen({super.key});
//
//   @override
//   State<AdminAttendanceScreen> createState() => _AdminAttendanceScreenState();
// }
//
// class _AdminAttendanceScreenState extends State<AdminAttendanceScreen> with WidgetsBindingObserver {
//   final MLService _mlService = MLService();
//   final ApiService _apiService = ApiService();
//
//   CameraController? _controller;
//   CameraDescription? _cameraDescription;
//   late FaceDetector _faceDetector;
//   List<Face> _faces = [];
//
//   bool _isNavigating = false;
//
//   // 🔴 1. STRICT LOCK VARIABLE (Ye camera ko atakne se rokega)
//   bool _isBusy = false;
//
//   bool _isForceCheckout = false;
//   bool _canScan = false;
//
//   @override
//   void initState() {
//     super.initState();
//     WidgetsBinding.instance.addObserver(this);
//
//     _faceDetector = FaceDetector(options: FaceDetectorOptions(
//         performanceMode: FaceDetectorMode.fast,
//         enableContours: false,
//         enableClassification: false
//     ));
//
//     _initializeCamera();
//
//     // 2 second delay to settle camera
//     Future.delayed(const Duration(seconds: 2), () {
//       if (mounted) setState(() => _canScan = true);
//     });
//   }
//
//   @override
//   void didChangeAppLifecycleState(AppLifecycleState state) {
//     if (_controller == null || !_controller!.value.isInitialized) return;
//
//     if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
//       // Background me gaya to camera band
//       _controller?.dispose();
//     } else if (state == AppLifecycleState.resumed) {
//       // Wapis aaya to camera chalu
//       _initializeCamera();
//     }
//   }
//
//   void _initializeCamera() async {
//     if (cameras.isEmpty) return;
//
//     // Purana controller dispose karo
//     if (_controller != null) {
//       await _controller?.dispose();
//     }
//
//     _cameraDescription = cameras.firstWhere(
//           (camera) => camera.lensDirection == CameraLensDirection.front,
//       orElse: () => cameras.first,
//     );
//
//     _controller = CameraController(
//       _cameraDescription!,
//       ResolutionPreset.medium,
//       enableAudio: false,
//       imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
//     );
//
//     try {
//       await _controller!.initialize();
//       if (!mounted) return;
//       setState(() {});
//
//       _controller!.startImageStream((image) async {
//         // 🔴 2. BUFFER FIX LOGIC
//         // Agar pehle se busy hai, to is frame ko ignore karo (Drop Frame)
//         if (_isBusy || !_canScan || _isNavigating) return;
//
//         _isBusy = true; // Taala lagao
//
//         try {
//           await _doFaceDetection(image);
//         } catch (e) {
//           debugPrint("Stream Error: $e");
//         } finally {
//           _isBusy = false; // Taala kholo (Chahe success ho ya fail)
//         }
//       });
//     } catch (e) {
//       debugPrint("Camera Error: $e");
//     }
//   }
//
//   Future<void> _stopCamera() async {
//     if (_controller == null) return;
//     final oldController = _controller;
//     _controller = null;
//     if (mounted) setState(() {});
//
//     try {
//       await oldController!.stopImageStream();
//       await oldController.dispose();
//     } catch (e) {}
//   }
//
//   Future<void> _doFaceDetection(CameraImage image) async {
//     // Basic check
//     if (_isNavigating || !mounted) return;
//
//     try {
//       final inputImage = _inputImageFromCameraImage(image);
//       if (inputImage == null) return;
//
//       final faces = await _faceDetector.processImage(inputImage);
//       if (mounted) setState(() => _faces = faces);
//
//       // Agar chehra nahi mila, to wapis jao
//       if (faces.isEmpty) return;
//
//       // --- FACE MIL GYA ---
//
//       // Embedding nikalo
//       List<double> embedding = await _mlService.getEmbedding(image, faces[0]);
//
//       // Location nikalo
//       Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
//
//       // Current Time
//       String currentTime = DateTime.now().toIso8601String();
//
//       // API Call
//       Map<String, dynamic> result;
//       if (_isForceCheckout) {
//         result = await _apiService.forceCheckOut(
//           faceEmbedding: embedding,
//           latitude: pos.latitude,
//           longitude: pos.longitude,
//           isFromAdminPhone: true,
//           deviceTime: currentTime,
//         );
//       } else {
//         result = await _apiService.markAttendance(
//           faceEmbedding: embedding,
//           latitude: pos.latitude,
//           longitude: pos.longitude,
//           isFromAdminPhone: true,
//           deviceTime: currentTime,
//         );
//       }
//
//       bool isSuccess = result['success'] == true;
//       String backendMessage = result['message'] ?? "Unknown Response";
//
//       if (isSuccess) {
//         // ✅ Success: Navigation Lock lagao
//         _isNavigating = true;
//
//         // Camera band karo
//         await _stopCamera();
//
//         String finalName = _getSafeName(result);
//
//         if (mounted) {
//           await Navigator.pushReplacement(
//               context,
//               MaterialPageRoute(builder: (context) => ResultScreen(
//                   name: finalName,
//                   imagePath: "",
//                   punchStatus: backendMessage,
//                   punchTime: DateFormat('hh:mm a').format(DateTime.now())
//               ))
//           );
//         }
//       } else {
//         // ❌ Fail: Toast dikhao
//         if (mounted) _showTopNotification(backendMessage, true);
//
//         // 🔴 Wait: Taaki user message padh sake aur system saans le sake
//         await Future.delayed(const Duration(seconds: 2));
//       }
//
//     } catch (e) {
//       debugPrint("Error: $e");
//     }
//   }
//
//   String _getSafeName(Map<String, dynamic> response) {
//     try {
//       var data = response['data'];
//       if (data == null) return "Verified User";
//       if (data['employee'] != null && data['employee'] is Map) {
//         return data['employee']['name'] ?? "Verified User";
//       }
//       if (data['name'] != null) return data['name'];
//       if (data['record'] != null && data['record']['employeeId'] != null) {
//         var emp = data['record']['employeeId'];
//         if (emp is Map) return emp['name'] ?? "Verified User";
//       }
//       return "Verified User";
//     } catch (_) { return "Verified User"; }
//   }
//
//   InputImage? _inputImageFromCameraImage(CameraImage image) {
//     if (_controller == null || _cameraDescription == null) return null;
//
//     final rotation = InputImageRotationValue.fromRawValue(_cameraDescription!.sensorOrientation);
//     if (rotation == null) return null;
//
//     final format = InputImageFormatValue.fromRawValue(image.format.raw);
//     if (format == null || (Platform.isAndroid && format != InputImageFormat.nv21)) return null;
//
//     final WriteBuffer allBytes = WriteBuffer();
//     for (final Plane plane in image.planes) {
//       allBytes.putUint8List(plane.bytes);
//     }
//     final bytes = allBytes.done().buffer.asUint8List();
//
//     final metadata = InputImageMetadata(
//       size: Size(image.width.toDouble(), image.height.toDouble()),
//       rotation: rotation,
//       format: format,
//       bytesPerRow: image.planes[0].bytesPerRow,
//     );
//
//     return InputImage.fromBytes(bytes: bytes, metadata: metadata);
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return PopScope(
//       canPop: false,
//       onPopInvokedWithResult: (didPop, result) {
//         if (didPop) return;
//         Navigator.pop(context);
//       },
//       child: Scaffold(
//         backgroundColor: Colors.black,
//         body: Stack(
//           children: [
//             // Camera
//             if (_controller != null && _controller!.value.isInitialized && !_isNavigating)
//               SizedBox.expand(
//                 child: FittedBox(
//                   fit: BoxFit.cover,
//                   child: SizedBox(
//                     width: _controller!.value.previewSize!.height,
//                     height: _controller!.value.previewSize!.width,
//                     child: CameraPreview(_controller!, child: CustomPaint(painter: FacePainter(faces: _faces, imageSize: _controller!.value.previewSize!))),
//                   ),
//                 ),
//               )
//             else
//               const Center(child: CircularProgressIndicator(color: Colors.white)),
//
//             // Back Button
//             Positioned(
//               top: 50, left: 20,
//               child: IconButton(
//                 icon: const Icon(Icons.arrow_back, color: Colors.white),
//                 onPressed: () => Navigator.pop(context),
//                 style: IconButton.styleFrom(backgroundColor: Colors.black45),
//               ),
//             ),
//
//             // Toggle
//             Positioned(
//               top: 50, right: 20,
//               child: Container(
//                 padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
//                 decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(30), border: _isForceCheckout ? Border.all(color: Colors.redAccent, width: 2) : null),
//                 child: Row(
//                   mainAxisSize: MainAxisSize.min,
//                   children: [
//                     Text("Force Out", style: TextStyle(color: _isForceCheckout ? Colors.redAccent : Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
//                     const SizedBox(width: 5),
//                     Transform.scale(scale: 0.8, child: Switch(value: _isForceCheckout, activeColor: Colors.red, onChanged: (v) => setState(() => _isForceCheckout = v))),
//                   ],
//                 ),
//               ),
//             ),
//
//             // Bottom Panel
//             Positioned(
//               bottom: 0, left: 0, right: 0,
//               child: Container(
//                 padding: const EdgeInsets.fromLTRB(20, 30, 20, 40),
//                 decoration: BoxDecoration(color: _isForceCheckout ? Colors.red.withOpacity(0.8) : Colors.black.withOpacity(0.7), borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
//                 child: Column(
//                   mainAxisSize: MainAxisSize.min,
//                   children: [
//                     _isBusy
//                         ? const SizedBox(height: 30, width: 30, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
//                         : Icon(_isForceCheckout ? Icons.logout : Icons.face, color: Colors.white, size: 40),
//                     const SizedBox(height: 15),
//                     Text(
//                       _isBusy ? "Processing..." : (_isForceCheckout ? "FORCE CHECK-OUT MODE" : "Face Recognition Active"),
//                       style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
//                     ),
//                     const SizedBox(height: 5),
//                     Text(_faces.isEmpty ? "Align face in center" : "Face Detected!", style: TextStyle(color: _faces.isEmpty ? Colors.white54 : Colors.greenAccent, fontSize: 12)),
//                   ],
//                 ),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
//
//   void _showTopNotification(String m, bool err) {
//     if (!mounted) return;
//     OverlayEntry entry = OverlayEntry(builder: (c) => Positioned(
//         top: 130, left: 20, right: 20,
//         child: Material(
//             color: Colors.transparent,
//             child: Container(
//                 padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
//                 decoration: BoxDecoration(color: err ? Colors.redAccent : Colors.green, borderRadius: BorderRadius.circular(30)),
//                 child: Row(children: [Icon(err ? Icons.error_outline : Icons.check_circle, color: Colors.white), const SizedBox(width: 10), Expanded(child: Text(m, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))])
//             )
//         )
//     ));
//     Overlay.of(context).insert(entry);
//     Future.delayed(const Duration(seconds: 2), () => entry.remove());
//   }
//
//   @override
//   void dispose() {
//     WidgetsBinding.instance.removeObserver(this);
//     final camera = _controller;
//     _controller = null;
//     if (camera != null) camera.dispose();
//     _faceDetector.close();
//     super.dispose();
//   }
// }
//
//
//
//
//
//
//
//
//
//
//
//
// // import 'dart:async';
// // import 'dart:io';
// // import 'package:camera/camera.dart';
// // import 'package:flutter/foundation.dart'; // WriteBuffer
// // import 'package:flutter/material.dart';
// // import 'package:geolocator/geolocator.dart';
// // import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
// // import 'package:intl/intl.dart';
// // import 'dart:ui';
// //
// // import '../../main.dart';
// // import '../../services/api_service.dart';
// // import '../../services/ml_service.dart';
// // import '../../widgets/face_painter.dart';
// // import '../Result_StartLogin Side/result_screen.dart';
// //
// // class AdminAttendanceScreen extends StatefulWidget {
// //   const AdminAttendanceScreen({super.key});
// //
// //   @override
// //   State<AdminAttendanceScreen> createState() => _AdminAttendanceScreenState();
// // }
// //
// // class _AdminAttendanceScreenState extends State<AdminAttendanceScreen> with WidgetsBindingObserver {
// //   final MLService _mlService = MLService();
// //   final ApiService _apiService = ApiService();
// //
// //   CameraController? _controller;
// //   // 🔴 Reference Code Variable
// //   CameraDescription? _cameraDescription;
// //   late FaceDetector _faceDetector;
// //   List<Face> _faces = [];
// //
// //   // 🔴 Flags (Exact Employee Screen Logic)
// //   bool _isNavigating = false;
// //   bool _isDetecting = false;
// //   bool _isProcessing = false;
// //   bool _canScan = false;
// //
// //   // 🔴 Admin Special Toggle
// //   bool _isForceCheckout = false;
// //
// //   @override
// //   void initState() {
// //     super.initState();
// //     WidgetsBinding.instance.addObserver(this);
// //
// //     // 1. Settings: Fast Mode (Same as Reference)
// //     _faceDetector = FaceDetector(options: FaceDetectorOptions(
// //         performanceMode: FaceDetectorMode.fast,
// //         enableContours: false,
// //         enableClassification: false
// //     ));
// //
// //     _initializeCamera();
// //
// //     // 2. Initial Delay
// //     Future.delayed(const Duration(seconds: 2), () {
// //       if (mounted) setState(() => _canScan = true);
// //     });
// //   }
// //
// //   @override
// //   void didChangeAppLifecycleState(AppLifecycleState state) {
// //     // Agar controller pehle se null hai to kuch mat karo
// //     if (_controller == null || !_controller!.value.isInitialized) return;
// //
// //     if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
// //       // 🔴 APP BACKGROUND ME GAYA:
// //       // Pehle UI update karo taaki 'CameraPreview' hat jaye aur 'Loader' dikhe
// //       if (mounted) {
// //         setState(() => _controller = null);
// //       }
// //       // Phir camera dispose karo
// //       _controller?.dispose();
// //     }
// //     else if (state == AppLifecycleState.resumed) {
// //       // 🔴 APP WAPIS AAYA:
// //       // Camera dobara start karo
// //       _initializeCamera();
// //     }
// //   }
// //
// //   // 🔴 Initialization Logic (Exact Copy of Employee Screen)
// //   void _initializeCamera() async {
// //     if (cameras.isEmpty) return;
// //
// //     // 🔴 AGAR PURANA HAI TO USE DISPOSE KARO
// //     if (_controller != null) {
// //       await _controller?.dispose();
// //     }
// //
// //     _cameraDescription = cameras.firstWhere(
// //           (camera) => camera.lensDirection == CameraLensDirection.front,
// //       orElse: () => cameras.first,
// //     );
// //
// //     _controller = CameraController(
// //       _cameraDescription!,
// //       ResolutionPreset.medium, // Medium works in Employee screen
// //       enableAudio: false,
// //       imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
// //     );
// //
// //     try {
// //       await _controller!.initialize();
// //       if (!mounted) return;
// //       setState(() {});
// //
// //       _controller!.startImageStream((image) {
// //         // Continuous Scanning Loop
// //         if (_canScan && !_isDetecting && !_isNavigating && !_isProcessing) {
// //           _doFaceDetection(image);
// //         }
// //       });
// //     } catch (e) {
// //       debugPrint("Camera Error: $e");
// //     }
// //   }
// //
// //   Future<void> _stopCamera() async {
// //     if (_controller == null) return;
// //     final oldController = _controller;
// //     _controller = null;
// //     if (mounted) setState(() {});
// //
// //     try {
// //       await oldController!.stopImageStream();
// //       await oldController.dispose();
// //     } catch (e) {}
// //   }
// //
// //   // 🔴 DETECTION LOGIC (Exact Copy + Admin Toggle)
// //   Future<void> _doFaceDetection(CameraImage image) async {
// //     if (_isDetecting || _isNavigating || !mounted) return;
// //     _isDetecting = true;
// //
// //     try {
// //       // Input Image Conversion
// //       final inputImage = _inputImageFromCameraImage(image);
// //       if (inputImage == null) {
// //         _isDetecting = false;
// //         return;
// //       }
// //
// //       final faces = await _faceDetector.processImage(inputImage);
// //       if (mounted) setState(() => _faces = faces);
// //
// //       if (faces.isEmpty) {
// //         _isDetecting = false;
// //         return;
// //       }
// //
// //       // Face found -> Start Processing
// //       if (mounted && !_isProcessing) {
// //         setState(() => _isProcessing = true);
// //       }
// //
// //       // --- CORE API LOGIC ---
// //       List<double> embedding = await _mlService.getEmbedding(image, faces[0]);
// //       Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
// //       String currentTime = DateTime.now().toIso8601String();
// //       // 🔴 CHANGE: Force Out Toggle Check
// //       Map<String, dynamic> result;
// //       if (_isForceCheckout) {
// //         result = await _apiService.forceCheckOut(
// //           faceEmbedding: embedding,
// //           latitude: pos.latitude,
// //           longitude: pos.longitude,
// //           isFromAdminPhone: true,
// //           deviceDate: currentTime,
// //         );
// //       } else {
// //         result = await _apiService.markAttendance(
// //           faceEmbedding: embedding,
// //           latitude: pos.latitude,
// //           longitude: pos.longitude,
// //           isFromAdminPhone: true,
// //           deviceDate: currentTime,
// //         );
// //       }
// //
// //       bool isSuccess = result['success'] == true ;
// //       String backendMessage = result['message'] ?? "Unknown Response";
// //
// //       if (isSuccess) {
// //         print("-----------------------------ye chlaaa");
// //         // ✅ Success: Stop Camera & Navigate
// //         _isNavigating = true;
// //         await _stopCamera();
// //
// //         String finalName = _getSafeName(result);
// //
// //         if (mounted) {
// //           await Navigator.pushReplacement(
// //               context,
// //               MaterialPageRoute(builder: (context) => ResultScreen(
// //                   name: finalName,
// //                   imagePath: "",
// //                   punchStatus: backendMessage,
// //                   punchTime: DateFormat('hh:mm a').format(DateTime.now())
// //               ))
// //           );
// //         }
// //       } else {
// //         print("-----------------------------ye chlaaa2222222222");
// //         // ❌ Failure: Show Toast & CONTINUE LOOP
// //         if (mounted) _showTopNotification(backendMessage, true);
// //
// //         // 2 Second wait (Memory cleaning time)
// //         await Future.delayed(const Duration(seconds: 2));
// //
// //         // Flags Reset -> Loop continues
// //         if (mounted) setState(() {
// //           _isProcessing = false;
// //           _isDetecting = false;
// //         });
// //       }
// //
// //     } catch (e) {
// //       debugPrint("Error: $e");
// //       if (mounted) setState(() => _isProcessing = false);
// //     } finally {
// //       // Safety Reset
// //       if (mounted && !_isNavigating && !_isProcessing) _isDetecting = false;
// //     }
// //   }
// //
// //   // Helper Name Extractor
// //   String _getSafeName(Map<String, dynamic> response) {
// //     try {
// //       var data = response['data'];
// //       if (data == null) return "Verified User";
// //
// //       // 1. Force Checkout Structure (data -> employee -> name)
// //       if (data['employee'] != null && data['employee'] is Map) {
// //         return data['employee']['name'] ?? "Verified User";
// //       }
// //
// //       // 2. Normal Attendance Structure (data -> name)
// //       if (data['name'] != null) return data['name'];
// //
// //       // 3. Record Structure
// //       if (data['record'] != null && data['record']['employeeId'] != null) {
// //         var emp = data['record']['employeeId'];
// //         if (emp is Map) return emp['name'] ?? "Verified User";
// //       }
// //
// //       return "Verified User";
// //     } catch (_) { return "Verified User"; }
// //   }
// //   // 🔴 Standard Input Image Logic (Exact Reference Copy)
// //   InputImage? _inputImageFromCameraImage(CameraImage image) {
// //     if (_controller == null || _cameraDescription == null) return null;
// //
// //     final rotation = InputImageRotationValue.fromRawValue(_cameraDescription!.sensorOrientation);
// //     if (rotation == null) return null;
// //
// //     final format = InputImageFormatValue.fromRawValue(image.format.raw);
// //     if (format == null || (Platform.isAndroid && format != InputImageFormat.nv21)) return null;
// //
// //     final WriteBuffer allBytes = WriteBuffer();
// //     for (final Plane plane in image.planes) {
// //       allBytes.putUint8List(plane.bytes);
// //     }
// //     final bytes = allBytes.done().buffer.asUint8List();
// //
// //     final metadata = InputImageMetadata(
// //       size: Size(image.width.toDouble(), image.height.toDouble()),
// //       rotation: rotation,
// //       format: format,
// //       bytesPerRow: image.planes[0].bytesPerRow,
// //     );
// //
// //     return InputImage.fromBytes(bytes: bytes, metadata: metadata);
// //   }
// //
// //   @override
// //   Widget build(BuildContext context) {
// //     return PopScope(
// //       canPop: false,
// //       onPopInvokedWithResult: (didPop, result) {
// //         if (didPop) return;
// //         Navigator.pop(context);
// //       },
// //       child: Scaffold(
// //         backgroundColor: Colors.black,
// //         body: Stack(
// //           children: [
// //             // Camera Preview
// //             if (_controller != null && _controller!.value.isInitialized && !_isNavigating)
// //               SizedBox.expand(
// //                 child: FittedBox(
// //                   fit: BoxFit.cover,
// //                   child: SizedBox(
// //                     width: _controller!.value.previewSize!.height,
// //                     height: _controller!.value.previewSize!.width,
// //                     child: CameraPreview(_controller!, child: CustomPaint(painter: FacePainter(faces: _faces, imageSize: _controller!.value.previewSize!))),
// //                   ),
// //                 ),
// //               )
// //             else
// //               const Center(child: CircularProgressIndicator(color: Colors.white)),
// //
// //             // Back Button
// //             Positioned(
// //               top: 50, left: 20,
// //               child: IconButton(
// //                 icon: const Icon(Icons.arrow_back, color: Colors.white),
// //                 onPressed: () => Navigator.pop(context),
// //                 style: IconButton.styleFrom(backgroundColor: Colors.black45),
// //               ),
// //             ),
// //
// //             // 🔴 Admin Toggle Button
// //             Positioned(
// //               top: 50, right: 20,
// //               child: Container(
// //                 padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
// //                 decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(30), border: _isForceCheckout ? Border.all(color: Colors.redAccent, width: 2) : null),
// //                 child: Row(
// //                   mainAxisSize: MainAxisSize.min,
// //                   children: [
// //                     Text("Force Out", style: TextStyle(color: _isForceCheckout ? Colors.redAccent : Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
// //                     const SizedBox(width: 5),
// //                     Transform.scale(scale: 0.8, child: Switch(value: _isForceCheckout, activeColor: Colors.red, onChanged: (v) => setState(() => _isForceCheckout = v))),
// //                   ],
// //                 ),
// //               ),
// //             ),
// //
// //             // Bottom UI
// //             Positioned(
// //               bottom: 0, left: 0, right: 0,
// //               child: Container(
// //                 padding: const EdgeInsets.fromLTRB(20, 30, 20, 40),
// //                 decoration: BoxDecoration(color: _isForceCheckout ? Colors.red.withOpacity(0.8) : Colors.black.withOpacity(0.7), borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
// //                 child: Column(
// //                   mainAxisSize: MainAxisSize.min,
// //                   children: [
// //                     _isProcessing
// //                         ? const SizedBox(height: 30, width: 30, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
// //                         : Icon(_isForceCheckout ? Icons.logout : Icons.face, color: Colors.white, size: 40),
// //                     const SizedBox(height: 15),
// //                     Text(
// //                       _isProcessing ? "Processing..." : (_isForceCheckout ? "FORCE CHECK-OUT MODE" : "Face Recognition Active"),
// //                       style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
// //                     ),
// //                     const SizedBox(height: 5),
// //                     Text(_faces.isEmpty ? "Align face in center" : "Face Detected!", style: TextStyle(color: _faces.isEmpty ? Colors.white54 : Colors.greenAccent, fontSize: 12)),
// //                   ],
// //                 ),
// //               ),
// //             ),
// //           ],
// //         ),
// //       ),
// //     );
// //   }
// //
// //   void _showTopNotification(String m, bool err) {
// //     if (!mounted) return;
// //     OverlayEntry entry = OverlayEntry(builder: (c) => Positioned(
// //         top: 130, left: 20, right: 20,
// //         child: Material(
// //             color: Colors.transparent,
// //             child: Container(
// //                 padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
// //                 decoration: BoxDecoration(color: err ? Colors.redAccent : Colors.green, borderRadius: BorderRadius.circular(30)),
// //                 child: Row(children: [Icon(err ? Icons.error_outline : Icons.check_circle, color: Colors.white), const SizedBox(width: 10), Expanded(child: Text(m, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))])
// //             )
// //         )
// //     ));
// //     Overlay.of(context).insert(entry);
// //     Future.delayed(const Duration(seconds: 2), () => entry.remove());
// //   }
// //
// //   @override
// //   void dispose() {
// //     WidgetsBinding.instance.removeObserver(this);
// //     final camera = _controller;
// //     _controller = null;
// //     if (camera != null) camera.dispose();
// //     _faceDetector.close();
// //     super.dispose();
// //   }
// // }
// //
// //
