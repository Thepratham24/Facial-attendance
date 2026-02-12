import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:intl/intl.dart';
import 'dart:ui';
import 'package:shared_preferences/shared_preferences.dart';

import '../../main.dart';
import '../../services/api_service.dart';
import '../../services/ml_service.dart';
import '../../widgets/face_painter.dart';
import '../Result_StartLogin Side/result_screen.dart';
import 'employee_dashboard.dart';

class EmployeeAttendanceScreen extends StatefulWidget {
  const EmployeeAttendanceScreen({super.key});

  @override
  State<EmployeeAttendanceScreen> createState() => _EmployeeAttendanceScreenState();
}

class _EmployeeAttendanceScreenState extends State<EmployeeAttendanceScreen> with WidgetsBindingObserver {
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

  // 🔴 Force Checkout Toggle State
  bool _isForceCheckoutMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _faceDetector = FaceDetector(options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
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
    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  void _initializeCamera() async {
    if (cameras.isEmpty) return;

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
        if (_canScan && !_isDetecting && !_isNavigating && !_isProcessing) {
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

      if (mounted && !_isProcessing) {
        setState(() => _isProcessing = true);
      }

      List<double> embedding = await _mlService.getEmbedding(image, faces[0]);
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? loggedInName = prefs.getString('emp_name');
      String? loggedInId = prefs.getString('emp_id');
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);

      // 🔴 LOGIC: Choose API based on Toggle State
      Map<String, dynamic> result;
      String currentTime = DateTime.now().toIso8601String();
      if (_isForceCheckoutMode) {
        print("🚀 Calling FORCE CHECKOUT API");
        result = await _apiService.forceCheckOut(
            faceEmbedding: embedding,
            latitude: pos.latitude,
            longitude: pos.longitude,
            isFromAdminPhone: false,
          deviceDate: currentTime,
        );
      } else {
        print("🚀 Calling STANDARD ATTENDANCE API");
        result = await _apiService.markAttendance(
            faceEmbedding: embedding,
            latitude: pos.latitude,
            longitude: pos.longitude,
            isFromAdminPhone: false,
          deviceDate: currentTime,
        );
      }

      bool isSuccess = result['success'] == true;
      String backendMessage = result['message'] ?? "Unknown Response";

      if (isSuccess) {
        _isNavigating = true;
        await _stopCamera();

        var data = result['data'];
        var empData = data['employee'] ?? data;
        String detectedName = empData['name'] ?? loggedInName ?? "Employee";
        String detectedId = empData['_id'] ?? loggedInId ?? "";

        if (mounted) {
          await Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => ResultScreen(name: detectedName, imagePath: "", punchStatus: backendMessage, punchTime: DateFormat('hh:mm a').format(DateTime.now()))));
          if (mounted) {
            Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (c) => EmployeeDashboard(employeeName: detectedName, employeeId: detectedId)), (route) => false);
          }
        }
      } else {
        if (mounted) _showTopNotification(backendMessage, true);
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) setState(() { _isProcessing = false; _isDetecting = false; });
      }
    } catch (e) {
      debugPrint("Error: $e");
      if (mounted) setState(() => _isProcessing = false);
    } finally {
      if (mounted && !_isNavigating && !_isProcessing) _isDetecting = false;
    }
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
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.75), borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 🔴 FORCE CHECKOUT UI
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 18),
                            SizedBox(width: 8),
                            Text("Force Check-out", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                          ],
                        ),
                        Switch(
                          value: _isForceCheckoutMode,
                          activeColor: Colors.orangeAccent,
                          onChanged: (val) {
                            setState(() => _isForceCheckoutMode = val);
                          },
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white12, height: 20),

                    _isProcessing ? const CircularProgressIndicator(color: Colors.white) : const Icon(Icons.face, color: Colors.white, size: 40),
                    const SizedBox(height: 10),
                    Text(
                      _isProcessing ? "Processing Recognition..." : "Face Recognition Active",
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 5),
                    Text(
                        _faces.isEmpty ? "Align face in center" : "Face Detected!",
                        style: TextStyle(color: _faces.isEmpty ? Colors.white54 : Colors.greenAccent, fontSize: 12)
                    ),
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
        top: 60, left: 20, right: 20,
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
    Future.delayed(const Duration(seconds: 3), () => entry.remove());
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




















// import 'dart:async';
// import 'dart:io'; // 🔴 Platform check ke liye zaroori hai
// import 'package:camera/camera.dart';
// import 'package:flutter/foundation.dart'; // WriteBuffer ke liye
// import 'package:flutter/material.dart';
// import 'package:geolocator/geolocator.dart';
// import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
// import 'package:intl/intl.dart';
// import 'dart:ui';
// import 'package:shared_preferences/shared_preferences.dart';
//
// import '../../main.dart';
// import '../../services/api_service.dart';
// import '../../services/ml_service.dart';
// import '../../widgets/face_painter.dart';
// import '../Result_StartLogin Side/result_screen.dart';
// import 'employee_dashboard.dart';
//
// class EmployeeAttendanceScreen extends StatefulWidget {
//   const EmployeeAttendanceScreen({super.key});
//
//   @override
//   State<EmployeeAttendanceScreen> createState() => _EmployeeAttendanceScreenState();
// }
//
// class _EmployeeAttendanceScreenState extends State<EmployeeAttendanceScreen> with WidgetsBindingObserver {
//   final MLService _mlService = MLService();
//   final ApiService _apiService = ApiService();
//
//   CameraController? _controller;
//   // 🔴 Variable to store Camera Details (Sensor Orientation)
//   CameraDescription? _cameraDescription;
//   late FaceDetector _faceDetector;
//   List<Face> _faces = [];
//
//   bool _isNavigating = false;
//   bool _isDetecting = false;
//   bool _isProcessing = false;
//   bool _canScan = false;
//
//   @override
//   void initState() {
//     super.initState();
//     WidgetsBinding.instance.addObserver(this);
//
//     // 🔴 Settings: Fast Mode
//     _faceDetector = FaceDetector(options: FaceDetectorOptions(
//         performanceMode: FaceDetectorMode.fast,
//         enableContours: false,
//         enableClassification: false
//     ));
//
//     _initializeCamera();
//
//     Future.delayed(const Duration(seconds: 2), () {
//       if (mounted) setState(() => _canScan = true);
//     });
//   }
//
//   // 🔴 App Background/Foreground Handle
//   @override
//   void didChangeAppLifecycleState(AppLifecycleState state) {
//     // Agar controller pehle se null hai to kuch mat karo
//     if (_controller == null || !_controller!.value.isInitialized) return;
//
//     if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
//       // 🔴 APP BACKGROUND ME GAYA:
//       // Pehle UI update karo taaki 'CameraPreview' hat jaye aur 'Loader' dikhe
//       if (mounted) {
//         setState(() => _controller = null);
//       }
//       // Phir camera dispose karo
//       _controller?.dispose();
//     }
//     else if (state == AppLifecycleState.resumed) {
//       // 🔴 APP WAPIS AAYA:
//       // Camera dobara start karo
//       _initializeCamera();
//     }
//   }
//
//   void _initializeCamera() async {
//     if (cameras.isEmpty) return;
//
//     if (_controller != null) {
//       await _controller?.dispose();
//     }
//
//     // 🔴 FIX 1: Find Front Camera Dynamically (Har phone me index 1 nahi hota)
//     _cameraDescription = cameras.firstWhere(
//           (camera) => camera.lensDirection == CameraLensDirection.front,
//       orElse: () => cameras.first,
//     );
//
//     _controller = CameraController(
//       _cameraDescription!,
//       ResolutionPreset.medium, // Medium is safe for ML
//       enableAudio: false,
//       imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
//     );
//
//     try {
//       await _controller!.initialize();
//       if (!mounted) return;
//       setState(() {});
//
//       _controller!.startImageStream((image) {
//         if (_canScan && !_isDetecting && !_isNavigating && !_isProcessing) {
//           _doFaceDetection(image);
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
//     if (_isDetecting || _isNavigating || !mounted) return;
//     _isDetecting = true;
//
//     try {
//       // 🔴 Pass Camera Description to helper
//       final inputImage = _inputImageFromCameraImage(image);
//       if (inputImage == null) {
//         _isDetecting = false;
//         return;
//       }
//
//       final faces = await _faceDetector.processImage(inputImage);
//       if (mounted) setState(() => _faces = faces);
//
//       if (faces.isEmpty) {
//         _isDetecting = false;
//         return;
//       }
//
//       if (mounted && !_isProcessing) {
//         setState(() => _isProcessing = true);
//       }
//
//       // Detection Logic Same as before
//       List<double> embedding = await _mlService.getEmbedding(image, faces[0]);
//       SharedPreferences prefs = await SharedPreferences.getInstance();
//       String? loggedInName = prefs.getString('emp_name');
//       String? loggedInId = prefs.getString('emp_id');
//       Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
//
//       Map<String, dynamic> result = await _apiService.markAttendance(
//         faceEmbedding: embedding,
//         latitude: pos.latitude,
//         longitude: pos.longitude,
//         isFromAdminPhone: false
//       );
//
//       bool isSuccess = result['success'] == true;
//       String backendMessage = result['message'] ?? "Unknown Response";
//
//       if (isSuccess) {
//         _isNavigating = true;
//         await _stopCamera();
//
//         var data = result['data'];
//         var empData = data['employee'] ?? data;
//         String detectedName = empData['name'] ?? loggedInName ?? "Employee";
//         String detectedId = empData['_id'] ?? loggedInId ?? "";
//
//         if (mounted) {
//           await Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => ResultScreen(name: detectedName, imagePath: "", punchStatus: backendMessage, punchTime: DateFormat('hh:mm a').format(DateTime.now()))));
//           if (mounted) {
//             Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (c) => EmployeeDashboard(employeeName: detectedName, employeeId: detectedId)), (route) => false);
//           }
//         }
//       }else {
//         if (mounted) _showTopNotification(backendMessage, true);
//         await Future.delayed(const Duration(seconds: 2));
//         if (mounted) setState(() { _isProcessing = false; _isDetecting = false; });
//       }
//     } catch (e) {
//       debugPrint("Error: $e");
//       if (mounted) setState(() => _isProcessing = false);
//     } finally {
//       if (mounted && !_isNavigating && !_isProcessing) _isDetecting = false;
//     }
//   }
//
//   // 🔴 FIX 2: DYNAMIC ROTATION CALCULATION
//   // Ab ye har phone ke hisaab se rotation set karega
//   InputImage? _inputImageFromCameraImage(CameraImage image) {
//     if (_controller == null || _cameraDescription == null) return null;
//
//     // 1. Get Rotation
//     final rotation = InputImageRotationValue.fromRawValue(_cameraDescription!.sensorOrientation);
//     if (rotation == null) return null;
//
//     // 2. Get Format
//     final format = InputImageFormatValue.fromRawValue(image.format.raw);
//
//     // Android par NV21 hona chahiye, iOS par BGRA8888
//     if (format == null || (Platform.isAndroid && format != InputImageFormat.nv21)) return null;
//
//     // 3. Create Bytes (Combine Planes)
//     final WriteBuffer allBytes = WriteBuffer();
//     for (final Plane plane in image.planes) {
//       allBytes.putUint8List(plane.bytes);
//     }
//     final bytes = allBytes.done().buffer.asUint8List();
//
//     // 4. Metadata (🔴 NEW LOGIC: Use InputImageMetadata)
//     final metadata = InputImageMetadata(
//       size: Size(image.width.toDouble(), image.height.toDouble()),
//       rotation: rotation, // Sensor orientation
//       format: format,     // Image format
//       bytesPerRow: image.planes[0].bytesPerRow, // 👈 Ye naye version me zaroori hai
//     );
//
//     return InputImage.fromBytes(bytes: bytes, metadata: metadata);
//   }
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
//             Positioned(
//               top: 50, left: 20,
//               child: IconButton(
//                 icon: const Icon(Icons.arrow_back, color: Colors.white),
//                 onPressed: () => Navigator.pop(context),
//                 style: IconButton.styleFrom(backgroundColor: Colors.black45),
//               ),
//             ),
//
//             Positioned(
//               bottom: 0, left: 0, right: 0,
//               child: Container(
//                 padding: const EdgeInsets.fromLTRB(20, 30, 20, 40),
//                 decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
//                 child: Column(
//                   mainAxisSize: MainAxisSize.min,
//                   children: [
//                     _isProcessing ? const CircularProgressIndicator(color: Colors.white) : const Icon(Icons.face, color: Colors.white, size: 40),
//                     const SizedBox(height: 15),
//                     Text(
//                       _isProcessing ? "Processing..." : "Face Recognition Active",
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
//         top: 60, left: 20, right: 20,
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
//     Future.delayed(const Duration(seconds: 3), () => entry.remove());
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
// // import 'package:camera/camera.dart';
// // import 'package:flutter/material.dart';
// // import 'package:geolocator/geolocator.dart';
// // import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
// // import 'package:intl/intl.dart';
// // import 'dart:ui';
// // import 'package:shared_preferences/shared_preferences.dart';
// //
// // import '../../main.dart';
// // import '../../services/api_service.dart';
// // import '../../services/ml_service.dart';
// // import '../../widgets/face_painter.dart';
// // import '../Result_StartLogin Side/result_screen.dart';
// // import 'employee_dashboard.dart';
// //
// // class EmployeeAttendanceScreen extends StatefulWidget {
// //   const EmployeeAttendanceScreen({super.key});
// //
// //   @override
// //   State<EmployeeAttendanceScreen> createState() => _EmployeeAttendanceScreenState();
// // }
// //
// // class _EmployeeAttendanceScreenState extends State<EmployeeAttendanceScreen> with WidgetsBindingObserver {
// //   final MLService _mlService = MLService();
// //   final ApiService _apiService = ApiService();
// //
// //   CameraController? _controller;
// //   late FaceDetector _faceDetector;
// //   List<Face> _faces = [];
// //
// //   bool _isNavigating = false;
// //   bool _isDetecting = false;
// //   bool _isProcessing = false;
// //   bool _canScan = false;
// //
// //   @override
// //   void initState() {
// //     super.initState();
// //     WidgetsBinding.instance.addObserver(this);
// //     _faceDetector = FaceDetector(options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast));
// //     _initializeCamera();
// //
// //     Future.delayed(const Duration(seconds: 2), () {
// //       if (mounted) setState(() => _canScan = true);
// //     });
// //   }
// //
// //   void _initializeCamera() async {
// //     if (cameras.isEmpty) return;
// //     if (_controller != null) await _controller!.dispose();
// //
// //     CameraController newController = CameraController(
// //       cameras[1],
// //       ResolutionPreset.medium,
// //       enableAudio: false,
// //       imageFormatGroup: ImageFormatGroup.yuv420,
// //     );
// //
// //     try {
// //       await newController.initialize();
// //       if (!mounted) return;
// //       setState(() => _controller = newController);
// //       newController.startImageStream((image) {
// //         if (_canScan && !_isDetecting && !_isNavigating && !_isProcessing) {
// //           _doFaceDetection(image);
// //         }
// //       });
// //     } catch (e) {
// //       debugPrint("Camera Error: $e");
// //     }
// //   }
// //
// //   // 🔴 FIX: Safe Camera Stop (Logic Update)
// //   Future<void> _stopCamera() async {
// //     if (_controller == null) return;
// //     final oldController = _controller;
// //     _controller = null;
// //
// //     // Sirf tab setState karo jab widget active ho
// //     if (mounted) setState(() {});
// //
// //     try {
// //       if (oldController!.value.isStreamingImages) await oldController.stopImageStream();
// //       await oldController.dispose();
// //     } catch (e) {
// //       debugPrint("Stop Error: $e");
// //     }
// //   }
// //
// //   Future<void> _doFaceDetection(CameraImage image) async {
// //     if (_isDetecting || _isNavigating || !mounted) return;
// //     _isDetecting = true;
// //
// //     try {
// //       final inputImage = _convertCameraImage(image);
// //       if (inputImage == null) return;
// //
// //       final faces = await _faceDetector.processImage(inputImage);
// //       if (mounted) setState(() => _faces = faces);
// //
// //       if (faces.isEmpty) {
// //         _isDetecting = false;
// //         return;
// //       }
// //
// //       if (mounted && !_isProcessing) {
// //         setState(() => _isProcessing = true);
// //       }
// //
// //       List<double> embedding = await _mlService.getEmbedding(image, faces[0]);
// //
// //       SharedPreferences prefs = await SharedPreferences.getInstance();
// //       String? loggedInName = prefs.getString('emp_name');
// //       String? loggedInId = prefs.getString('emp_id');
// //
// //       Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
// //       Map<String, dynamic> result = await _apiService.markAttendance(
// //         faceEmbedding: embedding,
// //         latitude: pos.latitude,
// //         longitude: pos.longitude,
// //         accuracy: pos.accuracy,
// //       );
// //
// //       bool isSuccess = result['success'] == true;
// //       String backendMessage = result['message'] ?? "Unknown Response";
// //
// //       if (isSuccess) {
// //         _isNavigating = true;
// //         await _stopCamera(); // Normal flow mein safe hai
// //
// //         String detectedName = "Employee";
// //         String detectedId = "";
// //
// //         if (result['data'] != null) {
// //           var data = result['data'];
// //           var empData = data['employee'] ?? data;
// //           detectedName = empData['name'] ?? "Employee";
// //           detectedId = empData['_id'] ?? "";
// //         }
// //
// //         if (!mounted) return;
// //
// //         await Navigator.pushReplacement(
// //           context,
// //           MaterialPageRoute(builder: (context) => ResultScreen(
// //               name: detectedName,
// //               imagePath: "",
// //               punchStatus: backendMessage,
// //               punchTime: DateFormat('hh:mm a').format(DateTime.now())
// //           )),
// //         );
// //
// //         String finalId = loggedInId ?? detectedId;
// //         String finalName = loggedInName ?? detectedName;
// //
// //         if (mounted) {
// //           Navigator.pushAndRemoveUntil(
// //               context,
// //               MaterialPageRoute(builder: (c) => EmployeeDashboard(
// //                 employeeName: finalName,
// //                 employeeId: finalId,
// //               )),
// //                   (route) => false
// //           );
// //         }
// //
// //       } else {
// //         if (mounted) _showTopNotification(backendMessage, true);
// //         await Future.delayed(const Duration(seconds: 2));
// //         if (mounted) {
// //           setState(() {
// //             _isProcessing = false;
// //             _isDetecting = false;
// //           });
// //         }
// //       }
// //     } catch (e) {
// //       debugPrint("Error: $e");
// //       if (mounted) setState(() => _isProcessing = false);
// //     } finally {
// //       if (mounted && !_isNavigating && !_isProcessing) _isDetecting = false;
// //     }
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
// //             Positioned(
// //               top: 50, left: 20,
// //               child: IconButton(
// //                 icon: const Icon(Icons.arrow_back, color: Colors.white),
// //                 onPressed: () => Navigator.pop(context),
// //                 style: IconButton.styleFrom(backgroundColor: Colors.black45),
// //               ),
// //             ),
// //
// //             Positioned(
// //               bottom: 0, left: 0, right: 0,
// //               child: Container(
// //                 padding: const EdgeInsets.fromLTRB(20, 30, 20, 40),
// //                 decoration: BoxDecoration(
// //                     color: Colors.black.withOpacity(0.7),
// //                     borderRadius: const BorderRadius.vertical(top: Radius.circular(30))
// //                 ),
// //                 child: Column(
// //                   mainAxisSize: MainAxisSize.min,
// //                   children: [
// //                     _isProcessing ? const CircularProgressIndicator(color: Colors.white) : const Icon(Icons.face, color: Colors.white, size: 40),
// //                     const SizedBox(height: 15),
// //                     Text(
// //                       _isProcessing ? "Processing..." : "Face Recognition Active",
// //                       style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
// //                     ),
// //                     const SizedBox(height: 5),
// //                     const Text("Attendance will be marked for the detected face", style: TextStyle(color: Colors.white54, fontSize: 12)),
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
// //   InputImage? _convertCameraImage(CameraImage image) {
// //     try {
// //       return InputImage.fromBytes(
// //           bytes: _mlService.concatenatePlanes(image.planes),
// //           metadata: InputImageMetadata(
// //               size: Size(image.width.toDouble(), image.height.toDouble()),
// //               rotation: InputImageRotation.rotation270deg,
// //               format: InputImageFormat.nv21,
// //               bytesPerRow: image.planes[0].bytesPerRow
// //           )
// //       );
// //     } catch (_) { return null; }
// //   }
// //
// //   void _showTopNotification(String m, bool err) {
// //     if (!mounted) return;
// //     OverlayEntry entry = OverlayEntry(builder: (c) => Positioned(
// //         top: 60, left: 20, right: 20,
// //         child: Material(
// //             color: Colors.transparent,
// //             child: Container(
// //                 padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
// //                 decoration: BoxDecoration(color: err ? Colors.redAccent : Colors.green, borderRadius: BorderRadius.circular(30)),
// //                 child: Row(
// //                   children: [
// //                     Icon(err ? Icons.error_outline : Icons.check_circle, color: Colors.white),
// //                     const SizedBox(width: 10),
// //                     Expanded(child: Text(m, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
// //                   ],
// //                 )
// //             )
// //         )
// //     ));
// //     Overlay.of(context).insert(entry);
// //     Future.delayed(const Duration(seconds: 3), () => entry.remove());
// //   }
// //
// //   // 🔴 FIX: Updated Dispose Logic
// //   @override
// //   void dispose() {
// //     WidgetsBinding.instance.removeObserver(this);
// //
// //     // Directly dispose controller without calling setState (Crash Prevention)
// //     final camera = _controller;
// //     _controller = null;
// //     if (camera != null) {
// //       camera.dispose();
// //     }
// //
// //     _faceDetector.close();
// //     super.dispose();
// //   }
// // }