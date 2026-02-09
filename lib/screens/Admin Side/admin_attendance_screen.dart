import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:face_attendance/screens/Admin%20Side/admin_dashboard_screen.dart';
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

class AdminAttendanceScreen extends StatefulWidget {
  const AdminAttendanceScreen({super.key});

  @override
  State<AdminAttendanceScreen> createState() => _AdminAttendanceScreenState();
}

class _AdminAttendanceScreenState extends State<AdminAttendanceScreen> with WidgetsBindingObserver {
  final MLService _mlService = MLService();
  final ApiService _apiService = ApiService();

  CameraController? _controller;
  late FaceDetector _faceDetector;
  List<Face> _faces = [];

  bool _isNavigating = false;
  bool _isDetecting = false;
  bool _isProcessing = false;
  bool _canScan = false;

  // 🔴 NEW FLAG FOR FORCE CHECKOUT
  bool _isForceCheckout = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _faceDetector = FaceDetector(options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast));

    _initializeCamera();

    // Thoda delay taaki camera settle ho jaye
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _canScan = true);
    });
  }

  // 🔴 LIFECYCLE HANDLE
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _controller;

    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      _stopCamera();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  void _initializeCamera() async {
    if (cameras.isEmpty) return;

    if (_controller != null) {
      await _stopCamera();
    }

    CameraDescription selectedCamera = cameras[0];
    for (var camera in cameras) {
      if (camera.lensDirection == CameraLensDirection.front) {
        selectedCamera = camera;
        break;
      }
    }

    CameraController newController = CameraController(
      selectedCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );

    try {
      await newController.initialize();
      if (!mounted) return;

      setState(() => _controller = newController);

      newController.startImageStream((image) {
        if (_canScan && !_isDetecting && !_isNavigating && !_isProcessing) {
          _doFaceDetection(image);
        }
      });
    } catch (e) {
      debugPrint("Camera Init Error: $e");
    }
  }

  Future<void> _stopCamera() async {
    final oldController = _controller;

    if (mounted) {
      setState(() {
        _controller = null;
      });
    }

    if (oldController != null) {
      try {
        if (oldController.value.isStreamingImages) {
          await oldController.stopImageStream();
        }
        await oldController.dispose();
      } catch (e) {
        debugPrint("Dispose Error: $e");
      }
    }
  }

  Future<void> _doFaceDetection(CameraImage image) async {
    if (_isDetecting || _isNavigating || !mounted) return;
    _isDetecting = true;

    try {
      final inputImage = _convertCameraImage(image);
      if (inputImage == null) return;

      final faces = await _faceDetector.processImage(inputImage);
      if (mounted) setState(() => _faces = faces);

      if (faces.isEmpty) {
        _isDetecting = false;
        return;
      }

      // Internet Check
      try {
        final result = await InternetAddress.lookup('google.com');
        if (result.isEmpty || result[0].rawAddress.isEmpty) {
          throw SocketException("No Internet");
        }
      } on SocketException {
        if (mounted && !_isNavigating) {
          _showTopNotification("No Internet Connection", true);
        }
        _isDetecting = false;
        return;
      }

      if (mounted && !_isProcessing) {
        setState(() => _isProcessing = true);
      }

      List<double> embedding = await _mlService.getEmbedding(image, faces[0]);
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);

      // 🔴🔴🔴 LOGIC CHANGED HERE FOR FLAG 🔴🔴🔴
      Map<String, dynamic> result;

      if (_isForceCheckout) {
        // CALL FORCE CHECKOUT API
        print("🚀 Calling Force CheckOut API...");
        result = await _apiService.forceCheckOut(
          faceEmbedding: embedding,
          latitude: pos.latitude,
          longitude: pos.longitude,
          isFromAdminPhone: true,
        );
      } else {
        // NORMAL ATTENDANCE
        result = await _apiService.markAttendance(
          faceEmbedding: embedding,
          latitude: pos.latitude,
          longitude: pos.longitude,
          isFromAdminPhone: true,
        );
      }

      bool isSuccess = result['success'] == true;
      String backendMessage = result['message'] ?? "Unknown Response";

      if (isSuccess) {
        _isNavigating = true;
        await _stopCamera();

        String detectedName = "Employee";
        if (result['data'] != null) {
          var data = result['data'];
          var empData = data['employee'] ?? data; // Handle structure variations
          detectedName = empData['name'] ?? "Employee";
        }

        if (!mounted) return;

        // Result Screen
        await Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => ResultScreen(
              name: detectedName,
              imagePath: "",
              punchStatus: backendMessage, // Backend Message Displayed
              punchTime: DateFormat('hh:mm a').format(DateTime.now())
          )),
        );

        if (mounted) {
          Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (c) => const AdminDashboard()),
                  (route) => false
          );
        }

      } else {
        if (mounted) _showTopNotification(backendMessage, true);

        await Future.delayed(const Duration(seconds: 2));

        if (mounted) {
          setState(() {
            _isProcessing = false;
            _isDetecting = false;
          });
        }
      }
    } catch (e) {
      debugPrint("Error: $e");
      if (mounted) {
        setState(() => _isProcessing = false);
        _showTopNotification("Scan Failed. Try Again.", true);
      }
    } finally {
      if (mounted && !_isNavigating && !_isProcessing) _isDetecting = false;
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
                    child: CameraPreview(
                        _controller!,
                        child: CustomPaint(
                            painter: FacePainter(
                                faces: _faces,
                                imageSize: _controller!.value.previewSize!
                            )
                        )
                    ),
                  ),
                ),
              )
            else
              const Center(child: CircularProgressIndicator(color: Colors.white)),

            // Back Button (Top Left)
            Positioned(
              top: 50, left: 20,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
                style: IconButton.styleFrom(backgroundColor: Colors.black45),
              ),
            ),

            // 🔴 FORCE CHECKOUT TOGGLE (Top Right)
            Positioned(
              top: 50, right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(30),
                  border: _isForceCheckout ? Border.all(color: Colors.redAccent, width: 2) : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Force Out",
                      style: TextStyle(
                          color: _isForceCheckout ? Colors.redAccent : Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12
                      ),
                    ),
                    const SizedBox(width: 5),
                    Transform.scale(
                      scale: 0.8,
                      child: Switch(
                        value: _isForceCheckout,
                        activeColor: Colors.red,
                        activeTrackColor: Colors.red.withOpacity(0.3),
                        inactiveThumbColor: Colors.white,
                        inactiveTrackColor: Colors.grey,
                        onChanged: (val) {
                          setState(() => _isForceCheckout = val);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Bottom Status Bar
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 30, 20, 40),
                decoration: BoxDecoration(
                    color: _isForceCheckout
                        ? Colors.red.withOpacity(0.8) // Red background if Force Checkout is ON
                        : Colors.black.withOpacity(0.7),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(30))
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _isProcessing
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Icon(_isForceCheckout ? Icons.logout : Icons.face, color: Colors.white, size: 40),
                    const SizedBox(height: 15),
                    Text(
                      _isProcessing
                          ? "Processing..."
                          : (_isForceCheckout ? "FORCE CHECK-OUT MODE" : "Face Recognition Active"),
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 5),
                    Text(
                        _isForceCheckout
                            ? "Caution: This will force mark attendance as OUT"
                            : "Attendance will be marked for the detected face",
                        style: const TextStyle(color: Colors.white70, fontSize: 12)
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
                child: Row(
                  children: [
                    Icon(err ? Icons.error_outline : Icons.check_circle, color: Colors.white),
                    const SizedBox(width: 10),
                    Expanded(child: Text(m, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                  ],
                )
            )
        )
    ));
    Overlay.of(context).insert(entry);
    Future.delayed(const Duration(seconds: 3), () => entry.remove());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _faceDetector.close();
    super.dispose();
  }
}


















// import 'dart:async';
// import 'dart:io';
// import 'package:camera/camera.dart';
// import 'package:face_attendance/screens/Admin%20Side/admin_dashboard_screen.dart';
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
//     _faceDetector = FaceDetector(options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast));
//
//     _initializeCamera();
//
//     // Thoda delay taaki camera settle ho jaye
//     Future.delayed(const Duration(seconds: 2), () {
//       if (mounted) setState(() => _canScan = true);
//     });
//   }
//
//   // 🔴 LIFECYCLE HANDLE (App Minimize/Resume Fix)
//   @override
//   void didChangeAppLifecycleState(AppLifecycleState state) {
//     final CameraController? cameraController = _controller;
//
//     // App background me gaya ya inactive hua -> Camera band karo
//     if (cameraController == null || !cameraController.value.isInitialized) {
//       return;
//     }
//
//     if (state == AppLifecycleState.inactive) {
//       _stopCamera(); // Safe stop
//     } else if (state == AppLifecycleState.resumed) {
//       _initializeCamera(); // Wapis aaya to start karo
//     }
//   }
//
//   void _initializeCamera() async {
//     if (cameras.isEmpty) return;
//
//     // 1. Purana Controller Hatayo UI se
//     if (_controller != null) {
//       await _stopCamera();
//     }
//
//     // 2. Front Camera Dhundo
//     CameraDescription selectedCamera = cameras[0];
//     for (var camera in cameras) {
//       if (camera.lensDirection == CameraLensDirection.front) {
//         selectedCamera = camera;
//         break;
//       }
//     }
//
//     // 3. Naya Controller Banao
//     CameraController newController = CameraController(
//       selectedCamera,
//       ResolutionPreset.medium,
//       enableAudio: false,
//       imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
//     );
//
//     try {
//       await newController.initialize();
//       if (!mounted) return;
//
//       setState(() => _controller = newController);
//
//       newController.startImageStream((image) {
//         if (_canScan && !_isDetecting && !_isNavigating && !_isProcessing) {
//           _doFaceDetection(image);
//         }
//       });
//     } catch (e) {
//       debugPrint("Camera Init Error: $e");
//     }
//   }
//
//   // 🔴 FIX: Safe Camera Stop (UI se pehle hatao, fir dispose karo)
//   Future<void> _stopCamera() async {
//     final oldController = _controller;
//
//     // Step 1: UI Update (CameraPreview Hatao)
//     if (mounted) {
//       setState(() {
//         _controller = null;
//       });
//     }
//
//     // Step 2: Background Dispose
//     if (oldController != null) {
//       try {
//         // Stream roko agar chal rahi ho
//         if (oldController.value.isStreamingImages) {
//           await oldController.stopImageStream();
//         }
//         await oldController.dispose();
//       } catch (e) {
//         debugPrint("Dispose Error: $e");
//       }
//     }
//   }
//
//   Future<void> _doFaceDetection(CameraImage image) async {
//     if (_isDetecting || _isNavigating || !mounted) return;
//     _isDetecting = true;
//
//     try {
//       final inputImage = _convertCameraImage(image);
//       if (inputImage == null) return;
//
//       final faces = await _faceDetector.processImage(inputImage);
//       if (mounted) setState(() => _faces = faces);
//
//       if (faces.isEmpty) {
//         _isDetecting = false;
//         return;
//       }
//
//       // 🔴 Internet Check
//       try {
//         final result = await InternetAddress.lookup('google.com');
//         if (result.isEmpty || result[0].rawAddress.isEmpty) {
//           throw SocketException("No Internet");
//         }
//       } on SocketException {
//         if (mounted && !_isNavigating) {
//           _showTopNotification("No Internet Connection", true);
//         }
//         _isDetecting = false;
//         return;
//       }
//
//       if (mounted && !_isProcessing) {
//         setState(() => _isProcessing = true);
//       }
//
//       // Embedding Generation
//       List<double> embedding = await _mlService.getEmbedding(image, faces[0]);
//
//       // Get Data
//       SharedPreferences prefs = await SharedPreferences.getInstance();
//       String? loggedInName = prefs.getString('emp_name');
//       String? loggedInId = prefs.getString('emp_id');
//
//       // Get Location
//       Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
//
//       // API Call
//       Map<String, dynamic> result = await _apiService.markAttendance(
//         faceEmbedding: embedding,
//         latitude: pos.latitude,
//         longitude: pos.longitude,
//         isFromAdminPhone: true,
//       );
//
//       bool isSuccess = result['success'] == true;
//       String backendMessage = result['message'] ?? "Unknown Response";
//
//       if (isSuccess) {
//         _isNavigating = true;
//
//         // 🔴 Camera Safe Stop call karo
//         await _stopCamera();
//
//         String detectedName = "Employee";
//         if (result['data'] != null) {
//           var data = result['data'];
//           var empData = data['employee'] ?? data;
//           detectedName = empData['name'] ?? "Employee";
//         }
//
//         if (!mounted) return;
//
//         // Result Screen par jao
//         await Navigator.pushReplacement(
//           context,
//           MaterialPageRoute(builder: (context) => ResultScreen(
//               name: detectedName,
//               imagePath: "",
//               punchStatus: backendMessage,
//               punchTime: DateFormat('hh:mm a').format(DateTime.now())
//           )),
//         );
//
//         if (mounted) {
//           Navigator.pushAndRemoveUntil(
//               context,
//               MaterialPageRoute(builder: (c) => const AdminDashboard()),
//                   (route) => false
//           );
//         }
//
//       } else {
//         if (mounted) _showTopNotification(backendMessage, true);
//
//         // Thoda wait karo error padhne ke liye
//         await Future.delayed(const Duration(seconds: 2));
//
//         if (mounted) {
//           setState(() {
//             _isProcessing = false;
//             _isDetecting = false;
//           });
//         }
//       }
//     } catch (e) {
//       debugPrint("Error: $e");
//       if (mounted) {
//         setState(() => _isProcessing = false);
//         _showTopNotification("Scan Failed. Try Again.", true);
//       }
//     } finally {
//       if (mounted && !_isNavigating && !_isProcessing) _isDetecting = false;
//     }
//   }
//
//   InputImage? _convertCameraImage(CameraImage image) {
//     if (_controller == null) return null;
//     try {
//       final camera = _controller!.description;
//       final sensorOrientation = camera.sensorOrientation;
//       InputImageRotation rotation = InputImageRotation.rotation0deg;
//
//       if (Platform.isAndroid) {
//         var rotationCompensation = (sensorOrientation + 0) % 360;
//         rotation = InputImageRotationValue.fromRawValue(rotationCompensation) ?? InputImageRotation.rotation270deg;
//       }
//
//       return InputImage.fromBytes(
//           bytes: _mlService.concatenatePlanes(image.planes),
//           metadata: InputImageMetadata(
//               size: Size(image.width.toDouble(), image.height.toDouble()),
//               rotation: rotation,
//               format: Platform.isAndroid ? InputImageFormat.nv21 : InputImageFormat.bgra8888,
//               bytesPerRow: image.planes[0].bytesPerRow
//           )
//       );
//     } catch (_) { return null; }
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
//             // 🔴 Safe Check: Initialize check + Navigating check
//             if (_controller != null && _controller!.value.isInitialized && !_isNavigating)
//               SizedBox.expand(
//                 child: FittedBox(
//                   fit: BoxFit.cover,
//                   child: SizedBox(
//                     width: _controller!.value.previewSize!.height,
//                     height: _controller!.value.previewSize!.width,
//                     child: CameraPreview(
//                         _controller!,
//                         child: CustomPaint(
//                             painter: FacePainter(
//                                 faces: _faces,
//                                 imageSize: _controller!.value.previewSize!
//                             )
//                         )
//                     ),
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
//                 decoration: BoxDecoration(
//                     color: Colors.black.withOpacity(0.7),
//                     borderRadius: const BorderRadius.vertical(top: Radius.circular(30))
//                 ),
//                 child: Column(
//                   mainAxisSize: MainAxisSize.min,
//                   children: [
//                     _isProcessing
//                         ? const CircularProgressIndicator(color: Colors.white)
//                         : const Icon(Icons.face, color: Colors.white, size: 40),
//                     const SizedBox(height: 15),
//                     Text(
//                       _isProcessing ? "Processing..." : "Face Recognition Active",
//                       style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
//                     ),
//                     const SizedBox(height: 5),
//                     const Text("Attendance will be marked for the detected face", style: TextStyle(color: Colors.white54, fontSize: 12)),
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
//                 child: Row(
//                   children: [
//                     Icon(err ? Icons.error_outline : Icons.check_circle, color: Colors.white),
//                     const SizedBox(width: 10),
//                     Expanded(child: Text(m, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
//                   ],
//                 )
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
//     // Dispose logic handle in Stop Camera mainly
//     _controller?.dispose();
//     _faceDetector.close();
//     super.dispose();
//   }
//
//
//
//
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
// // import 'dart:async';
// // import 'dart:io'; // 🔴 Added for Internet Check
// // import 'package:camera/camera.dart';
// // import 'package:face_attendance/screens/Admin%20Side/admin_dashboard_screen.dart';
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
// //   // 🔴 FIX 1: Safe Camera Initialization
// //   void _initializeCamera() async {
// //     if (cameras.isEmpty) return;
// //     if (_controller != null) await _controller!.dispose();
// //
// //     // Smartly find Front Camera
// //     CameraDescription selectedCamera = cameras[0];
// //     for (var camera in cameras) {
// //       if (camera.lensDirection == CameraLensDirection.front) {
// //         selectedCamera = camera;
// //         break;
// //       }
// //     }
// //
// //     CameraController newController = CameraController(
// //       selectedCamera, // 🔴 No hardcoded index
// //       ResolutionPreset.medium,
// //       enableAudio: false,
// //       imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
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
// //   Future<void> _stopCamera() async {
// //     if (_controller == null) return;
// //     final oldController = _controller;
// //     _controller = null; // UI ko turant batao camera band hai
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
// //       // Check Internet Connection First
// //       try {
// //         final result = await InternetAddress.lookup('google.com');
// //         if (result.isEmpty || result[0].rawAddress.isEmpty) {
// //           throw SocketException("No Internet");
// //         }
// //       } on SocketException {
// //         if (mounted) _showTopNotification("No Internet Connection", true);
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
// //
// //       Map<String, dynamic> result = await _apiService.markAttendance(
// //         faceEmbedding: embedding,
// //         latitude: pos.latitude,
// //         longitude: pos.longitude,
// //         isFromAdminPhone: true,
// //       );
// //
// //       bool isSuccess = result['success'] == true;
// //       String backendMessage = result['message'] ?? "Unknown Response";
// //
// //       if (isSuccess) {
// //         _isNavigating = true;
// //         await _stopCamera();
// //
// //         String detectedName = "Employee";
// //
// //         if (result['data'] != null) {
// //           var data = result['data'];
// //           var empData = data['employee'] ?? data;
// //           detectedName = empData['name'] ?? "Employee";
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
// //         if (mounted) {
// //           Navigator.pushAndRemoveUntil(
// //               context,
// //               MaterialPageRoute(builder: (c) => AdminDashboard()),
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
// //       if (mounted) {
// //         setState(() => _isProcessing = false);
// //         // User ko error dikhana zaroori hai
// //         _showTopNotification("Scan Failed. Try Again.", true);
// //       }
// //     } finally {
// //       if (mounted && !_isNavigating && !_isProcessing) _isDetecting = false;
// //     }
// //   }
// //
// //   // 🔴 FIX 2: Dynamic Rotation Logic
// //   InputImage? _convertCameraImage(CameraImage image) {
// //     if (_controller == null) return null;
// //     try {
// //       final camera = _controller!.description;
// //       final sensorOrientation = camera.sensorOrientation;
// //       InputImageRotation rotation = InputImageRotation.rotation0deg;
// //
// //       if (Platform.isAndroid) {
// //         var rotationCompensation = (sensorOrientation + 0) % 360;
// //         rotation = InputImageRotationValue.fromRawValue(rotationCompensation)
// //             ?? InputImageRotation.rotation270deg;
// //       }
// //
// //       return InputImage.fromBytes(
// //           bytes: _mlService.concatenatePlanes(image.planes),
// //           metadata: InputImageMetadata(
// //               size: Size(image.width.toDouble(), image.height.toDouble()),
// //               rotation: rotation, // 🔴 Dynamic
// //               format: InputImageFormat.nv21,
// //               bytesPerRow: image.planes[0].bytesPerRow
// //           )
// //       );
// //     } catch (_) { return null; }
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
// //   @override
// //   void dispose() {
// //     WidgetsBinding.instance.removeObserver(this);
// //     final camera = _controller;
// //     _controller = null;
// //     if (camera != null) {
// //       camera.dispose();
// //     }
// //     _faceDetector.close();
// //     super.dispose();
// //   }
// // }
// //
// //
// //
// //
// //
// //
// //
// //
// //
// //
// //
// //
// //
// // // import 'dart:async';
// // // import 'package:camera/camera.dart';
// // // import 'package:face_attendance/screens/Admin%20Side/admin_dashboard_screen.dart';
// // // import 'package:flutter/material.dart';
// // // import 'package:geolocator/geolocator.dart';
// // // import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
// // // import 'package:intl/intl.dart';
// // // import 'dart:ui';
// // // import 'package:shared_preferences/shared_preferences.dart';
// // //
// // // import '../../main.dart';
// // // import '../../services/api_service.dart';
// // // import '../../services/ml_service.dart';
// // // import '../../widgets/face_painter.dart';
// // // import '../Result_StartLogin Side/result_screen.dart';
// // //
// // //
// // // class AdminAttendanceScreen extends StatefulWidget {
// // //   const AdminAttendanceScreen({super.key});
// // //
// // //   @override
// // //   State<AdminAttendanceScreen> createState() => _AdminAttendanceScreenState();
// // // }
// // //
// // // class _AdminAttendanceScreenState extends State<AdminAttendanceScreen> with WidgetsBindingObserver {
// // //   final MLService _mlService = MLService();
// // //   final ApiService _apiService = ApiService();
// // //
// // //   CameraController? _controller;
// // //   late FaceDetector _faceDetector;
// // //   List<Face> _faces = [];
// // //
// // //   bool _isNavigating = false;
// // //   bool _isDetecting = false;
// // //   bool _isProcessing = false;
// // //   bool _canScan = false;
// // //
// // //   @override
// // //   void initState() {
// // //     super.initState();
// // //     WidgetsBinding.instance.addObserver(this);
// // //     _faceDetector = FaceDetector(options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast));
// // //     _initializeCamera();
// // //
// // //     Future.delayed(const Duration(seconds: 2), () {
// // //       if (mounted) setState(() => _canScan = true);
// // //     });
// // //   }
// // //
// // //   void _initializeCamera() async {
// // //     if (cameras.isEmpty) return;
// // //     if (_controller != null) await _controller!.dispose();
// // //
// // //     CameraController newController = CameraController(
// // //       cameras[1],
// // //       ResolutionPreset.medium,
// // //       enableAudio: false,
// // //       imageFormatGroup: ImageFormatGroup.yuv420,
// // //     );
// // //
// // //     try {
// // //       await newController.initialize();
// // //       if (!mounted) return;
// // //       setState(() => _controller = newController);
// // //       newController.startImageStream((image) {
// // //         if (_canScan && !_isDetecting && !_isNavigating && !_isProcessing) {
// // //           _doFaceDetection(image);
// // //         }
// // //       });
// // //     } catch (e) {
// // //       debugPrint("Camera Error: $e");
// // //     }
// // //   }
// // //
// // //   // 🔴 FIX: Safe Camera Stop (Logic Update)
// // //   Future<void> _stopCamera() async {
// // //     if (_controller == null) return;
// // //     final oldController = _controller;
// // //     _controller = null;
// // //
// // //     // Sirf tab setState karo jab widget active ho
// // //     if (mounted) setState(() {});
// // //
// // //     try {
// // //       if (oldController!.value.isStreamingImages) await oldController.stopImageStream();
// // //       await oldController.dispose();
// // //     } catch (e) {
// // //       debugPrint("Stop Error: $e");
// // //     }
// // //   }
// // //
// // //   Future<void> _doFaceDetection(CameraImage image) async {
// // //     if (_isDetecting || _isNavigating || !mounted) return;
// // //     _isDetecting = true;
// // //
// // //     try {
// // //       final inputImage = _convertCameraImage(image);
// // //       if (inputImage == null) return;
// // //
// // //       final faces = await _faceDetector.processImage(inputImage);
// // //       if (mounted) setState(() => _faces = faces);
// // //
// // //       if (faces.isEmpty) {
// // //         _isDetecting = false;
// // //         return;
// // //       }
// // //
// // //       if (mounted && !_isProcessing) {
// // //         setState(() => _isProcessing = true);
// // //       }
// // //
// // //       List<double> embedding = await _mlService.getEmbedding(image, faces[0]);
// // //
// // //       SharedPreferences prefs = await SharedPreferences.getInstance();
// // //       String? loggedInName = prefs.getString('emp_name');
// // //       String? loggedInId = prefs.getString('emp_id');
// // //
// // //       Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
// // //       Map<String, dynamic> result = await _apiService.markAttendance(
// // //         faceEmbedding: embedding,
// // //         latitude: pos.latitude,
// // //         longitude: pos.longitude,
// // //         accuracy: pos.accuracy,
// // //         isFromAdminPhone: true,
// // //       );
// // //
// // //       bool isSuccess = result['success'] == true;
// // //       String backendMessage = result['message'] ?? "Unknown Response";
// // //
// // //       if (isSuccess) {
// // //         _isNavigating = true;
// // //         await _stopCamera(); // Normal flow mein safe hai
// // //
// // //         String detectedName = "Employee";
// // //         String detectedId = "";
// // //
// // //         if (result['data'] != null) {
// // //           var data = result['data'];
// // //           var empData = data['employee'] ?? data;
// // //           detectedName = empData['name'] ?? "Employee";
// // //           detectedId = empData['_id'] ?? "";
// // //         }
// // //
// // //         if (!mounted) return;
// // //
// // //         await Navigator.pushReplacement(
// // //           context,
// // //           MaterialPageRoute(builder: (context) => ResultScreen(
// // //               name: detectedName,
// // //               imagePath: "",
// // //               punchStatus: backendMessage,
// // //               punchTime: DateFormat('hh:mm a').format(DateTime.now())
// // //           )),
// // //         );
// // //
// // //         String finalId = loggedInId ?? detectedId;
// // //         String finalName = loggedInName ?? detectedName;
// // //
// // //         if (mounted) {
// // //           Navigator.pushAndRemoveUntil(
// // //               context,
// // //               MaterialPageRoute(builder: (c) => AdminDashboard(
// // //               )),
// // //                   (route) => false
// // //           );
// // //         }
// // //
// // //       } else {
// // //         if (mounted) _showTopNotification(backendMessage, true);
// // //         await Future.delayed(const Duration(seconds: 2));
// // //         if (mounted) {
// // //           setState(() {
// // //             _isProcessing = false;
// // //             _isDetecting = false;
// // //           });
// // //         }
// // //       }
// // //     } catch (e) {
// // //       debugPrint("Error: $e");
// // //       if (mounted) setState(() => _isProcessing = false);
// // //     } finally {
// // //       if (mounted && !_isNavigating && !_isProcessing) _isDetecting = false;
// // //     }
// // //   }
// // //
// // //   @override
// // //   Widget build(BuildContext context) {
// // //     return PopScope(
// // //       canPop: false,
// // //       onPopInvokedWithResult: (didPop, result) {
// // //         if (didPop) return;
// // //         Navigator.pop(context);
// // //       },
// // //       child: Scaffold(
// // //         backgroundColor: Colors.black,
// // //         body: Stack(
// // //           children: [
// // //             if (_controller != null && _controller!.value.isInitialized && !_isNavigating)
// // //               SizedBox.expand(
// // //                 child: FittedBox(
// // //                   fit: BoxFit.cover,
// // //                   child: SizedBox(
// // //                     width: _controller!.value.previewSize!.height,
// // //                     height: _controller!.value.previewSize!.width,
// // //                     child: CameraPreview(_controller!, child: CustomPaint(painter: FacePainter(faces: _faces, imageSize: _controller!.value.previewSize!))),
// // //                   ),
// // //                 ),
// // //               )
// // //             else
// // //               const Center(child: CircularProgressIndicator(color: Colors.white)),
// // //
// // //             Positioned(
// // //               top: 50, left: 20,
// // //               child: IconButton(
// // //                 icon: const Icon(Icons.arrow_back, color: Colors.white),
// // //                 onPressed: () => Navigator.pop(context),
// // //                 style: IconButton.styleFrom(backgroundColor: Colors.black45),
// // //               ),
// // //             ),
// // //
// // //             Positioned(
// // //               bottom: 0, left: 0, right: 0,
// // //               child: Container(
// // //                 padding: const EdgeInsets.fromLTRB(20, 30, 20, 40),
// // //                 decoration: BoxDecoration(
// // //                     color: Colors.black.withOpacity(0.7),
// // //                     borderRadius: const BorderRadius.vertical(top: Radius.circular(30))
// // //                 ),
// // //                 child: Column(
// // //                   mainAxisSize: MainAxisSize.min,
// // //                   children: [
// // //                     _isProcessing ? const CircularProgressIndicator(color: Colors.white) : const Icon(Icons.face, color: Colors.white, size: 40),
// // //                     const SizedBox(height: 15),
// // //                     Text(
// // //                       _isProcessing ? "Processing..." : "Face Recognition Active",
// // //                       style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
// // //                     ),
// // //                     const SizedBox(height: 5),
// // //                     const Text("Attendance will be marked for the detected face", style: TextStyle(color: Colors.white54, fontSize: 12)),
// // //                   ],
// // //                 ),
// // //               ),
// // //             ),
// // //           ],
// // //         ),
// // //       ),
// // //     );
// // //   }
// // //
// // //   InputImage? _convertCameraImage(CameraImage image) {
// // //     try {
// // //       return InputImage.fromBytes(
// // //           bytes: _mlService.concatenatePlanes(image.planes),
// // //           metadata: InputImageMetadata(
// // //               size: Size(image.width.toDouble(), image.height.toDouble()),
// // //               rotation: InputImageRotation.rotation270deg,
// // //               format: InputImageFormat.nv21,
// // //               bytesPerRow: image.planes[0].bytesPerRow
// // //           )
// // //       );
// // //     } catch (_) { return null; }
// // //   }
// // //
// // //   void _showTopNotification(String m, bool err) {
// // //     if (!mounted) return;
// // //     OverlayEntry entry = OverlayEntry(builder: (c) => Positioned(
// // //         top: 60, left: 20, right: 20,
// // //         child: Material(
// // //             color: Colors.transparent,
// // //             child: Container(
// // //                 padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
// // //                 decoration: BoxDecoration(color: err ? Colors.redAccent : Colors.green, borderRadius: BorderRadius.circular(30)),
// // //                 child: Row(
// // //                   children: [
// // //                     Icon(err ? Icons.error_outline : Icons.check_circle, color: Colors.white),
// // //                     const SizedBox(width: 10),
// // //                     Expanded(child: Text(m, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
// // //                   ],
// // //                 )
// // //             )
// // //         )
// // //     ));
// // //     Overlay.of(context).insert(entry);
// // //     Future.delayed(const Duration(seconds: 3), () => entry.remove());
// // //   }
// // //
// // //   // 🔴 FIX: Updated Dispose Logic
// // //   @override
// // //   void dispose() {
// // //     WidgetsBinding.instance.removeObserver(this);
// // //
// // //     // Directly dispose controller without calling setState (Crash Prevention)
// // //     final camera = _controller;
// // //     _controller = null;
// // //     if (camera != null) {
// // //       camera.dispose();
// // //     }
// // //
// // //     _faceDetector.close();
// // //     super.dispose();
// // //   }
// // // }
// // //
// // //
// // //
// // //
// // //
// // //
// // //
