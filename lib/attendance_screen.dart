// import 'package:camera/camera.dart';
// import 'package:flutter/material.dart';
// import 'package:geolocator/geolocator.dart';
// import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
// import 'screens/all_employees_attendace_list.dart';
// import 'main.dart';
// import 'ml_service.dart';
// import 'db_service.dart';
// import 'screens/result_screen.dart';
//
// class AttendanceScreen extends StatefulWidget {
//   const AttendanceScreen({super.key});
//
//   @override
//   State<AttendanceScreen> createState() => _AttendanceScreenState();
// }
//
// class _AttendanceScreenState extends State<AttendanceScreen> {
//   final MLService _mlService = MLService();
//   final DBService _dbService = DBService();
//
//   CameraController? _controller;
//   late FaceDetector _faceDetector;
//
//   bool _isDetecting = false;
//   bool _registerMode = false;
//   bool _isInsideLocation = false;
//   bool _isSettingDialogOpen = false;
//   double _currentDistance = 0.0;
//   bool _isProcessing = false;
//   DateTime? _faceFirstSeenTime;
//   bool _isAlertShown = false;
//
//   double targetLat = 0.0;
//   double targetLng = 0.0;
//   double allowedRadius = 60;
//
//   List<Face> _faces = [];
//   CameraImage? _savedImage;
//
//   @override
//   void initState() {
//     super.initState();
//     _loadSettings();
//     _faceDetector = FaceDetector(options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast));
//     initializeCamera();
//     _startLocationTimer();
//   }
//
//   void _loadSettings() {
//     double savedLat = _dbService.getOfficeLat();
//     double savedLng = _dbService.getOfficeLng();
//     setState(() {
//       targetLat = savedLat;
//       targetLng = savedLng;
//     });
//   }
//
//   @override
//   void dispose() {
//     _controller?.dispose();
//     _faceDetector.close();
//     super.dispose();
//   }
//
//   void _startLocationTimer() async {
//     while (mounted) {
//       await _checkLocation();
//       await Future.delayed(const Duration(seconds: 3));
//     }
//   }
//
//   Future<void> _checkLocation() async {
//     try {
//       Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
//       double distance = Geolocator.distanceBetween(position.latitude, position.longitude, targetLat, targetLng);
//       if (mounted) {
//         setState(() {
//           _currentDistance = distance;
//           _isInsideLocation = (distance <= allowedRadius);
//         });
//       }
//     } catch (e) {
//       debugPrint("GPS Error: $e");
//     }
//   }
//
//   Future<void> _safeStopCamera() async {
//     if (_controller != null && _controller!.value.isStreamingImages) {
//       try {
//         await _controller!.stopImageStream();
//       } catch (e) {
//         debugPrint("Camera Safe Stop Error: $e");
//       }
//     }
//   }
//
//   void _showSettingsDialog() {
//     setState(() => _isSettingDialogOpen = true);
//
//     TextEditingController latController = TextEditingController(text: targetLat.toString());
//     TextEditingController lngController = TextEditingController(text: targetLng.toString());
//
//     showDialog(
//       context: context,
//       barrierDismissible: false,
//       builder: (context) => AlertDialog(
//         title: const Text("Set Office Location"),
//         content: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             const Text("Enter Coordinates:", style: TextStyle(fontSize: 12, color: Colors.grey)),
//             const SizedBox(height: 10),
//             TextField(controller: latController, decoration: const InputDecoration(labelText: "Latitude", border: OutlineInputBorder()), keyboardType: TextInputType.number),
//             const SizedBox(height: 10),
//             TextField(controller: lngController, decoration: const InputDecoration(labelText: "Longitude", border: OutlineInputBorder()), keyboardType: TextInputType.number),
//           ],
//         ),
//         actions: [
//           TextButton(
//               onPressed: () {
//                 setState(() => _isSettingDialogOpen = false);
//                 Navigator.pop(context);
//               },
//               child: const Text("Cancel")),
//           ElevatedButton(
//             onPressed: () async {
//               double? nLat = double.tryParse(latController.text.trim());
//               double? nLng = double.tryParse(lngController.text.trim());
//               if (nLat != null && nLng != null) {
//                 await _dbService.saveOfficeLocation(nLat, nLng);
//                 _loadSettings();
//                 await _checkLocation();
//                 setState(() => _isSettingDialogOpen = false);
//                 if (mounted) Navigator.pop(context);
//               }
//             },
//             child: const Text("Save"),
//           ),
//         ],
//       ),
//     );
//   }
//
//   void initializeCamera() async {
//     if (cameras.isEmpty) return;
//     _controller = CameraController(cameras[1], ResolutionPreset.medium, enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
//     await _controller!.initialize();
//     if (mounted) setState(() {});
//     _controller?.startImageStream((image) {
//       _savedImage = image;
//       if (!_isDetecting) _doFaceDetection(image);
//     });
//   }
//
//   Future<void> _doFaceDetection(CameraImage image) async {
//     if (_isDetecting || !mounted || _isSettingDialogOpen) return;
//     _isDetecting = true;
//
//     try {
//       final inputImage = _convertCameraImage(image);
//       if (inputImage != null) {
//         final faces = await _faceDetector.processImage(inputImage);
//         if (mounted) setState(() => _faces = faces);
//
//         if (faces.isEmpty) {
//           _faceFirstSeenTime = null;
//           _isAlertShown = false;
//         } else if (!_registerMode && _isInsideLocation) {
//           _faceFirstSeenTime ??= DateTime.now();
//
//           List<double> embedding = await _mlService.getEmbedding(image, faces[0]);
//           String? name = _identifyUser(embedding);
//
//           if (name != null) {
//             _faceFirstSeenTime = null;
//             await _dbService.saveAttendanceLog(name);
//             await _safeStopCamera();
//
//             if (mounted) {
//               _showTopNotification("Attendance Marked: $name", false);
//               await Navigator.push(
//                 context,
//                 MaterialPageRoute(builder: (context) => ResultScreen(name: name, imagePath: "")),
//               );
//               initializeCamera();
//               _faceFirstSeenTime = null;
//             }
//           } else {
//             final duration = DateTime.now().difference(_faceFirstSeenTime!);
//             if (duration.inSeconds >= 5 && !_isAlertShown) {
//               _isAlertShown = true;
//               _showRegisterAlert();
//             }
//           }
//         }
//       }
//     } catch (e) {
//       debugPrint("Detection Error: $e");
//     } finally {
//       _isDetecting = false;
//     }
//   }
//
//   void _showRegisterAlert() {
//     setState(() => _isSettingDialogOpen = true);
//     showDialog(
//       context: context,
//       barrierDismissible: false,
//       builder: (context) => AlertDialog(
//         title: const Text("Unknown Face"),
//         content: const Text("Face not recognized. Switch to 'Register Mode' to add this user."),
//         actions: [
//           ElevatedButton(
//             onPressed: () {
//               setState(() {
//                 _isSettingDialogOpen = false;
//                 _registerMode = true; // Auto switch to register mode
//               });
//               Navigator.pop(context);
//             },
//             child: const Text("Switch to Register"),
//           ),
//         ],
//       ),
//     );
//   }
//
//   String? _identifyUser(List<double> newEmbedding) {
//     Map users = _dbService.getAllUsers();
//     double minDistance = 1.0;
//     String? foundName;
//     users.forEach((name, storedEmbedding) {
//       if (name == 'office_lat' || name == 'office_lng') return;
//       double distance = _mlService.calculateDistance(newEmbedding, List<double>.from(storedEmbedding));
//       if (distance < minDistance) { minDistance = distance; foundName = name; }
//     });
//     return (minDistance < 0.8) ? foundName : null;
//   }
//
//   void _showTopNotification(String m, bool err) {
//     OverlayEntry entry = OverlayEntry(
//         builder: (c) => Positioned(
//             top: 60,
//             left: 20,
//             right: 20,
//             child: Material(
//                 color: Colors.transparent,
//                 child: Container(
//                     padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
//                     decoration: BoxDecoration(
//                         color: err ? Colors.redAccent.shade700 : Colors.green.shade700,
//                         borderRadius: BorderRadius.circular(15),
//                         boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, spreadRadius: 2)]),
//                     child: Row(
//                       mainAxisAlignment: MainAxisAlignment.center,
//                       children: [
//                         Icon(err ? Icons.error_outline : Icons.check_circle_outline, color: Colors.white),
//                         const SizedBox(width: 10),
//                         Flexible(child: Text(m, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
//                       ],
//                     )))));
//     Overlay.of(context).insert(entry);
//     Future.delayed(const Duration(seconds: 3), () => entry.remove());
//   }
//
//   InputImage? _convertCameraImage(CameraImage image) {
//     return InputImage.fromBytes(bytes: _mlService.concatenatePlanes(image.planes), metadata: InputImageMetadata(size: Size(image.width.toDouble(), image.height.toDouble()), rotation: InputImageRotation.rotation270deg, format: InputImageFormat.nv21, bytesPerRow: image.planes[0].bytesPerRow));
//   }
//
//   // --- NEW UI BUILD METHOD ---
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: Colors.black,
//       body: Stack(
//         children: [
//           // 1. CAMERA LAYER
//           if (_controller != null && _controller!.value.isInitialized)
//             Positioned.fill(
//               child: ClipRect(
//                 child: FittedBox(
//                   fit: BoxFit.cover,
//                   child: SizedBox(
//                     width: _controller!.value.previewSize!.height,
//                     height: _controller!.value.previewSize!.width,
//                     child: CameraPreview(
//                       _controller!,
//                       child: CustomPaint(
//                         painter: FacePainter(
//                           faces: _faces,
//                           imageSize: _controller!.value.previewSize!,
//                         ),
//                       ),
//                     ),
//                   ),
//                 ),
//               ),
//             ),
//
//           // 2. TOP GRADIENT OVERLAY (For visibility of status bar)
//           Positioned(
//             top: 0,
//             left: 0,
//             right: 0,
//             height: 150,
//             child: Container(
//               decoration: BoxDecoration(
//                 gradient: LinearGradient(
//                   begin: Alignment.topCenter,
//                   end: Alignment.bottomCenter,
//                   colors: [Colors.black.withOpacity(0.7), Colors.transparent],
//                 ),
//               ),
//             ),
//           ),
//
//           // 3. FLOATING TOP BAR (Settings & History)
//           Positioned(
//             top: 40,
//             right: 20,
//             left: 20,
//             child: Row(
//               mainAxisAlignment: MainAxisAlignment.spaceBetween,
//               children: [
//                 // Title
//                 const Text(
//                   "Smart Attendance",
//                   style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
//                 ),
//                 // Icons
//                 Row(
//                   children: [
//                     _buildCircleButton(Icons.edit_location_alt_rounded, _showSettingsDialog),
//                     const SizedBox(width: 10),
//                     _buildCircleButton(Icons.history, () {
//                       _controller?.stopImageStream().catchError((_) {});
//                       Navigator.push(context, MaterialPageRoute(builder: (c) => const AttendanceHistoryScreen())).then((_) {
//                         initializeCamera();
//                         setState(() { _isDetecting = false; });
//                       });
//                     }),
//                   ],
//                 )
//               ],
//             ),
//           ),
//
//           // 4. FLOATING STATUS CAPSULE (Location Status)
//           Positioned(
//             top: 100,
//             left: 0,
//             right: 0,
//             child: Center(
//               child: Container(
//                 padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
//                 decoration: BoxDecoration(
//                   color: _isInsideLocation ? Colors.green.withOpacity(0.8) : Colors.red.withOpacity(0.8),
//                   borderRadius: BorderRadius.circular(30),
//                   border: Border.all(color: Colors.white30, width: 1),
//                 ),
//                 child: Row(
//                   mainAxisSize: MainAxisSize.min,
//                   children: [
//                     Icon(_isInsideLocation ? Icons.location_on : Icons.location_off, color: Colors.white, size: 16),
//                     const SizedBox(width: 8),
//                     Text(
//                       _isInsideLocation ? "Inside Office (${_currentDistance.toStringAsFixed(0)}m)" : "Outside Office (${_currentDistance.toStringAsFixed(0)}m)",
//                       style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
//                     ),
//                   ],
//                 ),
//               ),
//             ),
//           ),
//
//           // 5. BOTTOM CONTROL PANEL
//           Positioned(
//             bottom: 0,
//             left: 0,
//             right: 0,
//             child: Container(
//               padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
//               decoration: const BoxDecoration(
//                 color: Colors.white,
//                 borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
//                 boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20, spreadRadius: 5)],
//               ),
//               child: Column(
//                 mainAxisSize: MainAxisSize.min,
//                 children: [
//                   // --- CUSTOM SEGMENTED TAB SWITCHER ---
//                   Container(
//                     height: 50,
//                     padding: const EdgeInsets.all(4),
//                     decoration: BoxDecoration(
//                       color: Colors.grey.shade200,
//                       borderRadius: BorderRadius.circular(25),
//                     ),
//                     child: Row(
//                       children: [
//                         _buildTabButton("Attendance", !_registerMode),
//                         _buildTabButton("Register", _registerMode),
//                       ],
//                     ),
//                   ),
//
//                   const SizedBox(height: 20),
//
//                   // --- ACTION AREA ---
//                   if (_registerMode)
//                     SizedBox(
//                       width: double.infinity,
//                       height: 55,
//                       child: ElevatedButton(
//                         onPressed: _isProcessing
//                             ? null
//                             : () async {
//                           if (_faces.isEmpty) {
//                             _showTopNotification("No face detected! Look at camera.", true);
//                             return;
//                           }
//                           setState(() => _isProcessing = true);
//                           try {
//                             await _safeStopCamera();
//                             await Future.delayed(const Duration(milliseconds: 300));
//                             if (_savedImage != null) {
//                               List<double> emb = await _mlService.getEmbedding(_savedImage!, _faces[0]);
//                               if (mounted) _showNameInputDialog(emb);
//                             }
//                           } catch (e) {
//                             initializeCamera();
//                           } finally {
//                             if (mounted) setState(() => _isProcessing = false);
//                           }
//                         },
//                         style: ElevatedButton.styleFrom(
//                           backgroundColor: Colors.indigo,
//                           shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
//                           elevation: 2,
//                         ),
//                         child: _isProcessing
//                             ? const CircularProgressIndicator(color: Colors.white)
//                             : const Row(
//                           mainAxisAlignment: MainAxisAlignment.center,
//                           children: [
//                             Icon(Icons.person_add_alt_1, color: Colors.white),
//                             SizedBox(width: 10),
//                             Text("REGISTER NOW", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
//                           ],
//                         ),
//                       ),
//                     )
//                   else
//                     const Column(
//                       children: [
//                         CircularProgressIndicator(color: Colors.indigo),
//                         SizedBox(height: 10),
//                         Text("Scanning for Attendance...", style: TextStyle(color: Colors.grey, fontSize: 14)),
//                       ],
//                     ),
//                 ],
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
//
//   // Helper for Top Circle Buttons
//   Widget _buildCircleButton(IconData icon, VoidCallback onTap) {
//     return GestureDetector(
//       onTap: onTap,
//       child: Container(
//         padding: const EdgeInsets.all(10),
//         decoration: BoxDecoration(
//           color: Colors.white.withOpacity(0.2),
//           shape: BoxShape.circle,
//         ),
//         child: Icon(icon, color: Colors.white, size: 22),
//       ),
//     );
//   }
//
//   // Helper for Custom Tab Button
//   Widget _buildTabButton(String text, bool isActive) {
//     return Expanded(
//       child: GestureDetector(
//         onTap: () {
//           setState(() {
//             _registerMode = (text == "Register");
//           });
//         },
//         child: AnimatedContainer(
//           duration: const Duration(milliseconds: 200),
//           alignment: Alignment.center,
//           decoration: BoxDecoration(
//             color: isActive ? Colors.white : Colors.transparent,
//             borderRadius: BorderRadius.circular(25),
//             boxShadow: isActive ? [BoxShadow(color: Colors.black12, blurRadius: 4)] : [],
//           ),
//           child: Text(
//             text,
//             style: TextStyle(
//               color: isActive ? Colors.black87 : Colors.grey,
//               fontWeight: FontWeight.bold,
//               fontSize: 15,
//             ),
//           ),
//         ),
//       ),
//     );
//   }
//
//   void _showNameInputDialog(List<double> embedding) {
//     TextEditingController nameController = TextEditingController();
//     showDialog(
//       context: context,
//       barrierDismissible: false,
//       builder: (c) => AlertDialog(
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
//         title: const Text("Register Employee"),
//         content: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             const Text("Enter the full name of the employee."),
//             const SizedBox(height: 15),
//             TextField(
//               controller: nameController,
//               decoration: InputDecoration(
//                 hintText: "Name (e.g. Rahul)",
//                 border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
//                 filled: true,
//                 fillColor: Colors.grey.shade50,
//               ),
//             ),
//           ],
//         ),
//         actions: [
//           TextButton(
//             onPressed: () {
//               Navigator.pop(context);
//               initializeCamera();
//             },
//             child: const Text("Cancel"),
//           ),
//           ElevatedButton(
//             onPressed: () async {
//               String inputName = nameController.text.trim();
//               if (inputName.isEmpty) {
//                 _showTopNotification("Please enter a name", true);
//                 return;
//               }
//               String? existingUserName = _identifyUser(embedding);
//               if (existingUserName != null) {
//                 _showTopNotification("Already registered as: '$existingUserName'", true);
//                 return;
//               }
//               await _dbService.registerUser(inputName, embedding);
//               if (mounted) {
//                 Navigator.pop(context);
//                 initializeCamera();
//                 _showTopNotification("Registration Successful!", false);
//               }
//             },
//             style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
//             child: const Text("Save"),
//           )
//         ],
//       ),
//     );
//   }
// }
//
// class FacePainter extends CustomPainter {
//   final List<Face> faces;
//   final Size imageSize;
//   FacePainter({required this.faces, required this.imageSize});
//   @override
//   void paint(Canvas canvas, Size size) {
//     final paint = Paint()
//       ..style = PaintingStyle.stroke
//       ..strokeWidth = 2.0
//       ..color = Colors.cyanAccent; // Modern Color
//
//     for (var face in faces) {
//       double scaleX = size.width / imageSize.height;
//       double scaleY = size.height / imageSize.width;
//
//       // Draw standard box
//       Rect rect = Rect.fromLTRB(
//           face.boundingBox.left * scaleX,
//           face.boundingBox.top * scaleY,
//           face.boundingBox.right * scaleX,
//           face.boundingBox.bottom * scaleY
//       );
//
//       // Optional: Draw corner brackets logic can go here for a "Scanner" look
//       canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(10)), paint);
//     }
//   }
//   @override
//   bool shouldRepaint(FacePainter oldDelegate) => true;
// }
//
//
//
//
//
//
//
//
// // import 'package:camera/camera.dart';
// // import 'package:flutter/material.dart';
// // import 'package:geolocator/geolocator.dart';
// // import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
// // import 'all_employees_attendace_list.dart';
// // import 'main.dart';
// // import 'ml_service.dart';
// // import 'db_service.dart';
// // import 'result_screen.dart';
// //
// // class AttendanceScreen extends StatefulWidget {
// //   const AttendanceScreen({super.key});
// //
// //   @override
// //   State<AttendanceScreen> createState() => _AttendanceScreenState();
// // }
// //
// // class _AttendanceScreenState extends State<AttendanceScreen> {
// //   final MLService _mlService = MLService();
// //   final DBService _dbService = DBService();
// //
// //   CameraController? _controller;
// //   late FaceDetector _faceDetector;
// //
// //   bool _isDetecting = false;
// //   bool _registerMode = false;
// //   bool _isInsideLocation = false;
// //   bool _isSettingDialogOpen = false; // Stops background scanning
// //   double _currentDistance = 0.0;
// //   bool _isProcessing = false; // Ye button ko lock karega
// //   DateTime? _faceFirstSeenTime;
// //   bool _isAlertShown = false;
// //
// //   double targetLat = 0.0;
// //   double targetLng = 0.0;
// //   double allowedRadius = 60;
// //
// //   List<Face> _faces = [];
// //   CameraImage? _savedImage;
// //
// //   @override
// //   void initState() {
// //     super.initState();
// //     _loadSettings();
// //     _faceDetector = FaceDetector(options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast));
// //     initializeCamera();
// //     _startLocationTimer();
// //   }
// //
// //   void _loadSettings() {
// //     double savedLat = _dbService.getOfficeLat();
// //     double savedLng = _dbService.getOfficeLng();
// //     setState(() {
// //       targetLat = savedLat;
// //       targetLng = savedLng;
// //     });
// //   }
// //
// //   @override
// //   void dispose() {
// //     _controller?.dispose();
// //     _faceDetector.close();
// //     super.dispose();
// //   }
// //
// //   void _startLocationTimer() async {
// //     while (mounted) {
// //       await _checkLocation();
// //       await Future.delayed(const Duration(seconds: 3));
// //     }
// //   }
// //
// //   Future<void> _checkLocation() async {
// //     try {
// //       Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
// //       double distance = Geolocator.distanceBetween(position.latitude, position.longitude, targetLat, targetLng);
// //       if (mounted) {
// //         setState(() {
// //           _currentDistance = distance;
// //           _isInsideLocation = (distance <= allowedRadius);
// //         });
// //       }
// //     } catch (e) {
// //       debugPrint("GPS Error: $e");
// //     }
// //   }
// // // Camera ko safe tarike se rokne wala function
// //   Future<void> _safeStopCamera() async {
// //     if (_controller != null && _controller!.value.isStreamingImages) {
// //       try {
// //         await _controller!.stopImageStream();
// //       } catch (e) {
// //         debugPrint("Camera rokne me dikkat aayi (Ignore karein): $e");
// //       }
// //     }
// //   }
// //   void _showSettingsDialog() {
// //     setState(() => _isSettingDialogOpen = true); // SCANNING PAUSED
// //
// //     TextEditingController latController = TextEditingController(text: targetLat.toString());
// //     TextEditingController lngController = TextEditingController(text: targetLng.toString());
// //
// //     showDialog(
// //       context: context,
// //       barrierDismissible: false,
// //       builder: (context) => AlertDialog(
// //         title: const Text("Set Office Location"),
// //         content: Column(
// //           mainAxisSize: MainAxisSize.min,
// //           children: [
// //             const Text("Check coordinates carefully!", style: TextStyle(fontSize: 12, color: Colors.red)),
// //             TextField(controller: latController, decoration: const InputDecoration(labelText: "Latitude"), keyboardType: TextInputType.number),
// //             TextField(controller: lngController, decoration: const InputDecoration(labelText: "Longitude"), keyboardType: TextInputType.number),
// //           ],
// //         ),
// //         actions: [
// //           TextButton(
// //               onPressed: () {
// //                 setState(() => _isSettingDialogOpen = false); // SCANNING RESUMED
// //                 Navigator.pop(context);
// //               },
// //               child: const Text("Cancel")
// //           ),
// //           ElevatedButton(
// //             onPressed: () async {
// //               double? nLat = double.tryParse(latController.text.trim());
// //               double? nLng = double.tryParse(lngController.text.trim());
// //               if (nLat != null && nLng != null) {
// //                 await _dbService.saveOfficeLocation(nLat, nLng);
// //                 _loadSettings();
// //                 await _checkLocation();
// //                 setState(() => _isSettingDialogOpen = false); // SCANNING RESUMED
// //                 if (mounted) Navigator.pop(context);
// //               }
// //             },
// //             child: const Text("Save & Refresh"),
// //           ),
// //         ],
// //       ),
// //     );
// //   }
// //
// //   void initializeCamera() async {
// //     if (cameras.isEmpty) return;
// //     _controller = CameraController(cameras[1], ResolutionPreset.medium, enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
// //     await _controller!.initialize();
// //     if (mounted) setState(() {});
// //     _controller?.startImageStream((image) {
// //       _savedImage = image;
// //       if (!_isDetecting) _doFaceDetection(image);
// //     });
// //   }
// //   Future<void> _doFaceDetection(CameraImage image) async {
// //     // 1. Agar system busy hai ya screen band hai, toh yahi ruk jao
// //     if (_isDetecting || !mounted || _isSettingDialogOpen) return;
// //
// //     _isDetecting = true; // System BUSY
// //
// //     try {
// //       final inputImage = _convertCameraImage(image);
// //       if (inputImage != null) {
// //         final faces = await _faceDetector.processImage(inputImage);
// //         if (mounted) setState(() => _faces = faces);
// //
// //         // Agar chehra nahi dikh raha
// //         if (faces.isEmpty) {
// //           _faceFirstSeenTime = null;
// //           _isAlertShown = false;
// //         }
// //         // Agar chehra dikh raha hai aur hum Attendance Mode mein hain
// //         else if (!_registerMode && _isInsideLocation) {
// //
// //           // --- STEP A: IDENTIFY USER ---
// //           List<double> embedding = await _mlService.getEmbedding(image, faces[0]);
// //           String? name = _identifyUser(embedding);
// //
// //           if (name != null) {
// //             // --- STEP B: CHECK DUPLICATE (Optional but Good) ---
// //             // Yahan aap check kar sakte ho ki abhi 1 minute pehle lagayi thi ya nahi.
// //             // Abhi ke liye hum seedha mark kar rahe hain.
// //
// //             await _safeStopCamera(); // Camera roko safely
// //             await _dbService.saveAttendanceLog(name);
// //
// //             if (mounted) {
// //               _showTopNotification("Attendance Marked: $name", false);
// //
// //               // --- STEP C: NAVIGATE AND RESET ---
// //               await Navigator.push(
// //                 context,
// //                 MaterialPageRoute(builder: (context) => ResultScreen(name: name, imagePath: "")),
// //               );
// //
// //               // Wapas aane ke baad:
// //               initializeCamera(); // Camera restart
// //               _faceFirstSeenTime = null; // Timer reset
// //             }
// //           } else {
// //             // Unknown Face Logic
// //             _faceFirstSeenTime ??= DateTime.now();
// //             final duration = DateTime.now().difference(_faceFirstSeenTime!);
// //             if (duration.inSeconds >= 5 && !_isAlertShown) {
// //               _isAlertShown = true;
// //               _showRegisterAlert();
// //             }
// //           }
// //         }
// //       }
// //     } catch (e) {
// //       debugPrint("Detection Error: $e");
// //     } finally {
// //       // --- STEP D: UNLOCK SYSTEM ---
// //       // Ye sabse important line hai. Chahe error aaye ya success,
// //       // ye variable false hona hi chahiye taaki agla button/frame chal sake.
// //       _isDetecting = false;
// //     }
// //   }
// //   void _showRegisterAlert() {
// //     setState(() => _isSettingDialogOpen = true); // PAUSE SCANNING WHILE ALERT IS OPEN
// //     showDialog(
// //       context: context,
// //       barrierDismissible: false,
// //       builder: (context) => AlertDialog(
// //         title: const Text("User Not Found"),
// //         content: const Text("Your face is not registered. Please register first."),
// //         actions: [
// //           ElevatedButton(
// //             onPressed: () {
// //               setState(() => _isSettingDialogOpen = false); // RESUME SCANNING
// //               Navigator.pop(context);
// //               setState(() => _registerMode = true);
// //             },
// //             child: const Text("OK"),
// //           ),
// //         ],
// //       ),
// //     );
// //   }
// //
// //   String? _identifyUser(List<double> newEmbedding) {
// //     Map users = _dbService.getAllUsers();
// //     double minDistance = 1.0;
// //     String? foundName;
// //     users.forEach((name, storedEmbedding) {
// //       if (name == 'office_lat' || name == 'office_lng') return;
// //       double distance = _mlService.calculateDistance(newEmbedding, List<double>.from(storedEmbedding));
// //       if (distance < minDistance) { minDistance = distance; foundName = name; }
// //     });
// //     return (minDistance < 0.8) ? foundName : null;
// //   }
// //
// //   void _showTopNotification(String m, bool err) {
// //     OverlayEntry entry = OverlayEntry(builder: (c) => Positioned(top: 100, left: 20, right: 20, child: Material(color: Colors.transparent, child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: err ? Colors.red : Colors.green, borderRadius: BorderRadius.circular(10)), child: Text(m, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))))));
// //     Overlay.of(context).insert(entry);
// //     Future.delayed(const Duration(seconds: 2), () => entry.remove());
// //   }
// //
// //   InputImage? _convertCameraImage(CameraImage image) {
// //     return InputImage.fromBytes(bytes: _mlService.concatenatePlanes(image.planes), metadata: InputImageMetadata(size: Size(image.width.toDouble(), image.height.toDouble()), rotation: InputImageRotation.rotation270deg, format: InputImageFormat.nv21, bytesPerRow: image.planes[0].bytesPerRow));
// //   }
// //
// //   @override
// //   Widget build(BuildContext context) {
// //     return Scaffold(
// //       appBar: AppBar(
// //         title: const Text("Face Scanner"),
// //         actions: [
// //           IconButton(icon: const Icon(Icons.location_on,color: Colors.green,), onPressed: _showSettingsDialog),
// //           IconButton(icon: const Icon(Icons.history,color: Colors.blueGrey,), onPressed: () async {
// //             await _controller?.stopImageStream();
// //             if (mounted) {
// //               Navigator.push(context, MaterialPageRoute(builder: (c) => const AttendanceHistoryScreen())).then((_) => initializeCamera());
// //             }
// //           }),
// //         ],
// //       ),
// //       backgroundColor: Colors.black,
// //       body: Stack(
// //         children: [
// //           if (_controller != null && _controller!.value.isInitialized)
// //             // Positioned.fill(child: CameraPreview(_controller!, child: CustomPaint(painter: FacePainter(faces: _faces, imageSize: _controller!.value.previewSize!)))),
// // // Purana code hata kar ye wala dalein
// //             Positioned.fill(
// //               child: ClipRect( // Ye screen se bahar nikalne wale camera part ko kaat dega
// //                 child: FittedBox(
// //                   fit: BoxFit.cover, // Ye image ko bina stretch kiye puri screen cover karne dega
// //                   child: SizedBox(
// //                     // Yahan width aur height ko ulat (swap) karna padta hai kyunki
// //                     // Camera sensor landscape hota hai aur phone portrait.
// //                     width: _controller!.value.previewSize!.height,
// //                     height: _controller!.value.previewSize!.width,
// //                     child: CameraPreview(
// //                       _controller!,
// //                       child: CustomPaint(
// //                         painter: FacePainter(
// //                           faces: _faces,
// //                           imageSize: _controller!.value.previewSize!,
// //                         ),
// //                       ),
// //                     ),
// //                   ),
// //                 ),
// //               ),
// //             ),
// //           Positioned(
// //             top: 0, left: 0, right: 0,
// //             child: Container(
// //               color: _isInsideLocation ? Colors.green.withOpacity(0.9) : Colors.red.withOpacity(0.9),
// //               padding: const EdgeInsets.all(12),
// //               child: Column(
// //                 children: [
// //                   Text(_isInsideLocation ? "LOCATION: OK" : "LOCATION: WRONG",
// //                       style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
// //                   Text("Meters Away: ${_currentDistance.toStringAsFixed(1)}m",
// //                       style: const TextStyle(color: Colors.white, fontSize: 13)),
// //                 ],
// //               ),
// //             ),
// //           ),
// //
// //           Positioned(bottom: 0, left: 0, right: 0, child: Container(padding: const EdgeInsets.all(25), decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(30))), child: Column(mainAxisSize: MainAxisSize.min, children: [
// //             Row(mainAxisAlignment: MainAxisAlignment.center, children: [
// //               const Text("Attendance"), Switch(value: _registerMode, onChanged: (v) => setState(() => _registerMode = v)), const Text("Register"),
// //             ]),
// //             if (_registerMode)
// //               ElevatedButton(
// //                 onPressed: _isProcessing
// //                     ? null // Agar processing chal rahi hai toh button disable
// //                     : () async {
// //                   if (_faces.isEmpty) {
// //                     _showTopNotification("No face detected!", true);
// //                     return;
// //                   }
// //
// //                   // 1. Button Lock Karo
// //                   setState(() => _isProcessing = true);
// //
// //                   try {
// //                     // 2. Camera Safe Stop
// //                     await _safeStopCamera();
// //
// //                     // 3. Thoda saans lene do phone ko
// //                     await Future.delayed(const Duration(milliseconds: 300));
// //
// //                     // 4. AI Processing
// //                     if (_savedImage != null) {
// //                       List<double> emb = await _mlService.getEmbedding(_savedImage!, _faces[0]);
// //                       if (mounted) _showNameInputDialog(emb);
// //                     }
// //                   } catch (e) {
// //                     debugPrint("Register Error: $e");
// //                     initializeCamera(); // Galti hui toh camera wapas chalao
// //                   } finally {
// //                     // 5. Button Unlock Karo
// //                     if (mounted) setState(() => _isProcessing = false);
// //                   }
// //                 },
// //                 style: ElevatedButton.styleFrom(backgroundColor: _isProcessing ? Colors.grey : Colors.blue),
// //                 child: _isProcessing
// //                     ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
// //                     : const Text("REGISTER NOW"),
// //               ),
// //           ]))),
// //         ],
// //       ),
// //     );
// //   }
// //
// //   void _showNameInputDialog(List<double> embedding) {
// //     TextEditingController nameController = TextEditingController();
// //     showDialog(context: context, builder: (c) => AlertDialog(title: const Text("Register Name"),
// //         content: TextField(controller: nameController),
// //         actions: [ElevatedButton(
// //         onPressed: () async {
// //     String inputName = nameController.text.trim();
// //
// //     if (inputName.isEmpty) {
// //     _showTopNotification("Please enter a name", true);
// //     return;
// //     }
// //
// //
// //     String? existingUserName = _identifyUser(embedding);
// //
// //
// //     if (existingUserName != null) {
// //
// //     _showTopNotification(
// //     "Already registered as: '$existingUserName' .",
// //     true
// //     );
// //     return;
// //     }
// //
// //     await _dbService.registerUser(inputName, embedding);
// //
// //     if (mounted) {
// //     Navigator.pop(context);
// //     initializeCamera();
// //     _showTopNotification("Registration Successful!", false);
// //     }
// //     }, child: const Text("Save"))]));
// //   }
// // }
// //
// // class FacePainter extends CustomPainter {
// //   final List<Face> faces;
// //   final Size imageSize;
// //   FacePainter({required this.faces, required this.imageSize});
// //   @override
// //   void paint(Canvas canvas, Size size) {
// //     final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = 3.0..color = Colors.greenAccent;
// //     for (var face in faces) {
// //       double scaleX = size.width / imageSize.height;
// //       double scaleY = size.height / imageSize.width;
// //       canvas.drawRect(Rect.fromLTRB(face.boundingBox.left * scaleX, face.boundingBox.top * scaleY, face.boundingBox.right * scaleX, face.boundingBox.bottom * scaleY), paint);
// //     }
// //   }
// //   @override
// //   bool shouldRepaint(FacePainter oldDelegate) => true;
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
// // // import 'package:camera/camera.dart';
// // // import 'package:flutter/material.dart';
// // // import 'package:geolocator/geolocator.dart';
// // // import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
// // // import 'all_employees_attendace_list.dart';
// // // import 'main.dart';
// // // import 'ml_service.dart';
// // // import 'db_service.dart';
// // // import 'result_screen.dart';
// // //
// // // class AttendanceScreen extends StatefulWidget {
// // //   const AttendanceScreen({super.key});
// // //
// // //   @override
// // //   State<AttendanceScreen> createState() => _AttendanceScreenState();
// // // }
// // //
// // // class _AttendanceScreenState extends State<AttendanceScreen> {
// // //   final MLService _mlService = MLService();
// // //   final DBService _dbService = DBService();
// // //
// // //   CameraController? _controller;
// // //   late FaceDetector _faceDetector;
// // //
// // //   bool _isDetecting = false;
// // //   bool _registerMode = false;
// // //   bool _isInsideLocation = false;
// // //   double _currentDistance = 0.0;
// // //
// // //   // FACE TIMER LOGIC
// // //   DateTime? _faceFirstSeenTime;
// // //   bool _isAlertShown = false; // Taki baar baar alert na aaye
// // //
// // //   double targetLat = 0.0;
// // //   double targetLng = 0.0;
// // //   double allowedRadius = 50;
// // //
// // //   List<Face> _faces = [];
// // //   CameraImage? _savedImage;
// // //
// // //   @override
// // //   void initState() {
// // //     super.initState();
// // //     _loadSettings();
// // //     _faceDetector = FaceDetector(options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast));
// // //     initializeCamera();
// // //     _startLocationTimer();
// // //   }
// // //
// // //   void _loadSettings() {
// // //     double savedLat = _dbService.getOfficeLat();
// // //     double savedLng = _dbService.getOfficeLng();
// // //     setState(() {
// // //       targetLat = savedLat;
// // //       targetLng = savedLng;
// // //     });
// // //   }
// // //
// // //   @override
// // //   void dispose() {
// // //     _controller?.dispose();
// // //     _faceDetector.close();
// // //     super.dispose();
// // //   }
// // //
// // //   void _startLocationTimer() async {
// // //     while (mounted) {
// // //       await _checkLocation();
// // //       await Future.delayed(const Duration(seconds: 3));
// // //     }
// // //   }
// // //
// // //   Future<void> _checkLocation() async {
// // //     try {
// // //       Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
// // //       double distance = Geolocator.distanceBetween(position.latitude, position.longitude, targetLat, targetLng);
// // //       if (mounted) {
// // //         setState(() {
// // //           _currentDistance = distance;
// // //           _isInsideLocation = (distance <= allowedRadius);
// // //         });
// // //       }
// // //     } catch (e) {
// // //       debugPrint("GPS Error: $e");
// // //     }
// // //   }
// // //
// // //   void _showSettingsDialog() {
// // //     TextEditingController latController = TextEditingController(text: targetLat.toString());
// // //     TextEditingController lngController = TextEditingController(text: targetLng.toString());
// // //
// // //     showDialog(
// // //       context: context,
// // //       barrierDismissible: false,
// // //       builder: (context) => AlertDialog(
// // //         title: const Text("Set Office Location"),
// // //         content: Column(
// // //           mainAxisSize: MainAxisSize.min,
// // //           children: [
// // //             const Text("Check coordinates carefully!", style: TextStyle(fontSize: 12, color: Colors.red)),
// // //             TextField(controller: latController, decoration: const InputDecoration(labelText: "Latitude"), keyboardType: TextInputType.number),
// // //             TextField(controller: lngController, decoration: const InputDecoration(labelText: "Longitude"), keyboardType: TextInputType.number),
// // //           ],
// // //         ),
// // //         actions: [
// // //           TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
// // //           ElevatedButton(
// // //             onPressed: () async {
// // //               double? nLat = double.tryParse(latController.text.trim());
// // //               double? nLng = double.tryParse(lngController.text.trim());
// // //               if (nLat != null && nLng != null) {
// // //                 await _dbService.saveOfficeLocation(nLat, nLng);
// // //                 _loadSettings();
// // //                 await _checkLocation();
// // //                 if (mounted) Navigator.pop(context);
// // //               }
// // //             },
// // //             child: const Text("Save & Refresh"),
// // //           ),
// // //         ],
// // //       ),
// // //     );
// // //   }
// // //
// // //   void initializeCamera() async {
// // //     if (cameras.isEmpty) return;
// // //     _controller = CameraController(cameras[1], ResolutionPreset.medium, enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
// // //     await _controller!.initialize();
// // //     if (mounted) setState(() {});
// // //     _controller?.startImageStream((image) {
// // //       _savedImage = image;
// // //       if (!_isDetecting) _doFaceDetection(image);
// // //     });
// // //   }
// // //
// // //   Future<void> _doFaceDetection(CameraImage image) async {
// // //     if (_isDetecting || !mounted) return;
// // //     _isDetecting = true;
// // //     try {
// // //       final inputImage = _convertCameraImage(image);
// // //       if (inputImage != null) {
// // //         final faces = await _faceDetector.processImage(inputImage);
// // //         if (mounted) setState(() => _faces = faces);
// // //
// // //         if (faces.isEmpty) {
// // //           _faceFirstSeenTime = null; // Face chala gaya toh timer reset
// // //           _isAlertShown = false;
// // //         } else if (!_registerMode && _isInsideLocation) {
// // //           // Timer start karo agar face pehli baar dikha hai
// // //           _faceFirstSeenTime ??= DateTime.now();
// // //
// // //           List<double> embedding = await _mlService.getEmbedding(image, faces[0]);
// // //           String? name = _identifyUser(embedding);
// // //
// // //           if (name != null) {
// // //             _faceFirstSeenTime = null; // Match ho gaya toh timer reset
// // //             await _dbService.saveAttendanceLog(name);
// // //             await _controller?.stopImageStream();
// // //             if (mounted) {
// // //               _showTopNotification("Success: $name", false);
// // //               Navigator.push(context, MaterialPageRoute(builder: (context) => ResultScreen(name: name, imagePath: ""))).then((_) => initializeCamera());
// // //             }
// // //           } else {
// // //             // Agar 5 seconds tak match nahi hua toh alert dikhao
// // //             final duration = DateTime.now().difference(_faceFirstSeenTime!);
// // //             if (duration.inSeconds >= 5 && !_isAlertShown) {
// // //               _isAlertShown = true;
// // //               _showRegisterAlert();
// // //             }
// // //           }
// // //         }
// // //       }
// // //     } catch (e) { debugPrint("AI Error: $e"); }
// // //     await Future.delayed(const Duration(milliseconds: 200));
// // //     _isDetecting = false;
// // //   }
// // //
// // //   // --- REGISTER ALERT FUNCTION ---
// // //   void _showRegisterAlert() {
// // //     showDialog(
// // //       context: context,
// // //       builder: (context) => AlertDialog(
// // //         title: const Text("User Not Found"),
// // //         content: const Text("Your face is not registered in our system. Please register your face first."),
// // //         actions: [
// // //           ElevatedButton(
// // //             onPressed: () {
// // //               Navigator.pop(context);
// // //               setState(() => _registerMode = true); // Automatic Register Mode on
// // //             },
// // //             child: const Text("OK"),
// // //           ),
// // //         ],
// // //       ),
// // //     );
// // //   }
// // //
// // //   String? _identifyUser(List<double> newEmbedding) {
// // //     Map users = _dbService.getAllUsers();
// // //     double minDistance = 1.0;
// // //     String? foundName;
// // //     users.forEach((name, storedEmbedding) {
// // //       if (name == 'office_lat' || name == 'office_lng') return;
// // //       double distance = _mlService.calculateDistance(newEmbedding, List<double>.from(storedEmbedding));
// // //       if (distance < minDistance) { minDistance = distance; foundName = name; }
// // //     });
// // //     return (minDistance < 0.8) ? foundName : null;
// // //   }
// // //
// // //   void _showTopNotification(String m, bool err) {
// // //     OverlayEntry entry = OverlayEntry(builder: (c) => Positioned(top: 100, left: 20, right: 20, child: Material(color: Colors.transparent, child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: err ? Colors.red : Colors.green, borderRadius: BorderRadius.circular(10)), child: Text(m, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))))));
// // //     Overlay.of(context).insert(entry);
// // //     Future.delayed(const Duration(seconds: 2), () => entry.remove());
// // //   }
// // //
// // //   InputImage? _convertCameraImage(CameraImage image) {
// // //     return InputImage.fromBytes(bytes: _mlService.concatenatePlanes(image.planes), metadata: InputImageMetadata(size: Size(image.width.toDouble(), image.height.toDouble()), rotation: InputImageRotation.rotation270deg, format: InputImageFormat.nv21, bytesPerRow: image.planes[0].bytesPerRow));
// // //   }
// // //
// // //   @override
// // //   Widget build(BuildContext context) {
// // //     return Scaffold(
// // //       appBar: AppBar(
// // //         title: const Text("Face Scanner"),
// // //         actions: [
// // //           IconButton(icon: const Icon(Icons.location_on,color: Colors.green,), onPressed: _showSettingsDialog),
// // //           IconButton(icon: const Icon(Icons.history,color: Colors.blueGrey,), onPressed: () async {
// // //             await _controller?.stopImageStream();
// // //             if (mounted) {
// // //               Navigator.push(context, MaterialPageRoute(builder: (c) => const AttendanceHistoryScreen())).then((_) => initializeCamera());
// // //             }
// // //           }),
// // //         ],
// // //       ),
// // //       backgroundColor: Colors.black,
// // //       body: Stack(
// // //         children: [
// // //           if (_controller != null && _controller!.value.isInitialized)
// // //             Positioned.fill(child: CameraPreview(_controller!, child: CustomPaint(painter: FacePainter(faces: _faces, imageSize: _controller!.value.previewSize!)))),
// // //
// // //           Positioned(
// // //             top: 0, left: 0, right: 0,
// // //             child: Container(
// // //               color: _isInsideLocation ? Colors.green.withOpacity(0.9) : Colors.red.withOpacity(0.9),
// // //               padding: const EdgeInsets.all(12),
// // //               child: Column(
// // //                 children: [
// // //                   Text(_isInsideLocation ? "LOCATION: OK" : "LOCATION: WRONG",
// // //                       style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
// // //                   Text("Meters Away: ${_currentDistance.toStringAsFixed(1)}m",
// // //                       style: const TextStyle(color: Colors.white, fontSize: 13)),
// // //                 ],
// // //               ),
// // //             ),
// // //           ),
// // //
// // //           Positioned(bottom: 0, left: 0, right: 0, child: Container(padding: const EdgeInsets.all(25), decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(30))), child: Column(mainAxisSize: MainAxisSize.min, children: [
// // //             Row(mainAxisAlignment: MainAxisAlignment.center, children: [
// // //               const Text("Attendance"), Switch(value: _registerMode, onChanged: (v) => setState(() => _registerMode = v)), const Text("Register"),
// // //             ]),
// // //             if (_registerMode) ElevatedButton(onPressed: () async {
// // //               if (_faces.isEmpty) return;
// // //               await _controller?.stopImageStream();
// // //               List<double> emb = await _mlService.getEmbedding(_savedImage!, _faces[0]);
// // //               _showNameInputDialog(emb);
// // //             }, child: const Text("REGISTER NOW")),
// // //           ]))),
// // //         ],
// // //       ),
// // //     );
// // //   }
// // //
// // //   void _showNameInputDialog(List<double> embedding) {
// // //     TextEditingController nameController = TextEditingController();
// // //     showDialog(context: context, builder: (c) => AlertDialog(title: const Text("Register Name"), content: TextField(controller: nameController), actions: [ElevatedButton(onPressed: () async { await _dbService.registerUser(nameController.text, embedding); Navigator.pop(context); initializeCamera(); }, child: const Text("Save"))]));
// // //   }
// // // }
// // //
// // // class FacePainter extends CustomPainter {
// // //   final List<Face> faces;
// // //   final Size imageSize;
// // //   FacePainter({required this.faces, required this.imageSize});
// // //   @override
// // //   void paint(Canvas canvas, Size size) {
// // //     final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = 3.0..color = Colors.greenAccent;
// // //     for (var face in faces) {
// // //       double scaleX = size.width / imageSize.height;
// // //       double scaleY = size.height / imageSize.width;
// // //       canvas.drawRect(Rect.fromLTRB(face.boundingBox.left * scaleX, face.boundingBox.top * scaleY, face.boundingBox.right * scaleX, face.boundingBox.bottom * scaleY), paint);
// // //     }
// // //   }
// // //   @override
// // //   bool shouldRepaint(FacePainter oldDelegate) => true;
// // // }
// // //
// //
// //
// //
// //
// // //correct one---------------------------------
// // // import 'package:camera/camera.dart';
// // // import 'package:flutter/material.dart';
// // // import 'package:geolocator/geolocator.dart';
// // // import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
// // // import 'all_employees_attendace_list.dart';
// // // import 'main.dart';
// // // import 'ml_service.dart';
// // // import 'db_service.dart';
// // // import 'result_screen.dart';
// // //
// // // class AttendanceScreen extends StatefulWidget {
// // //   const AttendanceScreen({super.key});
// // //
// // //   @override
// // //   State<AttendanceScreen> createState() => _AttendanceScreenState();
// // // }
// // //
// // // class _AttendanceScreenState extends State<AttendanceScreen> {
// // //   final MLService _mlService = MLService();
// // //   final DBService _dbService = DBService();
// // //
// // //   CameraController? _controller;
// // //   late FaceDetector _faceDetector;
// // //
// // //   bool _isDetecting = false;
// // //   bool _registerMode = false;
// // //   bool _isInsideLocation = false;
// // //   double _currentDistance = 0.0;
// // //
// // //   double targetLat = 0.0;
// // //   double targetLng = 0.0;
// // //   double allowedRadius = 50; // Radius 250 meters tak rakha hai
// // //
// // //   List<Face> _faces = [];
// // //   CameraImage? _savedImage;
// // //
// // //   @override
// // //   void initState() {
// // //     super.initState();
// // //     _loadSettings();
// // //     _faceDetector = FaceDetector(options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast));
// // //     initializeCamera();
// // //     _startLocationTimer();
// // //   }
// // //
// // //   void _loadSettings() {
// // //     // Database se data nikal kar variables mein daalna
// // //     double savedLat = _dbService.getOfficeLat();
// // //     double savedLng = _dbService.getOfficeLng();
// // //
// // //     setState(() {
// // //       targetLat = savedLat;
// // //       targetLng = savedLng;
// // //     });
// // //     debugPrint("Loaded Coordinates: $targetLat, $targetLng");
// // //   }
// // //
// // //   @override
// // //   void dispose() {
// // //     _controller?.dispose();
// // //     _faceDetector.close();
// // //     super.dispose();
// // //   }
// // //
// // //   void _startLocationTimer() async {
// // //     while (mounted) {
// // //       await _checkLocation();
// // //       await Future.delayed(const Duration(seconds: 3));
// // //     }
// // //   }
// // //
// // //   Future<void> _checkLocation() async {
// // //     try {
// // //       // Direct high accuracy position
// // //       Position position = await Geolocator.getCurrentPosition(
// // //         desiredAccuracy: LocationAccuracy.best,
// // //       );
// // //
// // //       double distance = Geolocator.distanceBetween(
// // //           position.latitude, position.longitude, targetLat, targetLng
// // //       );
// // //
// // //       if (mounted) {
// // //         setState(() {
// // //           _currentDistance = distance;
// // //           _isInsideLocation = (distance <= allowedRadius);
// // //         });
// // //       }
// // //     } catch (e) {
// // //       debugPrint("GPS Error: $e");
// // //     }
// // //   }
// // //
// // //   void _showSettingsDialog() {
// // //     TextEditingController latController = TextEditingController(text: targetLat.toString());
// // //     TextEditingController lngController = TextEditingController(text: targetLng.toString());
// // //
// // //     showDialog(
// // //       context: context,
// // //       barrierDismissible: false,
// // //       builder: (context) => AlertDialog(
// // //         title: const Text("Set Office Location"),
// // //         content: Column(
// // //           mainAxisSize: MainAxisSize.min,
// // //           children: [
// // //             const Text("Check coordinates carefully!", style: TextStyle(fontSize: 12, color: Colors.red)),
// // //             TextField(controller: latController, decoration: const InputDecoration(labelText: "Latitude (e.g. 30.90)"), keyboardType: TextInputType.number),
// // //             TextField(controller: lngController, decoration: const InputDecoration(labelText: "Longitude (e.g. 75.85)"), keyboardType: TextInputType.number),
// // //           ],
// // //         ),
// // //         actions: [
// // //           TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
// // //           ElevatedButton(
// // //             onPressed: () async {
// // //               double? nLat = double.tryParse(latController.text.trim());
// // //               double? nLng = double.tryParse(lngController.text.trim());
// // //
// // //               if (nLat != null && nLng != null) {
// // //                 // Database mein save karo
// // //                 await _dbService.saveOfficeLocation(nLat, nLng);
// // //                 // Variables update karo
// // //                 _loadSettings();
// // //                 // Turant check karo
// // //                 await _checkLocation();
// // //                 if (mounted) Navigator.pop(context);
// // //                 _showTopNotification("Location Updated!", false);
// // //               } else {
// // //                 _showTopNotification("Invalid Coordinates!", true);
// // //               }
// // //             },
// // //             child: const Text("Save & Refresh"),
// // //           ),
// // //         ],
// // //       ),
// // //     );
// // //   }
// // //
// // //   void initializeCamera() async {
// // //     if (cameras.isEmpty) return;
// // //     _controller = CameraController(cameras[1], ResolutionPreset.medium, enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
// // //     await _controller!.initialize();
// // //     if (mounted) setState(() {});
// // //     _controller?.startImageStream((image) {
// // //       _savedImage = image;
// // //       if (!_isDetecting) _doFaceDetection(image);
// // //     });
// // //   }
// // //
// // //   Future<void> _doFaceDetection(CameraImage image) async {
// // //     if (_isDetecting || !mounted) return;
// // //     _isDetecting = true;
// // //     try {
// // //       final inputImage = _convertCameraImage(image);
// // //       if (inputImage != null) {
// // //         final faces = await _faceDetector.processImage(inputImage);
// // //         if (mounted) setState(() => _faces = faces);
// // //
// // //         // Attendance Logic tabhi chalega jab Location OK ho
// // //         if (faces.isNotEmpty && !_registerMode && _isInsideLocation) {
// // //           List<double> embedding = await _mlService.getEmbedding(image, faces[0]);
// // //           String? name = _identifyUser(embedding);
// // //
// // //           if (name != null) {
// // //             await _dbService.saveAttendanceLog(name);
// // //             await _controller?.stopImageStream();
// // //             if (mounted) {
// // //               _showTopNotification("Success: $name", false);
// // //               Navigator.push(context, MaterialPageRoute(builder: (context) => ResultScreen(name: name, imagePath: ""))).then((_) => initializeCamera());
// // //             }
// // //           }
// // //         }
// // //       }
// // //     } catch (e) { debugPrint("AI Error: $e"); }
// // //     await Future.delayed(const Duration(milliseconds: 200));
// // //     _isDetecting = false;
// // //   }
// // //
// // //   String? _identifyUser(List<double> newEmbedding) {
// // //     Map users = _dbService.getAllUsers();
// // //     double minDistance = 1.0;
// // //     String? foundName;
// // //     users.forEach((name, storedEmbedding) {
// // //       if (name == 'office_lat' || name == 'office_lng') return;
// // //       double distance = _mlService.calculateDistance(newEmbedding, List<double>.from(storedEmbedding));
// // //       if (distance < minDistance) { minDistance = distance; foundName = name; }
// // //     });
// // //     return (minDistance < 0.8) ? foundName : null;
// // //   }
// // //
// // //   void _showTopNotification(String m, bool err) {
// // //     OverlayEntry entry = OverlayEntry(builder: (c) => Positioned(top: 100, left: 20, right: 20, child: Material(color: Colors.transparent, child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: err ? Colors.red : Colors.green, borderRadius: BorderRadius.circular(10)), child: Text(m, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))))));
// // //     Overlay.of(context).insert(entry);
// // //     Future.delayed(const Duration(seconds: 2), () => entry.remove());
// // //   }
// // //
// // //   InputImage? _convertCameraImage(CameraImage image) {
// // //     return InputImage.fromBytes(bytes: _mlService.concatenatePlanes(image.planes), metadata: InputImageMetadata(size: Size(image.width.toDouble(), image.height.toDouble()), rotation: InputImageRotation.rotation270deg, format: InputImageFormat.nv21, bytesPerRow: image.planes[0].bytesPerRow));
// // //   }
// // //
// // //   @override
// // //   Widget build(BuildContext context) {
// // //     return Scaffold(
// // //       appBar: AppBar(
// // //         title: const Text("Face Scanner"),
// // //         actions: [
// // //           // Icon(Icons.location_on, color: _isInsideLocation ? Colors.green : Colors.red),
// // //           IconButton(icon: const Icon(Icons.location_on,color: Colors.green,), onPressed: _showSettingsDialog),
// // //           IconButton(icon: const Icon(Icons.history,color: Colors.blueGrey,), onPressed: () async {
// // //             await _controller?.stopImageStream();
// // //             if (mounted) {
// // //               Navigator.push(context, MaterialPageRoute(builder: (c) => const AttendanceHistoryScreen())).then((_) => initializeCamera());
// // //             }
// // //           }),
// // //         ],
// // //       ),
// // //       backgroundColor: Colors.black,
// // //       body: Stack(
// // //         children: [
// // //           if (_controller != null && _controller!.value.isInitialized)
// // //             Positioned.fill(child: CameraPreview(_controller!, child: CustomPaint(painter: FacePainter(faces: _faces, imageSize: _controller!.value.previewSize!)))),
// // //
// // //           // --- REAL-TIME STATUS BAR ---
// // //           Positioned(
// // //             top: 0, left: 0, right: 0,
// // //             child: Container(
// // //               color: _isInsideLocation ? Colors.green.withOpacity(0.9) : Colors.red.withOpacity(0.9),
// // //               padding: const EdgeInsets.all(12),
// // //               child: Column(
// // //                 children: [
// // //                   Text(_isInsideLocation ? "LOCATION: OK" : "LOCATION: WRONG",
// // //                       style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
// // //                   Text("Meters Away: ${_currentDistance.toStringAsFixed(1)}m",
// // //                       style: const TextStyle(color: Colors.white, fontSize: 13)),
// // //                   Text("Actual Target: ${targetLat.toStringAsFixed(4)}, ${targetLng.toStringAsFixed(4)}",
// // //                       style: const TextStyle(color: Colors.white70, fontSize: 10)),
// // //                 ],
// // //               ),
// // //             ),
// // //           ),
// // //
// // //           Positioned(bottom: 0, left: 0, right: 0, child: Container(padding: const EdgeInsets.all(25), decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(30))), child: Column(mainAxisSize: MainAxisSize.min, children: [
// // //             Row(mainAxisAlignment: MainAxisAlignment.center, children: [
// // //               const Text("Attendance"), Switch(value: _registerMode, onChanged: (v) => setState(() => _registerMode = v)), const Text("Register"),
// // //             ]),
// // //             if (_registerMode) ElevatedButton(onPressed: () async {
// // //               if (_faces.isEmpty) return;
// // //               await _controller?.stopImageStream();
// // //               List<double> emb = await _mlService.getEmbedding(_savedImage!, _faces[0]);
// // //               _showNameInputDialog(emb);
// // //             }, child: const Text("REGISTER NOW")),
// // //           ]))),
// // //         ],
// // //       ),
// // //     );
// // //   }
// // //
// // //   void _showNameInputDialog(List<double> embedding) {
// // //     TextEditingController nameController = TextEditingController();
// // //     showDialog(context: context, builder: (c) => AlertDialog(title: const Text("Register Name"), content: TextField(controller: nameController), actions: [ElevatedButton(onPressed: () async { await _dbService.registerUser(nameController.text, embedding); Navigator.pop(context); initializeCamera(); }, child: const Text("Save"))]));
// // //   }
// // // }
// // //
// // // class FacePainter extends CustomPainter {
// // //   final List<Face> faces;
// // //   final Size imageSize;
// // //   FacePainter({required this.faces, required this.imageSize});
// // //   @override
// // //   void paint(Canvas canvas, Size size) {
// // //     final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = 3.0..color = Colors.greenAccent;
// // //     for (var face in faces) {
// // //       double scaleX = size.width / imageSize.height;
// // //       double scaleY = size.height / imageSize.width;
// // //       canvas.drawRect(Rect.fromLTRB(face.boundingBox.left * scaleX, face.boundingBox.top * scaleY, face.boundingBox.right * scaleX, face.boundingBox.bottom * scaleY), paint);
// // //     }
// // //   }
// // //   @override
// // //   bool shouldRepaint(FacePainter oldDelegate) => true;
// // // }
// // //
// // //
// // //
// // //
// // //
// // //
// // //
// // //
// // //
// // //
// // //
// // //
// // //
// // //
// // //
// // //
// // //
// // //
// // //
// // //
// // //
// // //
// // // // import 'package:camera/camera.dart';
// // // // import 'package:flutter/material.dart';
// // // // import 'package:geolocator/geolocator.dart';
// // // // import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
// // // // import 'all_employees_attendace_list.dart';
// // // // import 'main.dart';
// // // // import 'ml_service.dart';
// // // // import 'db_service.dart';
// // // // import 'result_screen.dart';
// // // //
// // // // class AttendanceScreen extends StatefulWidget {
// // // //   const AttendanceScreen({super.key});
// // // //
// // // //   @override
// // // //   State<AttendanceScreen> createState() => _AttendanceScreenState();
// // // // }
// // // //
// // // // class _AttendanceScreenState extends State<AttendanceScreen> {
// // // //   final MLService _mlService = MLService();
// // // //   final DBService _dbService = DBService();
// // // //
// // // //   CameraController? _controller;
// // // //   late FaceDetector _faceDetector;
// // // //
// // // //   bool _isDetecting = false;
// // // //   bool _registerMode = false;
// // // //   bool _isInsideLocation = false;
// // // //   double _currentDistance = 0.0;
// // // //
// // // //   double targetLat = 0.0;
// // // //   double targetLng = 0.0;
// // // //   double allowedRadius = 200; // 200 Meters
// // // //
// // // //   List<Face> _faces = [];
// // // //   CameraImage? _savedImage;
// // // //
// // // //   @override
// // // //   void initState() {
// // // //     super.initState();
// // // //     _refreshLocationData(); // DB se data uthayega
// // // //     _faceDetector = FaceDetector(options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast));
// // // //     initializeCamera();
// // // //     _startLocationTimer();
// // // //   }
// // // //
// // // //   // Database se fresh coordinates nikalne ke liye
// // // //   void _refreshLocationData() {
// // // //     setState(() {
// // // //       targetLat = _dbService.getOfficeLat();
// // // //       targetLng = _dbService.getOfficeLng();
// // // //     });
// // // //   }
// // // //
// // // //   @override
// // // //   void dispose() {
// // // //     _controller?.dispose();
// // // //     _faceDetector.close();
// // // //     super.dispose();
// // // //   }
// // // //
// // // //   void _startLocationTimer() async {
// // // //     while (mounted) {
// // // //       await _checkLocation();
// // // //       await Future.delayed(const Duration(seconds: 3));
// // // //     }
// // // //   }
// // // //
// // // //   Future<void> _checkLocation() async {
// // // //     try {
// // // //       Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
// // // //
// // // //       double distance = Geolocator.distanceBetween(
// // // //           position.latitude, position.longitude, targetLat, targetLng
// // // //       );
// // // //
// // // //       if (mounted) {
// // // //         setState(() {
// // // //           _currentDistance = distance;
// // // //           // Agar target 0.0 hai toh matlab location set nahi hui
// // // //           _isInsideLocation = (targetLat != 0.0) && (distance <= allowedRadius);
// // // //         });
// // // //       }
// // // //     } catch (e) {
// // // //       debugPrint("GPS Error: $e");
// // // //     }
// // // //   }
// // // //
// // // //   // --- NAYA AUTO-LOCATION DIALOG ---
// // // //   void _showSettingsDialog() {
// // // //     showDialog(
// // // //       context: context,
// // // //       builder: (context) => AlertDialog(
// // // //         title: const Text("Location Settings"),
// // // //         content: Column(
// // // //           mainAxisSize: MainAxisSize.min,
// // // //           children: [
// // // //             Text("Target: ${targetLat.toStringAsFixed(4)}, ${targetLng.toStringAsFixed(4)}"),
// // // //             const SizedBox(height: 10),
// // // //             const Text("Tip: Jahan khade ho wahi office location set karne ke liye niche wala button dabayein.", style: TextStyle(fontSize: 12)),
// // // //           ],
// // // //         ),
// // // //         actions: [
// // // //           TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close")),
// // // //           ElevatedButton(
// // // //               style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
// // // //               onPressed: () async {
// // // //                 // Current position uthao aur wahi save kar do
// // // //                 Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
// // // //                 await _dbService.saveOfficeLocation(pos.latitude, pos.longitude);
// // // //                 _refreshLocationData();
// // // //                 Navigator.pop(context);
// // // //                 _showTopNotification("Office Location Set Successfully!", false);
// // // //               },
// // // //               child: const Text("SET CURRENT AS OFFICE", style: TextStyle(color: Colors.white))
// // // //           ),
// // // //         ],
// // // //       ),
// // // //     );
// // // //   }
// // // //
// // // //   void initializeCamera() async {
// // // //     if (cameras.isEmpty) return;
// // // //     _controller = CameraController(cameras[1], ResolutionPreset.medium, enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
// // // //     await _controller!.initialize();
// // // //     if (mounted) setState(() {});
// // // //     _controller?.startImageStream((image) {
// // // //       _savedImage = image;
// // // //       if (!_isDetecting) _doFaceDetection(image);
// // // //     });
// // // //   }
// // // //
// // // //   Future<void> _doFaceDetection(CameraImage image) async {
// // // //     if (_isDetecting || !mounted) return;
// // // //     _isDetecting = true;
// // // //     try {
// // // //       final inputImage = _convertCameraImage(image);
// // // //       if (inputImage != null) {
// // // //         final faces = await _faceDetector.processImage(inputImage);
// // // //         if (mounted) setState(() => _faces = faces);
// // // //
// // // //         // Sirf tabhi kaam karega jab location "OK" ho
// // // //         if (faces.isNotEmpty && !_registerMode && _isInsideLocation) {
// // // //           List<double> embedding = await _mlService.getEmbedding(image, faces[0]);
// // // //           String? name = _identifyUser(embedding);
// // // //
// // // //           if (name != null) {
// // // //             await _dbService.saveAttendanceLog(name);
// // // //             await _controller?.stopImageStream();
// // // //             if (mounted) {
// // // //               _showTopNotification("Success: $name", false);
// // // //               Navigator.push(context, MaterialPageRoute(builder: (context) => ResultScreen(name: name, imagePath: ""))).then((_) => initializeCamera());
// // // //             }
// // // //           }
// // // //         }
// // // //       }
// // // //     } catch (e) { debugPrint("AI Error: $e"); }
// // // //     await Future.delayed(const Duration(milliseconds: 200));
// // // //     _isDetecting = false;
// // // //   }
// // // //
// // // //   String? _identifyUser(List<double> newEmbedding) {
// // // //     Map users = _dbService.getAllUsers();
// // // //     double minDistance = 1.0;
// // // //     String? foundName;
// // // //     users.forEach((name, storedEmbedding) {
// // // //       if (name == 'office_lat' || name == 'office_lng') return;
// // // //       double distance = _mlService.calculateDistance(newEmbedding, List<double>.from(storedEmbedding));
// // // //       if (distance < minDistance) { minDistance = distance; foundName = name; }
// // // //     });
// // // //     return (minDistance < 0.8) ? foundName : null;
// // // //   }
// // // //
// // // //   void _showTopNotification(String m, bool err) {
// // // //     OverlayEntry entry = OverlayEntry(builder: (c) => Positioned(top: 100, left: 20, right: 20, child: Material(color: Colors.transparent, child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: err ? Colors.red : Colors.green, borderRadius: BorderRadius.circular(10)), child: Text(m, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))))));
// // // //     Overlay.of(context).insert(entry);
// // // //     Future.delayed(const Duration(seconds: 2), () => entry.remove());
// // // //   }
// // // //
// // // //   InputImage? _convertCameraImage(CameraImage image) {
// // // //     return InputImage.fromBytes(bytes: _mlService.concatenatePlanes(image.planes), metadata: InputImageMetadata(size: Size(image.width.toDouble(), image.height.toDouble()), rotation: InputImageRotation.rotation270deg, format: InputImageFormat.nv21, bytesPerRow: image.planes[0].bytesPerRow));
// // // //   }
// // // //
// // // //   @override
// // // //   Widget build(BuildContext context) {
// // // //     return Scaffold(
// // // //       appBar: AppBar(
// // // //         title: const Text("Face Scanner"),
// // // //         actions: [
// // // //           Icon(Icons.location_on, color: _isInsideLocation ? Colors.green : Colors.red),
// // // //           IconButton(icon: const Icon(Icons.my_location), onPressed: _showSettingsDialog),
// // // //           IconButton(icon: const Icon(Icons.history), onPressed: () async {
// // // //             await _controller?.stopImageStream();
// // // //             if (mounted) {
// // // //               Navigator.push(context, MaterialPageRoute(builder: (c) => const AttendanceHistoryScreen())).then((_) => initializeCamera());
// // // //             }
// // // //           }),
// // // //         ],
// // // //       ),
// // // //       backgroundColor: Colors.black,
// // // //       body: Stack(
// // // //         children: [
// // // //           if (_controller != null && _controller!.value.isInitialized)
// // // //             Positioned.fill(child: CameraPreview(_controller!, child: CustomPaint(painter: FacePainter(faces: _faces, imageSize: _controller!.value.previewSize!)))),
// // // //
// // // //           // --- TOP STATUS BAR ---
// // // //           Positioned(
// // // //             top: 0, left: 0, right: 0,
// // // //             child: Container(
// // // //               color: _isInsideLocation ? Colors.green.withOpacity(0.8) : Colors.red.withOpacity(0.8),
// // // //               padding: const EdgeInsets.all(10),
// // // //               child: Column(
// // // //                 children: [
// // // //                   Text(_isInsideLocation ? "LOCATION: OK" : "LOCATION: WRONG", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
// // // //                   Text("Distance: ${_currentDistance.toStringAsFixed(1)}m", style: const TextStyle(color: Colors.white, fontSize: 12)),
// // // //                   if (targetLat == 0.0) const Text("PLEASE SET OFFICE LOCATION FIRST!", style: TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold, fontSize: 10)),
// // // //                 ],
// // // //               ),
// // // //             ),
// // // //           ),
// // // //
// // // //           Positioned(bottom: 0, left: 0, right: 0, child: Container(padding: const EdgeInsets.all(25), decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(30))), child: Column(mainAxisSize: MainAxisSize.min, children: [
// // // //             Row(mainAxisAlignment: MainAxisAlignment.center, children: [
// // // //               const Text("Attendance"), Switch(value: _registerMode, onChanged: (v) => setState(() => _registerMode = v)), const Text("Register"),
// // // //             ]),
// // // //             if (_registerMode) ElevatedButton(onPressed: () async {
// // // //               if (_faces.isEmpty) return;
// // // //               await _controller?.stopImageStream();
// // // //               List<double> emb = await _mlService.getEmbedding(_savedImage!, _faces[0]);
// // // //               _showNameInputDialog(emb);
// // // //             }, child: const Text("REGISTER NOW")),
// // // //           ]))),
// // // //         ],
// // // //       ),
// // // //     );
// // // //   }
// // // //
// // // //   void _showNameInputDialog(List<double> embedding) {
// // // //     TextEditingController nameController = TextEditingController();
// // // //     showDialog(context: context, builder: (c) => AlertDialog(title: const Text("Register Name"), content: TextField(controller: nameController), actions: [ElevatedButton(onPressed: () async { await _dbService.registerUser(nameController.text, embedding); Navigator.pop(context); initializeCamera(); }, child: const Text("Save"))]));
// // // //   }
// // // // }
// // // //
// // // // class FacePainter extends CustomPainter {
// // // //   final List<Face> faces;
// // // //   final Size imageSize;
// // // //   FacePainter({required this.faces, required this.imageSize});
// // // //   @override
// // // //   void paint(Canvas canvas, Size size) {
// // // //     final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = 3.0..color = Colors.greenAccent;
// // // //     for (var face in faces) {
// // // //       double scaleX = size.width / imageSize.height;
// // // //       double scaleY = size.height / imageSize.width;
// // // //       canvas.drawRect(Rect.fromLTRB(face.boundingBox.left * scaleX, face.boundingBox.top * scaleY, face.boundingBox.right * scaleX, face.boundingBox.bottom * scaleY), paint);
// // // //     }
// // // //   }
// // // //   @override
// // // //   bool shouldRepaint(FacePainter oldDelegate) => true;
// // // // }
// // // //
// // // //
// // // // //
// // // // //
// // // // //
// // // // // import 'package:camera/camera.dart';
// // // // // import 'package:flutter/material.dart';
// // // // // import 'package:geolocator/geolocator.dart';
// // // // // import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
// // // // // import 'all_employees_attendace_list.dart';
// // // // // import 'main.dart';
// // // // // import 'ml_service.dart';
// // // // // import 'db_service.dart';
// // // // // import 'result_screen.dart';
// // // // //
// // // // // class AttendanceScreen extends StatefulWidget {
// // // // //   const AttendanceScreen({super.key});
// // // // //
// // // // //   @override
// // // // //   State<AttendanceScreen> createState() => _AttendanceScreenState();
// // // // // }
// // // // //
// // // // // class _AttendanceScreenState extends State<AttendanceScreen> {
// // // // //   final MLService _mlService = MLService();
// // // // //   final DBService _dbService = DBService();
// // // // //
// // // // //   CameraController? _controller;
// // // // //   late FaceDetector _faceDetector;
// // // // //
// // // // //   // LOGIC VARIABLES
// // // // //   DateTime? _faceFirstSeenTime;
// // // // //   bool _isDetecting = false;
// // // // //   bool _registerMode = false;
// // // // //   bool _isInsideLocation = false; // Tracks if user is in the right spot
// // // // //
// // // // //   // COORDINATES
// // // // //   double targetLat = 31.31328;
// // // // //   double targetLng = 75.59;
// // // // //   double allowedRadius = 110;
// // // // //
// // // // //   List<Face> _faces = [];
// // // // //   CameraImage? _savedImage;
// // // // //
// // // // //   @override
// // // // //   void initState() {
// // // // //     super.initState();
// // // // //     // 1. Load saved coordinates from Hive immediately
// // // // //     targetLat = _dbService.getOfficeLat();
// // // // //     targetLng = _dbService.getOfficeLng();
// // // // //
// // // // //     _faceDetector = FaceDetector(options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast));
// // // // //     initializeCamera();
// // // // //
// // // // //     // 2. Start a separate background timer to check location every 3 seconds
// // // // //     // This keeps the face detection loop fast and unblocked
// // // // //     _startLocationTimer();
// // // // //   }
// // // // //
// // // // //   @override
// // // // //   void dispose() {
// // // // //     _controller?.dispose();
// // // // //     _faceDetector.close();
// // // // //     super.dispose();
// // // // //   }
// // // // //
// // // // //   // Separate background location checker
// // // // //   void _startLocationTimer() async {
// // // // //     while (mounted) {
// // // // //       await _checkLocation();
// // // // //       await Future.delayed(const Duration(seconds: 3));
// // // // //     }
// // // // //   }
// // // // //
// // // // //   Future<void> _checkLocation() async {
// // // // //     try {
// // // // //       Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
// // // // //       double distance = Geolocator.distanceBetween(position.latitude, position.longitude, targetLat, targetLng);
// // // // //
// // // // //       if (mounted) {
// // // // //         setState(() {
// // // // //           _isInsideLocation = distance <= allowedRadius;
// // // // //         });
// // // // //       }
// // // // //     } catch (e) {
// // // // //       debugPrint("Location Error: $e");
// // // // //     }
// // // // //   }
// // // // //
// // // // //   void _showSettingsDialog() {
// // // // //     TextEditingController latController = TextEditingController(text: targetLat.toString());
// // // // //     TextEditingController lngController = TextEditingController(text: targetLng.toString());
// // // // //
// // // // //     showDialog(
// // // // //       context: context,
// // // // //       builder: (context) => AlertDialog(
// // // // //         title: const Text("Set Office Location"),
// // // // //         content: Column(
// // // // //           mainAxisSize: MainAxisSize.min,
// // // // //           children: [
// // // // //             TextField(controller: latController, decoration: const InputDecoration(labelText: "Latitude"), keyboardType: TextInputType.number),
// // // // //             TextField(controller: lngController, decoration: const InputDecoration(labelText: "Longitude"), keyboardType: TextInputType.number),
// // // // //           ],
// // // // //         ),
// // // // //         actions: [
// // // // //           TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
// // // // //           ElevatedButton(
// // // // //             onPressed: () async {
// // // // //               double? nLat = double.tryParse(latController.text);
// // // // //               double? nLng = double.tryParse(lngController.text);
// // // // //               if (nLat != null && nLng != null) {
// // // // //                 await _dbService.saveOfficeLocation(nLat, nLng);
// // // // //                 setState(() {
// // // // //                   targetLat = nLat;
// // // // //                   targetLng = nLng;
// // // // //                 });
// // // // //                 Navigator.pop(context);
// // // // //                 _checkLocation(); // Force immediate check
// // // // //               }
// // // // //             },
// // // // //             child: const Text("Save"),
// // // // //           ),
// // // // //         ],
// // // // //       ),
// // // // //     );
// // // // //   }
// // // // //
// // // // //   void initializeCamera() async {
// // // // //     if (cameras.isEmpty) return;
// // // // //     _controller = CameraController(cameras[1], ResolutionPreset.medium, enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
// // // // //     await _controller!.initialize();
// // // // //     if (mounted) setState(() {});
// // // // //     _controller?.startImageStream((image) {
// // // // //       _savedImage = image;
// // // // //       if (!_isDetecting) _doFaceDetection(image);
// // // // //     });
// // // // //   }
// // // // //
// // // // //   Future<void> _doFaceDetection(CameraImage image) async {
// // // // //     _isDetecting = true;
// // // // //     try {
// // // // //       final inputImage = _convertCameraImage(image);
// // // // //       if (inputImage != null) {
// // // // //         final faces = await _faceDetector.processImage(inputImage);
// // // // //         if (mounted) setState(() => _faces = faces);
// // // // //
// // // // //         if (faces.isEmpty) {
// // // // //           _faceFirstSeenTime = null;
// // // // //         } else if (!_registerMode) {
// // // // //           // If we are OUTSIDE, show warning and STOP detection here
// // // // //           if (!_isInsideLocation) {
// // // // //             _showTopNotification("Outside Office Area!", true);
// // // // //             _faceFirstSeenTime = null;
// // // // //           } else {
// // // // //             // INSIDE: Proceed with Face Recognition
// // // // //             _faceFirstSeenTime ??= DateTime.now();
// // // // //             List<double> embedding = await _mlService.getEmbedding(image, faces[0]);
// // // // //             String? name = _identifyUser(embedding);
// // // // //
// // // // //             if (name != null) {
// // // // //               _faceFirstSeenTime = null;
// // // // //               await _dbService.saveAttendanceLog(name);
// // // // //               await _controller?.stopImageStream();
// // // // //               if (mounted) {
// // // // //                 _showTopNotification("Success: $name", false);
// // // // //                 Navigator.push(context, MaterialPageRoute(builder: (context) => ResultScreen(name: name, imagePath: ""))).then((_) => initializeCamera());
// // // // //               }
// // // // //             } else {
// // // // //               final duration = DateTime.now().difference(_faceFirstSeenTime!);
// // // // //               if (duration.inSeconds >= 3) {
// // // // //                 _showTopNotification("Face not matched! Register now.", true);
// // // // //                 _faceFirstSeenTime = null;
// // // // //               }
// // // // //             }
// // // // //           }
// // // // //         }
// // // // //       }
// // // // //     } catch (e) { debugPrint("AI Error: $e"); }
// // // // //     await Future.delayed(const Duration(milliseconds: 200));
// // // // //     _isDetecting = false;
// // // // //   }
// // // // //
// // // // //   // Helper Methods (Same as before)
// // // // //   String? _identifyUser(List<double> newEmbedding) {
// // // // //     Map users = _dbService.getAllUsers();
// // // // //     double minDistance = 1.0;
// // // // //     String? foundName;
// // // // //     users.forEach((name, storedEmbedding) {
// // // // //       if (name == 'office_lat' || name == 'office_lng') return;
// // // // //       double distance = _mlService.calculateDistance(newEmbedding, List<double>.from(storedEmbedding));
// // // // //       if (distance < minDistance) { minDistance = distance; foundName = name; }
// // // // //     });
// // // // //     return (minDistance < 0.8) ? foundName : null;
// // // // //   }
// // // // //
// // // // //   void _showTopNotification(String m, bool err) {
// // // // //     OverlayEntry entry = OverlayEntry(builder: (c) => Positioned(top: 50, left: 20, right: 20, child: Material(color: Colors.transparent, child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: err ? Colors.red : Colors.indigo, borderRadius: BorderRadius.circular(10)), child: Text(m, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))))));
// // // // //     Overlay.of(context).insert(entry);
// // // // //     Future.delayed(const Duration(seconds: 2), () => entry.remove());
// // // // //   }
// // // // //
// // // // //   InputImage? _convertCameraImage(CameraImage image) {
// // // // //     return InputImage.fromBytes(bytes: _mlService.concatenatePlanes(image.planes), metadata: InputImageMetadata(size: Size(image.width.toDouble(), image.height.toDouble()), rotation: InputImageRotation.rotation270deg, format: InputImageFormat.nv21, bytesPerRow: image.planes[0].bytesPerRow));
// // // // //   }
// // // // //
// // // // //   @override
// // // // //   Widget build(BuildContext context) {
// // // // //     return Scaffold(
// // // // //       appBar: AppBar(
// // // // //         title: const Text("Face Scanner"),
// // // // //         actions: [
// // // // //           IconButton(icon: Icon(Icons.location_on, color: _isInsideLocation ? Colors.green : Colors.red), onPressed: _showSettingsDialog),
// // // // //           IconButton(icon: const Icon(Icons.history), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const AttendanceHistoryScreen()))),
// // // // //         ],
// // // // //       ),
// // // // //       backgroundColor: Colors.black,
// // // // //       body: Stack(
// // // // //         children: [
// // // // //           if (_controller != null && _controller!.value.isInitialized)
// // // // //             Positioned.fill(child: ClipRect(child: FittedBox(fit: BoxFit.cover, child: SizedBox(width: _controller!.value.previewSize!.height, height: _controller!.value.previewSize!.width, child: CameraPreview(_controller!, child: CustomPaint(painter: FacePainter(faces: _faces, imageSize: _controller!.value.previewSize!))))))),
// // // // //           Positioned(bottom: 0, left: 0, right: 0, child: Container(padding: const EdgeInsets.all(25), decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(30))), child: Column(mainAxisSize: MainAxisSize.min, children: [
// // // // //             Row(mainAxisAlignment: MainAxisAlignment.center, children: [
// // // // //               const Text("Attendance"), Switch(value: _registerMode, onChanged: (v) => setState(() => _registerMode = v)), const Text("Register"),
// // // // //             ]),
// // // // //             if (_registerMode) ElevatedButton(onPressed: () async {
// // // // //               await _controller?.stopImageStream();
// // // // //               List<double> emb = await _mlService.getEmbedding(_savedImage!, _faces[0]);
// // // // //               _showNameInputDialog(emb);
// // // // //             }, child: const Text("REGISTER")),
// // // // //           ]))),
// // // // //         ],
// // // // //       ),
// // // // //     );
// // // // //   }
// // // // //
// // // // //   // Logic for manual register button dialog
// // // // //   void _showNameInputDialog(List<double> embedding) {
// // // // //     TextEditingController nameController = TextEditingController();
// // // // //     showDialog(context: context, builder: (c) => AlertDialog(title: const Text("Register Name"), content: TextField(controller: nameController), actions: [ElevatedButton(onPressed: () async { await _dbService.registerUser(nameController.text, embedding); Navigator.pop(context); initializeCamera(); }, child: const Text("Save"))]));
// // // // //   }
// // // // // }
// // // // //
// // // // // class FacePainter extends CustomPainter {
// // // // //   final List<Face> faces;
// // // // //   final Size imageSize;
// // // // //   FacePainter({required this.faces, required this.imageSize});
// // // // //   @override
// // // // //   void paint(Canvas canvas, Size size) {
// // // // //     final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = 3.0..color = Colors.greenAccent;
// // // // //     for (var face in faces) {
// // // // //       double scaleX = size.width / imageSize.height;
// // // // //       double scaleY = size.height / imageSize.width;
// // // // //       canvas.drawRect(Rect.fromLTRB(face.boundingBox.left * scaleX, face.boundingBox.top * scaleY, face.boundingBox.right * scaleX, face.boundingBox.bottom * scaleY), paint);
// // // // //     }
// // // // //   }
// // // // //   @override
// // // // //   bool shouldRepaint(FacePainter oldDelegate) => true;
// // // // // }
// // // // //
// // // // //
// // // // //
// // // // //
// // // // //
// // // // //
// // // // //
// // // // //
// // // // //
// // // // //
// // // // //
// // // // //
// // // // //
// // // // //
// // // // //
// // // // //
// // // // //
// // // // //
// // // // // // import 'package:camera/camera.dart';
// // // // // // import 'package:face_attendance/user_list_screen.dart';
// // // // // // import 'package:flutter/material.dart';
// // // // // // import 'package:geolocator/geolocator.dart';
// // // // // // import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
// // // // // // import 'all_employees_attendace_list.dart';
// // // // // // import 'main.dart';      // To access global 'cameras' list
// // // // // // import 'ml_service.dart'; // Your AI Helper
// // // // // // import 'db_service.dart'; // Your Database Helper
// // // // // // import 'result_screen.dart'; // The new result screen
// // // // // //
// // // // // // class AttendanceScreen extends StatefulWidget {
// // // // // //   const AttendanceScreen({super.key});
// // // // // //
// // // // // //   @override
// // // // // //   State<AttendanceScreen> createState() => _AttendanceScreenState();
// // // // // // }
// // // // // //
// // // // // // class _AttendanceScreenState extends State<AttendanceScreen> {
// // // // // //   // 1. SERVICES & CONTROLLERS
// // // // // //   final MLService _mlService = MLService();
// // // // // //   final DBService _dbService = DBService();
// // // // // //   CameraController? _controller;
// // // // // //   late FaceDetector _faceDetector;
// // // // // //   DateTime? _faceFirstSeenTime; // Tracks how long a face is visible
// // // // // //   double targetLat = 31.31328;
// // // // // //   double targetLng = 75.59;
// // // // // //   double allowedRadius = 150; // 100 meters ke andar hona chahiye
// // // // // //   // 2. STATE VARIABLES
// // // // // //   bool _isDetecting = false;
// // // // // //   bool _registerMode = false; // Switch between Attendance and Registration
// // // // // //   List<Face> _faces = [];
// // // // // //   CameraImage? _savedImage;
// // // // // //
// // // // // //   @override
// // // // // //   void initState() {
// // // // // //     super.initState();
// // // // // //     // Initialize Face Detector with 'fast' mode for smooth UI
// // // // // //     _faceDetector = FaceDetector(
// // // // // //         options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast));
// // // // // //     initializeCamera();
// // // // // //   }
// // // // // //
// // // // // //   // 3. CLEANUP (Prevents memory leaks and crashes)
// // // // // //   @override
// // // // // //   void dispose() {
// // // // // //     _controller?.dispose();
// // // // // //     _faceDetector.close();
// // // // // //     super.dispose();
// // // // // //   }
// // // // // //
// // // // // //   Future<bool> _checkLocation() async {
// // // // // //     bool serviceEnabled;
// // // // // //     LocationPermission permission;
// // // // // //
// // // // // //     // Check if GPS is ON
// // // // // //     serviceEnabled = await Geolocator.isLocationServiceEnabled();
// // // // // //     if (!serviceEnabled) {
// // // // // //       _showTopNotification("Please turn on GPS/Location", true);
// // // // // //       return false;
// // // // // //     }
// // // // // //
// // // // // //     permission = await Geolocator.checkPermission();
// // // // // //     if (permission == LocationPermission.denied) {
// // // // // //       permission = await Geolocator.requestPermission();
// // // // // //       if (permission == LocationPermission.denied) {
// // // // // //         _showTopNotification("Location permission denied", true);
// // // // // //         return false;
// // // // // //       }
// // // // // //     }
// // // // // //
// // // // // //     // Current position get karein
// // // // // //     Position position = await Geolocator.getCurrentPosition();
// // // // // //
// // // // // //     // Distance calculate karein (Meters mein)
// // // // // //     double distanceInMeters = Geolocator.distanceBetween(
// // // // // //       position.latitude,
// // // // // //       position.longitude,
// // // // // //       targetLat,
// // // // // //       targetLng,
// // // // // //     );
// // // // // //
// // // // // //     if (distanceInMeters <= allowedRadius) {
// // // // // //       return true; // User boundary ke andar hai
// // // // // //     } else {
// // // // // //       _showTopNotification("You are outside the office area!", true);
// // // // // //       return false;
// // // // // //     }
// // // // // //   }
// // // // // //   // This replaces the SnackBar with a top-floating alert
// // // // // //   void _showTopNotification(String message, bool isError) {
// // // // // //     OverlayEntry overlayEntry = OverlayEntry(
// // // // // //       builder: (context) => Positioned(
// // // // // //         top: 50.0, // Appears below the status bar
// // // // // //         left: 20.0,
// // // // // //         right: 20.0,
// // // // // //         child: Material(
// // // // // //           color: Colors.transparent,
// // // // // //           child: Container(
// // // // // //             padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
// // // // // //             decoration: BoxDecoration(
// // // // // //               color: isError ? Colors.redAccent : Colors.indigoAccent,
// // // // // //               borderRadius: BorderRadius.circular(10),
// // // // // //               boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
// // // // // //             ),
// // // // // //             child: Row(
// // // // // //               children: [
// // // // // //                 Icon(isError ? Icons.error_outline : Icons.check_circle_outline, color: Colors.white),
// // // // // //                 const SizedBox(width: 12),
// // // // // //                 Expanded(
// // // // // //                   child: Text(
// // // // // //                     message,
// // // // // //                     style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
// // // // // //                   ),
// // // // // //                 ),
// // // // // //               ],
// // // // // //             ),
// // // // // //           ),
// // // // // //         ),
// // // // // //       ),
// // // // // //     );
// // // // // //
// // // // // //     // Show it
// // // // // //     Overlay.of(context).insert(overlayEntry);
// // // // // //
// // // // // //     // Remove it automatically after 2 seconds
// // // // // //     Future.delayed(const Duration(seconds: 2), () {
// // // // // //       overlayEntry.remove();
// // // // // //     });
// // // // // //   }
// // // // // //   // 4. CAMERA SETUP
// // // // // //   void initializeCamera() async {
// // // // // //     if (cameras.isEmpty) return;
// // // // // //
// // // // // //     _controller = CameraController(
// // // // // //       cameras[1], // Front Camera
// // // // // //       ResolutionPreset.medium,
// // // // // //       enableAudio: false,
// // // // // //       imageFormatGroup: ImageFormatGroup.yuv420,
// // // // // //     );
// // // // // //
// // // // // //     try {
// // // // // //       await _controller!.initialize();
// // // // // //       if (!mounted) return;
// // // // // //       setState(() {});
// // // // // //       _startStreaming();
// // // // // //     } catch (e) {
// // // // // //       _showSnackBar("Camera error: $e");
// // // // // //     }
// // // // // //   }
// // // // // //
// // // // // //   void _startStreaming() {
// // // // // //     _controller?.startImageStream((CameraImage image) {
// // // // // //       _savedImage = image;
// // // // // //       if (!_isDetecting) {
// // // // // //         _doFaceDetection(image);
// // // // // //       }
// // // // // //     });
// // // // // //   }
// // // // // //
// // // // // //   // 5. LIVE FACE DETECTION (The Green Box)
// // // // // //   Future<void> _doFaceDetection(CameraImage image) async {
// // // // // //     if (_isDetecting) return;
// // // // // //     _isDetecting = true;
// // // // // //
// // // // // //     try {
// // // // // //       final inputImage = _convertCameraImage(image);
// // // // // //       if (inputImage != null) {
// // // // // //         final faces = await _faceDetector.processImage(inputImage);
// // // // // //
// // // // // //         if (mounted) {
// // // // // //           setState(() => _faces = faces);
// // // // // //         }
// // // // // //
// // // // // //         // If no face is seen, reset the timer
// // // // // //         if (faces.isEmpty) {
// // // // // //           _faceFirstSeenTime = null;
// // // // // //         }
// // // // // //
// // // // // //         // If a face is found and we are in Attendance Mode
// // // // // //         else if (!_registerMode) {
// // // // // //           // Start the timer when we first see the face
// // // // // //           _faceFirstSeenTime ??= DateTime.now();
// // // // // //
// // // // // //           // 1. Location check (Geofencing)
// // // // // //           bool isInside = await _checkLocation();
// // // // // //
// // // // // //           if (isInside) {
// // // // // //             // 2. Get the 192 unique numbers (Embedding)
// // // // // //             List<double> embedding = await _mlService.getEmbedding(image, faces[0]);
// // // // // //
// // // // // //             // 3. Compare with Database
// // // // // //             String? name = _identifyUser(embedding);
// // // // // //
// // // // // //             if (name != null) {
// // // // // //               // MATCH FOUND!
// // // // // //               _faceFirstSeenTime = null; // Reset timer
// // // // // //               await _dbService.saveAttendanceLog(name);
// // // // // //               await _controller?.stopImageStream();
// // // // // //
// // // // // //               if (mounted) {
// // // // // //                 _showTopNotification("Success: Attendance Marked for $name", false);
// // // // // //                 Navigator.push(
// // // // // //                   context,
// // // // // //                   MaterialPageRoute(builder: (context) => ResultScreen(name: name, imagePath: "")),
// // // // // //                 ).then((_) => _startStreaming());
// // // // // //               }
// // // // // //             } else {
// // // // // //               // NO MATCH FOUND
// // // // // //               // Check if the face has been visible for more than 3 seconds
// // // // // //               final duration = DateTime.now().difference(_faceFirstSeenTime!);
// // // // // //               if (duration.inSeconds >= 3) {
// // // // // //                 _showTopNotification("Alert: Face not matched! Register your face now.", true);
// // // // // //                 _faceFirstSeenTime = null; // Reset timer so it doesn't spam the message
// // // // // //               }
// // // // // //             }
// // // // // //           }
// // // // // //         }
// // // // // //       }
// // // // // //     } catch (e) {
// // // // // //       debugPrint("AI Error: $e");
// // // // // //     }
// // // // // //
// // // // // //     // Use a shorter delay (200ms) for smoother detection
// // // // // //     await Future.delayed(const Duration(milliseconds: 200));
// // // // // //     _isDetecting = false;
// // // // // //   }
// // // // // //
// // // // // //
// // // // // //
// // // // // //   // 6. MAIN ACTION: REGISTER OR ATTENDANCE
// // // // // //   Future<void> onCaptureButtonPressed() async {
// // // // // //     if (_faces.isEmpty || _savedImage == null) {
// // // // // //       _showTopNotification("No face detected! Stand in front of the camera.", true);
// // // // // //       // _showSnackBar("No face detected! Stand in front of the camera.");
// // // // // //       return;
// // // // // //     }
// // // // // //
// // // // // //     // Stop stream to focus CPU power on AI Embedding
// // // // // //     await _controller?.stopImageStream();
// // // // // //
// // // // // //     try {
// // // // // //       // Create the "Fingerprint" (192 numbers)
// // // // // //       List<double> embedding = await _mlService.getEmbedding(_savedImage!, _faces[0]);
// // // // // //
// // // // // //       if (_registerMode) {
// // // // // //         _showNameInputDialog(embedding);
// // // // // //       } else {
// // // // // //         String? name = _identifyUser(embedding);
// // // // // //         if (name != null) {
// // // // // //           // Success: Show Snackbar and Move to Result Screen
// // // // // //           _showTopNotification("Success: Attendance Marked for $name", false);
// // // // // //           if (mounted) {
// // // // // //             Navigator.push(
// // // // // //               context,
// // // // // //               MaterialPageRoute(
// // // // // //                 builder: (context) => ResultScreen(name: name, imagePath: ""),
// // // // // //               ),
// // // // // //             ).then((_) => _startStreaming()); // Restart camera when user clicks 'Back'
// // // // // //           }
// // // // // //         } else {
// // // // // //           _showResultDialog("Access Denied", "User not recognized.", false);
// // // // // //         }
// // // // // //       }
// // // // // //     } catch (e) {
// // // // // //       _showTopNotification("Error: $e", true);
// // // // // //       _startStreaming();
// // // // // //     }
// // // // // //   }
// // // // // //
// // // // // //
// // // // // //
// // // // // //
// // // // // //   // Database Comparison Logic
// // // // // //   String? _identifyUser(List<double> newEmbedding) {
// // // // // //     Map<dynamic, dynamic> users = _dbService.getAllUsers();
// // // // // //     double minDistance = 1.0;
// // // // // //     String? foundName;
// // // // // //
// // // // // //     users.forEach((name, storedEmbedding) {
// // // // // //       double distance = _mlService.calculateDistance(
// // // // // //           newEmbedding, List<double>.from(storedEmbedding));
// // // // // //       if (distance < minDistance) {
// // // // // //         minDistance = distance;
// // // // // //         foundName = name;
// // // // // //       }
// // // // // //     });
// // // // // //
// // // // // //     // Threshold: 0.8 is standard for MobileFaceNet
// // // // // //     return (minDistance < 0.8) ? foundName : null;
// // // // // //   }
// // // // // //
// // // // // //   // 7. UI HELPERS (Dialogs & Conversion)
// // // // // //   InputImage? _convertCameraImage(CameraImage image) {
// // // // // //     return InputImage.fromBytes(
// // // // // //       bytes: _mlService.concatenatePlanes(image.planes),
// // // // // //       metadata: InputImageMetadata(
// // // // // //         size: Size(image.width.toDouble(), image.height.toDouble()),
// // // // // //         rotation: InputImageRotation.rotation270deg, // Standard for Android Front Cam
// // // // // //         format: InputImageFormat.nv21,
// // // // // //         bytesPerRow: image.planes[0].bytesPerRow,
// // // // // //       ),
// // // // // //     );
// // // // // //   }
// // // // // //
// // // // // //   void _showNameInputDialog(List<double> embedding) {
// // // // // //     TextEditingController nameController = TextEditingController();
// // // // // //     showDialog(
// // // // // //       context: context,
// // // // // //       barrierDismissible: false,
// // // // // //       builder: (context) => AlertDialog(
// // // // // //         title: const Text("Register User"),
// // // // // //         content: TextField(
// // // // // //           controller: nameController,
// // // // // //           decoration: const InputDecoration(hintText: "Enter Full Name"),
// // // // // //         ),
// // // // // //         actions: [
// // // // // //           TextButton(onPressed: () { Navigator.pop(context); _startStreaming(); }, child: const Text("Cancel")),
// // // // // //           ElevatedButton(
// // // // // //             onPressed: () async {
// // // // // //               if (nameController.text.isNotEmpty) {
// // // // // //                 await _dbService.registerUser(nameController.text, embedding);
// // // // // //                 Navigator.pop(context);
// // // // // //                 _startStreaming();
// // // // // //                 _showTopNotification("User ${nameController.text} Registered!", false);
// // // // // //
// // // // // //               }
// // // // // //             },
// // // // // //             child: const Text("Save"),
// // // // // //           ),
// // // // // //         ],
// // // // // //       ),
// // // // // //     );
// // // // // //   }
// // // // // //
// // // // // //   void _showResultDialog(String title, String message, bool success) {
// // // // // //     showDialog(
// // // // // //       context: context,
// // // // // //       builder: (context) => AlertDialog(
// // // // // //         title: Text(title, style: TextStyle(color: success ? Colors.green : Colors.red)),
// // // // // //         content: Text(message),
// // // // // //         actions: [TextButton(onPressed: () { Navigator.pop(context); _startStreaming(); }, child: const Text("OK"))],
// // // // // //       ),
// // // // // //     );
// // // // // //   }
// // // // // //
// // // // // //   void _showSnackBar(String message) {
// // // // // //     ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
// // // // // //   }
// // // // // //
// // // // // //   // 8. THE BUILD METHOD (UI)
// // // // // //   @override
// // // // // //   Widget build(BuildContext context) {
// // // // // //     return Scaffold(
// // // // // //       // Add this inside your Scaffold in admin_attendance_screen.dart
// // // // // //       appBar: AppBar(
// // // // // //         title: const Text("Face Scanner"),
// // // // // //         actions: [
// // // // // //           IconButton(
// // // // // //             icon: const Icon(Icons.history_edu),
// // // // // //             onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AttendanceHistoryScreen())),
// // // // // //           ),
// // // // // //         ],
// // // // // //       ),
// // // // // //       backgroundColor: Colors.black,
// // // // // //       body: Stack(
// // // // // //         children: [
// // // // // //           // PROPORTIONAL CAMERA VIEW (No Stretching)
// // // // // //           if (_controller != null && _controller!.value.isInitialized)
// // // // // //             Positioned.fill(
// // // // // //               child: ClipRect(
// // // // // //                 child: FittedBox(
// // // // // //                   fit: BoxFit.cover,
// // // // // //                   child: SizedBox(
// // // // // //                     width: _controller!.value.previewSize!.height,
// // // // // //                     height: _controller!.value.previewSize!.width,
// // // // // //                     child: CameraPreview(
// // // // // //                       _controller!,
// // // // // //                       child: CustomPaint(
// // // // // //                         painter: FacePainter(
// // // // // //                           faces: _faces,
// // // // // //                           imageSize: _controller!.value.previewSize!,
// // // // // //                         ),
// // // // // //                       ),
// // // // // //                     ),
// // // // // //                   ),
// // // // // //                 ),
// // // // // //               ),
// // // // // //             ),
// // // // // //
// // // // // //           // BOTTOM UI PANEL
// // // // // //           // Inside your build method's Stack...
// // // // // //           Positioned(
// // // // // //             bottom: 0, left: 0, right: 0,
// // // // // //             child: Container(
// // // // // //               padding: const EdgeInsets.all(25),
// // // // // //               decoration: const BoxDecoration(
// // // // // //                 color: Colors.white,
// // // // // //                 borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
// // // // // //               ),
// // // // // //               child: Column(
// // // // // //                 mainAxisSize: MainAxisSize.min,
// // // // // //                 children: [
// // // // // //                   // Toggle stays so you can switch to Register mode
// // // // // //                   Row(
// // // // // //                     mainAxisAlignment: MainAxisAlignment.center,
// // // // // //                     children: [
// // // // // //                       const Text("Attendance Mode"),
// // // // // //                       Switch(
// // // // // //                         value: _registerMode,
// // // // // //                         onChanged: (val) => setState(() => _registerMode = val),
// // // // // //                       ),
// // // // // //                       const Text("Register Mode"),
// // // // // //                     ],
// // // // // //                   ),
// // // // // //
// // // // // //                   // ONLY show the button if _registerMode is true
// // // // // //                   if (_registerMode) ...[
// // // // // //                     const SizedBox(height: 15),
// // // // // //                     SizedBox(
// // // // // //                       width: double.infinity,
// // // // // //                       height: 55,
// // // // // //                       child: ElevatedButton(
// // // // // //                         onPressed: onCaptureButtonPressed, // Only manual for registration
// // // // // //                         style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
// // // // // //                         child: const Text("REGISTER THIS FACE", style: TextStyle(color: Colors.white)),
// // // // // //                       ),
// // // // // //                     ),
// // // // // //                   ],
// // // // // //
// // // // // //                   if (!_registerMode)
// // // // // //                     const Padding(
// // // // // //                       padding: EdgeInsets.only(top: 10),
// // // // // //                       child: Text("Looking for registered faces...",
// // // // // //                           style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
// // // // // //                     ),
// // // // // //                 ],
// // // // // //               ),
// // // // // //             ),
// // // // // //           ),
// // // // // //         ],
// // // // // //       ),
// // // // // //     );
// // // // // //   }
// // // // // // }
// // // // // //
// // // // // // // 9. THE FACE PAINTER (Draws the Box)
// // // // // // class FacePainter extends CustomPainter {
// // // // // //   final List<Face> faces;
// // // // // //   final Size imageSize;
// // // // // //   FacePainter({required this.faces, required this.imageSize});
// // // // // //
// // // // // //   @override
// // // // // //   void paint(Canvas canvas, Size size) {
// // // // // //     final paint = Paint()
// // // // // //       ..style = PaintingStyle.stroke
// // // // // //       ..strokeWidth = 3.0
// // // // // //       ..color = Colors.greenAccent;
// // // // // //
// // // // // //     for (var face in faces) {
// // // // // //       double scaleX = size.width / imageSize.height;
// // // // // //       double scaleY = size.height / imageSize.width;
// // // // // //
// // // // // //       canvas.drawRect(
// // // // // //         Rect.fromLTRB(
// // // // // //           face.boundingBox.left * scaleX,
// // // // // //           face.boundingBox.top * scaleY,
// // // // // //           face.boundingBox.right * scaleX,
// // // // // //           face.boundingBox.bottom * scaleY,
// // // // // //         ),
// // // // // //         paint,
// // // // // //       );
// // // // // //     }
// // // // // //   }
// // // // // //
// // // // // //   @override
// // // // // //   bool shouldRepaint(FacePainter oldDelegate) => true;
// // // // // // }