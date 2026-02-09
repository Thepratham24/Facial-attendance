import 'dart:async'; // 🔴 Added
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:ui';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/ml_service.dart';
import '../../services/api_service.dart';
import '../../widgets/face_painter.dart';
import '../../main.dart';
import 'employee_dashboard.dart';

class EmployeeLoginScreen extends StatefulWidget {
  const EmployeeLoginScreen({super.key});

  @override
  State<EmployeeLoginScreen> createState() => _EmployeeLoginScreenState();
}

class _EmployeeLoginScreenState extends State<EmployeeLoginScreen> with WidgetsBindingObserver {
  final MLService _mlService = MLService();
  final ApiService _apiService = ApiService();

  CameraController? _controller;
  late FaceDetector _faceDetector;

  bool _isDetecting = false;
  bool _isNavigating = false;
  bool _canStartScanning = false;
  DateTime? _lastScanTime;
  String _statusMessage = "Initializing...";
  Color _statusColor = Colors.white;
  List<Face> _faces = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 🔴 Landmarks ON helps with glasses/specs
    _faceDetector = FaceDetector(options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast, enableLandmarks: true));

    Future.delayed(const Duration(milliseconds: 500), () {
      _checkAutoLogin();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only manage camera if we are not navigating away
    if (_isNavigating) return;

    if (state == AppLifecycleState.inactive) {
      _stopCamera();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _checkAutoLogin() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('token');
    String? empId = prefs.getString('employeeId');
    String? empName = prefs.getString('emp_name');

    if (token != null && empId != null && empName != null && mounted) {
      print("✅ Auto Login Success: $empName");
      _isNavigating = true; // Prevent camera start
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => EmployeeDashboard(
            employeeName: empName,
            employeeId: empId
        )),
      );
    } else {
      _requestCameraPermission();
    }
  }

  Future<void> _requestCameraPermission() async {
    var status = await Permission.camera.request();
    if (status.isGranted) {
      _initializeCamera();
    } else {
      if (mounted) setState(() => _statusMessage = "Camera Permission Denied");
    }
  }

  // 🔴 FIX 1: Safe Camera Init (List check)
  void _initializeCamera() async {
    if (cameras.isEmpty) {
      setState(() => _statusMessage = "No Camera Found");
      return;
    }

    if (_controller != null) {
      await _controller!.dispose();
    }

    // Try finding front camera, else fallback to first available
    CameraDescription selectedCamera = cameras[0];
    try {
      selectedCamera = cameras.firstWhere(
            (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
    } catch (e) {
      // Fallback if list is weirdly empty
      if (cameras.isNotEmpty) selectedCamera = cameras[0];
    }

    _controller = CameraController(
        selectedCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888
    );

    try {
      await _controller!.initialize();
      if (!mounted) return;

      await _controller?.startImageStream(_processCameraImage);

      setState(() => _statusMessage = "Clearing Buffer...");
      await Future.delayed(const Duration(seconds: 2));

      if (mounted) {
        setState(() {
          _canStartScanning = true;
          _statusMessage = "Look at the Camera...";
        });
      }
    } catch (e) {
      debugPrint("Camera Error: $e");
      if(mounted) setState(() => _statusMessage = "Camera Error: Try Restarting");
    }
  }

  Future<void> _stopCamera({bool isDisposing = false}) async {
    final CameraController? oldController = _controller;

    if (!isDisposing && mounted) {
      setState(() => _controller = null);
    }

    if (oldController != null) {
      try {
        if (oldController.value.isStreamingImages) {
          await oldController.stopImageStream();
        }
        await oldController.dispose();
      } catch (e) {
        print("Stop Error: $e");
      }
    }
  }

  void _processCameraImage(CameraImage image) async {
    if (!_canStartScanning || _isDetecting || _isNavigating || _controller == null || !mounted) return;

    if (_lastScanTime != null && DateTime.now().difference(_lastScanTime!).inMilliseconds < 450) return;
    _lastScanTime = DateTime.now();

    _isDetecting = true;

    try {
      final inputImage = _convertCameraImage(image);
      if (inputImage == null) return;

      final faces = await _faceDetector.processImage(inputImage);
      if (mounted) setState(() => _faces = faces);

      if (faces.isNotEmpty) {
        // 🔴 FIX 2: Internet Check before heavy processing
        try {
          final result = await InternetAddress.lookup('google.com');
          if (result.isEmpty || result[0].rawAddress.isEmpty) {
            throw SocketException("No Internet");
          }
        } on SocketException {
          if(mounted) _showTopNotification("No Internet Connection", true);
          _isDetecting = false; // Release lock
          return;
        }

        if(mounted) setState(() { _statusMessage = "Verifying..."; _statusColor = Colors.cyanAccent; });

        List<double> liveEmbedding = await _mlService.getEmbedding(image, faces[0]);
        var response = await _apiService.authenticateEmployee(liveEmbedding);

        bool isSuccess = response != null && response['success'] == true && response['data'] != null;
        String backendMsg = response?['message'] ?? "Face Not Recognized";

        if (isSuccess && mounted && !_isNavigating) {
          _isNavigating = true;
          await _stopCamera();

          var userData = response['data'];
          String name = userData['name'] ?? "Employee";
          String? token = response['token'];
          String idToSave = userData['employeeId'] ?? userData['_id'] ?? "";
          String locationId = response['locationId'] ?? userData['locationId'] ?? "";

          _showTopNotification("$backendMsg! Welcome, $name!", false);

          SharedPreferences prefs = await SharedPreferences.getInstance();
          await prefs.setString('emp_name', name);
          await prefs.setString('employeeId', idToSave);
          await prefs.setString('_id', idToSave);
          if (token != null) await prefs.setString('token', token);
          if (locationId.isNotEmpty) await prefs.setString('locationId', locationId);

          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => EmployeeDashboard(
                  employeeName: name,
                  employeeId: idToSave
              )),
            );
          }
        } else {
          if (mounted) {
            _showTopNotification(backendMsg, true);

            setState(() { _statusMessage = "Retrying..."; _statusColor = Colors.white; });
            await Future.delayed(const Duration(seconds: 1));

            if(mounted && !_isNavigating) {
              setState(() { _statusMessage = "Look at the Camera..."; _statusColor = Colors.white; _isDetecting = false; });
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Scan Error: $e");
    } finally {
      if (mounted && !_isNavigating && _faces.isEmpty) _isDetecting = false;
    }
  }

  void _showTopNotification(String message, bool isError) {
    if (!mounted) return;

    OverlayEntry entry = OverlayEntry(builder: (context) => Positioned(
      top: 50,
      left: 20,
      right: 20,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
              color: isError ? Colors.redAccent : Colors.green,
              borderRadius: BorderRadius.circular(30),
              boxShadow: [const BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))]
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(isError ? Icons.error_outline : Icons.check_circle, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    ));

    Overlay.of(context).insert(entry);
    Future.delayed(const Duration(seconds: 3), () {
      entry.remove();
    });
  }

  // 🔴 FIX 3: Dynamic Rotation Logic
  InputImage? _convertCameraImage(CameraImage image) {
    if (_controller == null) return null;
    try {
      final camera = _controller!.description;
      final sensorOrientation = camera.sensorOrientation;
      InputImageRotation rotation = InputImageRotation.rotation0deg;

      if (Platform.isAndroid) {
        var rotationCompensation = (sensorOrientation + 0) % 360;
        rotation = InputImageRotationValue.fromRawValue(rotationCompensation)
            ?? InputImageRotation.rotation270deg;
      }

      final bytes = _mlService.concatenatePlanes(image.planes);
      return InputImage.fromBytes(
          bytes: bytes,
          metadata: InputImageMetadata(
              size: Size(image.width.toDouble(), image.height.toDouble()),
              rotation: rotation, // 🔴 Dynamic
              format: InputImageFormat.nv21,
              bytesPerRow: image.planes[0].bytesPerRow
          )
      );
    } catch (_) { return null; }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopCamera(isDisposing: true);
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_controller != null && _controller!.value.isInitialized && !_isNavigating)
            Positioned.fill(
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
                        imageSize: _controller!.value.previewSize!,
                      ),
                    ),
                  ),
                ),
              ),
            )
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),

          SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: Column(children: const [
                      Icon(Icons.security, color: Colors.white, size: 40),
                      SizedBox(height: 10),
                      Text("BIOMETRIC LOGIN", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))
                    ])
                ),

                Padding(
                  padding: const EdgeInsets.all(25),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.white.withOpacity(0.2))),
                        child: Column(children: [
                          Icon(_statusColor == Colors.greenAccent ? Icons.verified : Icons.face_unlock_outlined, color: _statusColor, size: 35),
                          const SizedBox(height: 20),
                          Text(_statusMessage, textAlign: TextAlign.center, style: TextStyle(color: _statusColor, fontSize: 20, fontWeight: FontWeight.bold)),
                          if(!_canStartScanning) ...[const SizedBox(height: 10), const SizedBox(height: 15, width: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54))],
                          const SizedBox(height: 8),
                          const Text("Keep phone steady", style: TextStyle(color: Colors.white54, fontSize: 12))
                        ]),
                      ),
                    ),
                  ),
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}

















// import 'dart:io';
// import 'package:camera/camera.dart';
// import 'package:flutter/material.dart';
// import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
// import 'package:permission_handler/permission_handler.dart';
// import 'dart:ui';
// import 'package:shared_preferences/shared_preferences.dart';
//
// import '../../services/ml_service.dart';
// import '../../services/api_service.dart';
// import '../../widgets/face_painter.dart';
// import '../../main.dart';
// import 'employee_dashboard.dart';
//
// class EmployeeLoginScreen extends StatefulWidget {
//   const EmployeeLoginScreen({super.key});
//
//   @override
//   State<EmployeeLoginScreen> createState() => _EmployeeLoginScreenState();
// }
//
// class _EmployeeLoginScreenState extends State<EmployeeLoginScreen> with WidgetsBindingObserver {
//   final MLService _mlService = MLService();
//   final ApiService _apiService = ApiService();
//
//   CameraController? _controller;
//   late FaceDetector _faceDetector;
//
//   bool _isDetecting = false;
//   bool _isNavigating = false;
//   bool _canStartScanning = false;
//   DateTime? _lastScanTime;
//   String _statusMessage = "Initializing...";
//   Color _statusColor = Colors.white;
//   List<Face> _faces = [];
//
//   @override
//   void initState() {
//     super.initState();
//     WidgetsBinding.instance.addObserver(this);
//     // Specs detection ke liye landmarks ON and Low Resolution (Freeze fix)
//     _faceDetector = FaceDetector(options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast, enableLandmarks: true));
//
//     Future.delayed(const Duration(milliseconds: 500), () {
//       _checkAutoLogin();
//     });
//   }
//
//   @override
//   void didChangeAppLifecycleState(AppLifecycleState state) {
//     if (_controller == null || !_controller!.value.isInitialized) return;
//
//     if (state == AppLifecycleState.inactive) {
//       _stopCamera();
//     } else if (state == AppLifecycleState.resumed) {
//       _initializeCamera();
//     }
//   }
//
//   Future<void> _checkAutoLogin() async {
//     SharedPreferences prefs = await SharedPreferences.getInstance();
//     String? token = prefs.getString('token');
//     String? empId = prefs.getString('employeeId');
//     String? empName = prefs.getString('emp_name');
//
//     if (token != null && empId != null && empName != null && mounted) {
//       print("✅ Auto Login Success: $empName");
//       Navigator.pushReplacement(
//         context,
//         MaterialPageRoute(builder: (context) => EmployeeDashboard(
//             employeeName: empName,
//             employeeId: empId
//         )),
//       );
//     } else {
//       _requestCameraPermission();
//     }
//   }
//
//   Future<void> _requestCameraPermission() async {
//     var status = await Permission.camera.request();
//     if (status.isGranted) {
//       _initializeCamera();
//     } else {
//       if (mounted) setState(() => _statusMessage = "Camera Permission Denied");
//     }
//   }
//
//   void _initializeCamera() async {
//     if (cameras.isEmpty) return;
//
//     if (_controller != null) {
//       await _controller!.dispose();
//     }
//
//     CameraDescription? frontCamera = cameras.firstWhere(
//           (camera) => camera.lensDirection == CameraLensDirection.front,
//       orElse: () => cameras.first,
//     );
//
//     _controller = CameraController(
//         frontCamera,
//         ResolutionPreset.medium, // 🔴 Low for performance/Anti-Freeze
//         enableAudio: false,
//         imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888
//     );
//
//     try {
//       await _controller!.initialize();
//       if (!mounted) return;
//
//       await _controller?.startImageStream(_processCameraImage);
//
//       setState(() => _statusMessage = "Clearing Buffer...");
//       await Future.delayed(const Duration(seconds: 2));
//
//       if (mounted) {
//         setState(() {
//           _canStartScanning = true;
//           _statusMessage = "Look at the Camera...";
//         });
//       }
//     } catch (e) {
//       debugPrint("Camera Error: $e");
//     }
//   }
//
//   Future<void> _stopCamera({bool isDisposing = false}) async {
//     final CameraController? oldController = _controller;
//
//     if (!isDisposing && mounted) {
//       setState(() => _controller = null);
//     }
//
//     if (oldController != null) {
//       try {
//         if (oldController.value.isStreamingImages) {
//           await oldController.stopImageStream();
//         }
//         await oldController.dispose();
//       } catch (e) {
//         print("Stop Error: $e");
//       }
//     }
//   }
//
//   void _processCameraImage(CameraImage image) async {
//     if (!_canStartScanning || _isDetecting || _isNavigating || _controller == null || !mounted) return;
//
//     // 🔴 450ms Throttle for Specs Glare handling
//     if (_lastScanTime != null && DateTime.now().difference(_lastScanTime!).inMilliseconds < 450) return;
//     _lastScanTime = DateTime.now();
//
//     _isDetecting = true;
//
//     try {
//       final inputImage = _convertCameraImage(image);
//       if (inputImage == null) return;
//
//       final faces = await _faceDetector.processImage(inputImage);
//       if (mounted) setState(() => _faces = faces);
//
//       if (faces.isNotEmpty) {
//         if(mounted) setState(() { _statusMessage = "Verifying..."; _statusColor = Colors.cyanAccent; });
//
//         List<double> liveEmbedding = await _mlService.getEmbedding(image, faces[0]);
//         var response = await _apiService.authenticateEmployee(liveEmbedding);
//
//         bool isSuccess = response != null && response['success'] == true && response['data'] != null;
//         String backendMsg = response?['message'] ?? "Face Not Recognized";
//
//         if (isSuccess && mounted && !_isNavigating) {
//           _isNavigating = true;
//           await _stopCamera();
//
//           var userData = response['data'];
//           String name = userData['name'] ?? "Employee";
//           String? token = response['token'];
//           String idToSave = userData['employeeId'] ?? userData['_id'] ?? "";
//           String locationId = response['locationId'] ?? userData['locationId'] ?? "";
//
//           // 🔴 Success Notification
//           _showTopNotification("$backendMsg! Welcome, $name!", false);
//
//           SharedPreferences prefs = await SharedPreferences.getInstance();
//           await prefs.setString('emp_name', name);
//           await prefs.setString('employeeId', idToSave);
//           await prefs.setString('_id', idToSave);
//           if (token != null) await prefs.setString('token', token);
//           if (locationId.isNotEmpty) await prefs.setString('locationId', locationId);
//
//           if (mounted) {
//             Navigator.pushReplacement(
//               context,
//               MaterialPageRoute(builder: (context) => EmployeeDashboard(
//                   employeeName: name,
//                   employeeId: idToSave
//               )),
//             );
//           }
//         } else {
//           if (mounted) {
//             // 🔴 ERROR NOTIFICATION (Ab ye Upar ayega)
//             _showTopNotification(backendMsg, true);
//
//             setState(() { _statusMessage = "Retrying..."; _statusColor = Colors.white; });
//             await Future.delayed(const Duration(seconds: 2));
//
//             if(mounted && !_isNavigating) {
//               setState(() { _statusMessage = "Look at the Camera..."; _statusColor = Colors.white; _isDetecting = false; });
//             }
//           }
//         }
//       }
//     } catch (e) {
//       debugPrint("Scan Error: $e");
//     } finally {
//       if (mounted && !_isNavigating && _faces.isEmpty) _isDetecting = false;
//     }
//   }
//
//   // 🔴🔴 NEW: TOP NOTIFICATION FUNCTION 🔴🔴
//   void _showTopNotification(String message, bool isError) {
//     if (!mounted) return;
//
//     OverlayEntry entry = OverlayEntry(builder: (context) => Positioned(
//       top: 50, // Top margin (Status bar ke niche)
//       left: 20,
//       right: 20,
//       child: Material(
//         color: Colors.transparent,
//         child: Container(
//           padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
//           decoration: BoxDecoration(
//               color: isError ? Colors.redAccent : Colors.green,
//               borderRadius: BorderRadius.circular(30),
//               boxShadow: [const BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))]
//           ),
//           child: Row(
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               Icon(isError ? Icons.error_outline : Icons.check_circle, color: Colors.white),
//               const SizedBox(width: 10),
//               Expanded(
//                 child: Text(
//                   message,
//                   style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
//                   overflow: TextOverflow.ellipsis,
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     ));
//
//     Overlay.of(context).insert(entry);
//     // 3 Seconds baad gayab ho jayega
//     Future.delayed(const Duration(seconds: 3), () {
//       entry.remove();
//     });
//   }
//
//   InputImage? _convertCameraImage(CameraImage image) {
//     try {
//       final bytes = _mlService.concatenatePlanes(image.planes);
//       return InputImage.fromBytes(
//           bytes: bytes,
//           metadata: InputImageMetadata(
//               size: Size(image.width.toDouble(), image.height.toDouble()),
//               rotation: InputImageRotation.rotation270deg,
//               format: InputImageFormat.nv21,
//               bytesPerRow: image.planes[0].bytesPerRow
//           )
//       );
//     } catch (_) { return null; }
//   }
//
//   @override
//   void dispose() {
//     WidgetsBinding.instance.removeObserver(this);
//     _stopCamera(isDisposing: true);
//     _faceDetector.close();
//     super.dispose();
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: Colors.black,
//       body: Stack(
//         children: [
//           if (_controller != null && _controller!.value.isInitialized && !_isNavigating)
//             Positioned.fill(
//               child: FittedBox(
//                 fit: BoxFit.cover,
//                 child: SizedBox(
//                   width: _controller!.value.previewSize!.height,
//                   height: _controller!.value.previewSize!.width,
//                   child: CameraPreview(
//                     _controller!,
//                     child: CustomPaint(
//                       painter: FacePainter(
//                         faces: _faces,
//                         imageSize: _controller!.value.previewSize!,
//                       ),
//                     ),
//                   ),
//                 ),
//               ),
//             )
//           else
//             const Center(child: CircularProgressIndicator(color: Colors.white)),
//
//           SafeArea(
//             child: Column(
//               mainAxisAlignment: MainAxisAlignment.spaceBetween,
//               children: [
//                 Padding(
//                     padding: const EdgeInsets.only(top: 20),
//                     child: Column(children: const [
//                       Icon(Icons.security, color: Colors.white, size: 40),
//                       SizedBox(height: 10),
//                       Text("BIOMETRIC LOGIN", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))
//                     ])
//                 ),
//
//                 Padding(
//                   padding: const EdgeInsets.all(25),
//                   child: ClipRRect(
//                     borderRadius: BorderRadius.circular(30),
//                     child: BackdropFilter(
//                       filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
//                       child: Container(
//                         width: double.infinity,
//                         padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
//                         decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.white.withOpacity(0.2))),
//                         child: Column(children: [
//                           Icon(_statusColor == Colors.greenAccent ? Icons.verified : Icons.face_unlock_outlined, color: _statusColor, size: 35),
//                           const SizedBox(height: 20),
//                           Text(_statusMessage, textAlign: TextAlign.center, style: TextStyle(color: _statusColor, fontSize: 20, fontWeight: FontWeight.bold)),
//                           if(!_canStartScanning) ...[const SizedBox(height: 10), const SizedBox(height: 15, width: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54))],
//                           const SizedBox(height: 8),
//                           const Text("Keep phone steady", style: TextStyle(color: Colors.white54, fontSize: 12))
//                         ]),
//                       ),
//                     ),
//                   ),
//                 )
//               ],
//             ),
//           )
//         ],
//       ),
//     );
//   }
// }
//
//
//
//
//
//
