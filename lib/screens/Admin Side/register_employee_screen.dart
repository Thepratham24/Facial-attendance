import 'dart:async';
import 'dart:ui';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:intl/intl.dart';

import '../../constants/app_colors.dart';
import '../../main.dart'; // Ensure 'cameras' list is accessible
import '../../services/api_service.dart';
import '../../services/ml_service.dart';
import '../../widgets/face_painter.dart';

class AttendanceRegisterScreen extends StatefulWidget {
  const AttendanceRegisterScreen({super.key});

  @override
  State<AttendanceRegisterScreen> createState() => _AttendanceRegisterScreenState();
}

class _AttendanceRegisterScreenState extends State<AttendanceRegisterScreen> with WidgetsBindingObserver {
  final MLService _mlService = MLService();
  final ApiService _apiService = ApiService();

  // Text Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _designationController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();

  // Dropdown Data
  List<dynamic> _locationList = [];
  List<dynamic> _departmentList = [];
  List<dynamic> _shiftList = [];

  // Selections
  List<String> _selectedLocationIds = [];
  String? _selectedShiftId;
  String? _selectedDepartmentId;
  int _selectedGender = 1;

  bool _isLoadingDropdowns = false;

  // Camera & ML
  CameraController? _controller;
  late FaceDetector _faceDetector;
  List<Face> _faces = [];
  CameraImage? _savedImage;

  bool _isDetecting = false;
  bool _isProcessing = false; // Locks UI

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _faceDetector = FaceDetector(options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast));

    // Default Date
    _dateController.text = DateFormat('yyyy-MM-dd').format(DateTime.now());

    _fetchDropdownData();
    _initializeCamera();
  }

  // 🔴 1. RESET EVERYTHING
  void _clearControllers() {
    _nameController.clear();
    _emailController.clear();
    _phoneController.clear();
    _designationController.clear();
    _dateController.text = DateFormat('yyyy-MM-dd').format(DateTime.now());

    if (mounted) {
      setState(() {
        _selectedLocationIds = [];
        _selectedShiftId = null; // Reset selection
        // Department reset nahi karte taaki baar baar select na karna pade (User convenience)
        _selectedGender = 1;
        _faces = [];
        _savedImage = null;
        _isProcessing = false;
      });
    }
  }

  String get _selectedLocationsText {
    if (_selectedLocationIds.isEmpty) return "Select Locations";
    if (_locationList.isEmpty) return "Loading...";
    List<String> names = [];
    for (var id in _selectedLocationIds) {
      var loc = _locationList.firstWhere((element) => element['_id'] == id, orElse: () => null);
      if (loc != null) names.add(loc['name']);
    }
    return names.join(", ");
  }

  void _fetchDropdownData() async {
    setState(() => _isLoadingDropdowns = true);
    try {
      var locs = await _apiService.getLocations();
      var shifts = await _apiService.getShifts();
      var departments = await _apiService.getDepartments();

      if (mounted) {
        setState(() {
          _locationList = locs;
          _shiftList = shifts;
          _departmentList = departments;

          // Auto-select first options for convenience
          if (_departmentList.isNotEmpty) _selectedDepartmentId = _departmentList[0]['_id'];
          if (_shiftList.isNotEmpty) _selectedShiftId = _shiftList[0]['_id'];

          _isLoadingDropdowns = false;
        });
      }
    } catch (e) {
      debugPrint("Dropdown Error: $e");
      if (mounted) setState(() => _isLoadingDropdowns = false);
    }
  }

  // 🔴 2. SAFEST CAMERA INIT (Prevents Crash)
  Future<void> _initializeCamera() async {
    if (cameras.isEmpty) return;

    // Dispose old controller properly
    if (_controller != null) {
      await _controller?.dispose();
      if(mounted) setState(() => _controller = null);
    }

    CameraDescription description = cameras[0];
    for (var i = 0; i < cameras.length; i++) {
      if (cameras[i].lensDirection == CameraLensDirection.front) {
        description = cameras[i];
        break;
      }
    }

    CameraController newController = CameraController(
        description,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888
    );

    try {
      await newController.initialize();
      if (!mounted) return;

      setState(() => _controller = newController);

      // Start Stream
      newController.startImageStream((image) {
        _savedImage = image;
        if (!_isDetecting && !_isProcessing) {
          _isDetecting = true;
          _doFaceDetection(image);
        }
      });
    } catch (e) {
      debugPrint("Camera Init Error: $e");
    }
  }

  Future<void> _doFaceDetection(CameraImage image) async {
    try {
      final inputImage = _convertCameraImage(image);
      if (inputImage != null) {
        final faces = await _faceDetector.processImage(inputImage);
        if (mounted) setState(() => _faces = faces);
      }
    } catch (e) {
      // Ignore transient errors
    } finally {
      if(mounted) _isDetecting = false;
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
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );
    } catch (e) { return null; }
  }

  // 🔴 3. MAIN LOGIC (Crash Fix here)
  Future<void> _handleRegistration() async {
    if (_faces.isEmpty || _savedImage == null) {
      _showTopNotification("No face detected! Look at camera.", true);
      return;
    }

    setState(() => _isProcessing = true);

    try {
      // A. Stop Stream FIRST (Critical to prevent crash)
      if (_controller != null && _controller!.value.isStreamingImages) {
        await _controller!.stopImageStream();
        await Future.delayed(const Duration(milliseconds: 200)); // Safety Pause
      }

      // B. Generate Embedding (Using last saved frame)
      List<double> emb = await _mlService.getEmbedding(_savedImage!, _faces[0]);

      // C. Check Duplicacy (API Call)
      var result = await _apiService.checkFaceExistence(emb);

      if (result['code'] == 422 || result['code'] == 409) {
        // 🔥 Already Exists -> Show Error & Restart Camera
        _showTopNotification(result['message'], true);
        setState(() => _isProcessing = false);
        _initializeCamera(); // Restart immediately
        return;
      }

      // D. Take High-Res Photo (Ab safe hai kyunki stream band hai)
      XFile photo = await _controller!.takePicture();
      File imageFile = File(photo.path);

      // E. Open Dialog
      if (mounted) {
        _showFullRegistrationForm(emb, imageFile);
      }

    } catch (e) {
      debugPrint("Registration Error: $e");
      _showTopNotification("Error: Please try again.", true);
      _initializeCamera(); // Restart if failed
    } finally {
      // Don't set isProcessing false here, let dialog handle it
    }
  }

  // DATE PICKER
  Future<void> _selectDate(BuildContext context) async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) => Theme(data: Theme.of(context).copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFF2E3192))), child: child!),
    );
    if (picked != null) {
      setState(() => _dateController.text = DateFormat('yyyy-MM-dd').format(picked));
    }
  }

  // 🔴 4. FORM DIALOG
  void _showFullRegistrationForm(List<double> embedding, File facePhoto) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            backgroundColor: Colors.white,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(colors: [Color(0xFF2E3192), Color(0xFF1BFFFF)]),
                      borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
                    ),
                    child: const Center(child: Text("New Profile", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
                  ),

                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        CircleAvatar(radius: 40, backgroundImage: FileImage(facePhoto)),
                        const SizedBox(height: 20),

                        // Date Field
                        TextField(
                          controller: _dateController,
                          readOnly: true,
                          onTap: () => _selectDate(context),
                          decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.calendar_today, size: 20),
                              labelText: "Joining Date",
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))
                          ),
                        ),
                        const SizedBox(height: 10),

                        _buildTextField(_nameController, "Full Name", Icons.person),
                        const SizedBox(height: 10),
                        _buildTextField(_emailController, "Email", Icons.email, type: TextInputType.emailAddress),
                        const SizedBox(height: 10),
                        _buildTextField(_phoneController, "Phone", Icons.phone, type: TextInputType.phone),
                        const SizedBox(height: 10),
                        _buildTextField(_designationController, "Designation", Icons.work),
                        const SizedBox(height: 10),

                        _isLoadingDropdowns
                            ? const LinearProgressIndicator()
                            : Column(
                          children: [
                            _buildDropdown(
                                value: _departmentList.any((d) => d['_id'] == _selectedDepartmentId) ? _selectedDepartmentId : null,
                                hint: "Department",
                                items: _departmentList.map((d) => DropdownMenuItem<String>(value: d['_id'], child: Text(d['name']))).toList(),
                                onChanged: (v) => setStateDialog(() => _selectedDepartmentId = v)
                            ),
                            const SizedBox(height: 10),

                            // Multi Select Location UI
                            InkWell(
                              onTap: () async {
                                await showDialog(
                                  context: context,
                                  builder: (ctx) {
                                    return StatefulBuilder(builder: (context, setInnerState) {
                                      return AlertDialog(
                                        title: const Text("Select Locations"),
                                        content: SizedBox(
                                          width: double.maxFinite,
                                          child: ListView.builder(
                                            shrinkWrap: true,
                                            itemCount: _locationList.length,
                                            itemBuilder: (context, index) {
                                              final loc = _locationList[index];
                                              final isSelected = _selectedLocationIds.contains(loc['_id']);
                                              return CheckboxListTile(
                                                value: isSelected,
                                                title: Text(loc['name']),
                                                activeColor: Colors.indigo,
                                                onChanged: (bool? checked) {
                                                  setInnerState(() {
                                                    if (checked == true) _selectedLocationIds.add(loc['_id']);
                                                    else _selectedLocationIds.remove(loc['_id']);
                                                  });
                                                  setStateDialog(() {});
                                                },
                                              );
                                            },
                                          ),
                                        ),
                                        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Done"))],
                                      );
                                    });
                                  },
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
                                decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(12)),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(child: Text(_selectedLocationsText, style: TextStyle(color: _selectedLocationIds.isEmpty ? Colors.grey[600] : Colors.black87))),
                                    const Icon(Icons.arrow_drop_down, color: Colors.grey),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: 10),
                            _buildDropdown(
                                value: _shiftList.any((s) => s['_id'] == _selectedShiftId) ? _selectedShiftId : null,
                                hint: "Shift",
                                items: _shiftList.map((s) => DropdownMenuItem<String>(value: s['_id'], child: Text(s['name']))).toList(),
                                onChanged: (v) => setStateDialog(() => _selectedShiftId = v)
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        _buildDropdown(
                            value: _selectedGender,
                            hint: "Gender",
                            items: const [DropdownMenuItem(value: 1, child: Text("Male")), DropdownMenuItem(value: 2, child: Text("Female"))],
                            onChanged: (v) => setStateDialog(() => _selectedGender = v ?? 1)
                        ),

                        const SizedBox(height: 25),

                        Row(
                          children: [
                            Expanded(child: TextButton(onPressed: () {
                              Navigator.pop(context); // Close Dialog
                              _initializeCamera(); // Restart Camera on Cancel
                              setState(() => _isProcessing = false);
                            }, child: const Text("Cancel"))),

                            Expanded(child: ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
                                onPressed: () async {
                                  // Validation
                                  if (_nameController.text.isEmpty || _selectedLocationIds.isEmpty || _selectedShiftId == null || _selectedDepartmentId == null) {
                                    _showTopNotification("Fill all fields", true);
                                    return;
                                  }

                                  Navigator.pop(c); // Close Dialog
                                  setState(() => _isProcessing = true);
                                  _showTopNotification("Registering...", false);

                                  // API CALL
                                  var result = await _apiService.registerEmployee(
                                    name: _nameController.text,
                                    email: _emailController.text,
                                    phone: _phoneController.text,
                                    gender: _selectedGender,
                                    designation: _designationController.text,
                                    departmentId: _selectedDepartmentId!,
                                    locationIds: _selectedLocationIds,
                                    shiftId: _selectedShiftId!,
                                    imageFile: facePhoto,
                                    faceEmbedding: embedding,
                                    joiningDate: _dateController.text,
                                  );

                                  if (result['success'] == true) {
                                    _showTopNotification(result['message'], false);

                                    // 🔴 5. SUCCESS: Clear & Restart for Next
                                    _clearControllers();
                                    await Future.delayed(const Duration(seconds: 1));
                                    if(mounted) _initializeCamera();

                                  } else {
                                    _showTopNotification(result['message'] ?? "Error", true);
                                    if(mounted) {
                                      setState(() => _isProcessing = false);
                                      _initializeCamera();
                                    }
                                  }
                                },
                                child: const Text("Save", style: TextStyle(color: Colors.white))
                            )),
                          ],
                        )
                      ],
                    ),
                  )
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTextField(TextEditingController ctrl, String hint, IconData icon, {TextInputType type = TextInputType.text}) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      decoration: InputDecoration(
          prefixIcon: Icon(icon, size: 20),
          hintText: hint,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0)
      ),
    );
  }

  Widget _buildDropdown<T>({required T? value, required String hint, required List<DropdownMenuItem<T>> items, required Function(T?) onChanged}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(12)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          hint: Text(hint),
          items: items,
          onChanged: onChanged,
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
                decoration: BoxDecoration(
                    color: err ? Colors.redAccent : Colors.green,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [const BoxShadow(color: Colors.black26, blurRadius: 10)]
                ),
                child: Text(m, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
            )
        )
    ));
    Overlay.of(context).insert(entry);
    Future.delayed(const Duration(seconds: 3), () => entry.remove());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Dispose safe check
    if (_controller != null) {
      _controller!.dispose();
    }
    _faceDetector.close();
    super.dispose();
  }

  // 🔴 CRASH FIX HERE: LIFECYCLE UPDATE
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      // Background me ja raha hai -> UI se controller hatao, fir dispose karo
      if (_controller != null) {
        final oldController = _controller;
        if(mounted) setState(() => _controller = null); // UI Rebuild (Shows Loader)
        oldController?.dispose();
      }
    } else if (state == AppLifecycleState.resumed) {
      // Wapis aaya -> Initialize karo
      _initializeCamera();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 🔴 SAFE CHECK: Only show CameraPreview if controller is NOT null AND Initialized
          if (_controller != null && _controller!.value.isInitialized)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _controller!.value.previewSize!.height,
                  height: _controller!.value.previewSize!.width,
                  child: CameraPreview(
                    _controller!,
                    child: CustomPaint(painter: FacePainter(faces: _faces, imageSize: _controller!.value.previewSize!)),
                  ),
                ),
              ),
            )
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),

          Positioned(top: 50, left: 20, child: GestureDetector(onTap: () => Navigator.pop(context), child: Container(padding: const EdgeInsets.all(8), decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle), child: const Icon(Icons.arrow_back, color: Colors.white)))),

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
                      Text(_isProcessing ? "Processing..." : "Align Face to Register", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 20),
                      SizedBox(width: double.infinity, height: 55, child: ElevatedButton(onPressed: _isProcessing ? null : _handleRegistration, style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), child: Ink(decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF2E3192), Color(0xFF1BFFFF)]), borderRadius: BorderRadius.circular(15)), child: Center(child: _isProcessing ? const CircularProgressIndicator(color: Colors.white) : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.camera, color: Colors.white), SizedBox(width: 10), Text("CAPTURE & REGISTER", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white))])))))
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






















// import 'dart:async';
// import 'dart:ui';
// import 'dart:io';
// import 'package:camera/camera.dart';
// import 'package:flutter/material.dart';
// import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
// import 'package:intl/intl.dart';
//
// import '../../constants/app_colors.dart';
// import '../../main.dart'; // Ensure 'cameras' list is accessible
// import '../../services/api_service.dart';
// import '../../services/ml_service.dart';
// import '../../widgets/face_painter.dart';
//
// class AttendanceRegisterScreen extends StatefulWidget {
//   const AttendanceRegisterScreen({super.key});
//
//   @override
//   State<AttendanceRegisterScreen> createState() => _AttendanceRegisterScreenState();
// }
//
// class _AttendanceRegisterScreenState extends State<AttendanceRegisterScreen> with WidgetsBindingObserver {
//   final MLService _mlService = MLService();
//   final ApiService _apiService = ApiService();
//
//   // Text Controllers
//   final TextEditingController _nameController = TextEditingController();
//   final TextEditingController _emailController = TextEditingController();
//   final TextEditingController _phoneController = TextEditingController();
//   final TextEditingController _designationController = TextEditingController();
//   final TextEditingController _dateController = TextEditingController();
//
//   // Dropdown Data
//   List<dynamic> _locationList = [];
//   List<dynamic> _departmentList = [];
//   List<dynamic> _shiftList = [];
//
//   // Selections
//   List<String> _selectedLocationIds = [];
//   String? _selectedShiftId;
//   String? _selectedDepartmentId;
//   int _selectedGender = 1;
//
//   bool _isLoadingDropdowns = false;
//
//   // Camera & ML
//   CameraController? _controller;
//   late FaceDetector _faceDetector;
//   List<Face> _faces = [];
//   CameraImage? _savedImage;
//
//   bool _isDetecting = false;
//   bool _isProcessing = false; // Locks UI
//
//   @override
//   void initState() {
//     super.initState();
//     WidgetsBinding.instance.addObserver(this);
//     _faceDetector = FaceDetector(options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast));
//
//     // Default Date
//     _dateController.text = DateFormat('yyyy-MM-dd').format(DateTime.now());
//
//     _fetchDropdownData();
//     _initializeCamera();
//   }
//
//   // 🔴 1. RESET EVERYTHING
//   void _clearControllers() {
//     _nameController.clear();
//     _emailController.clear();
//     _phoneController.clear();
//     _designationController.clear();
//     _dateController.text = DateFormat('yyyy-MM-dd').format(DateTime.now());
//
//     if (mounted) {
//       setState(() {
//         _selectedLocationIds = [];
//         _selectedShiftId = null; // Reset selection
//         // Department reset nahi karte taaki baar baar select na karna pade (User convenience)
//         _selectedGender = 1;
//         _faces = [];
//         _savedImage = null;
//         _isProcessing = false;
//       });
//     }
//   }
//
//   String get _selectedLocationsText {
//     if (_selectedLocationIds.isEmpty) return "Select Locations";
//     if (_locationList.isEmpty) return "Loading...";
//     List<String> names = [];
//     for (var id in _selectedLocationIds) {
//       var loc = _locationList.firstWhere((element) => element['_id'] == id, orElse: () => null);
//       if (loc != null) names.add(loc['name']);
//     }
//     return names.join(", ");
//   }
//
//   void _fetchDropdownData() async {
//     setState(() => _isLoadingDropdowns = true);
//     try {
//       var locs = await _apiService.getLocations();
//       var shifts = await _apiService.getShifts();
//       var departments = await _apiService.getDepartments();
//
//       if (mounted) {
//         setState(() {
//           _locationList = locs;
//           _shiftList = shifts;
//           _departmentList = departments;
//
//           // Auto-select first options for convenience
//           if (_departmentList.isNotEmpty) _selectedDepartmentId = _departmentList[0]['_id'];
//           if (_shiftList.isNotEmpty) _selectedShiftId = _shiftList[0]['_id'];
//
//           _isLoadingDropdowns = false;
//         });
//       }
//     } catch (e) {
//       debugPrint("Dropdown Error: $e");
//       if (mounted) setState(() => _isLoadingDropdowns = false);
//     }
//   }
//
//   // 🔴 2. SAFEST CAMERA INIT (Prevents Crash)
//   Future<void> _initializeCamera() async {
//     if (cameras.isEmpty) return;
//
//     // Dispose old controller properly
//     if (_controller != null) {
//       await _controller?.dispose();
//       if(mounted) setState(() => _controller = null);
//     }
//
//     CameraDescription description = cameras[0];
//     for (var i = 0; i < cameras.length; i++) {
//       if (cameras[i].lensDirection == CameraLensDirection.front) {
//         description = cameras[i];
//         break;
//       }
//     }
//
//     CameraController newController = CameraController(
//         description,
//         ResolutionPreset.medium,
//         enableAudio: false,
//         imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888
//     );
//
//     try {
//       await newController.initialize();
//       if (!mounted) return;
//
//       setState(() => _controller = newController);
//
//       // Start Stream
//       newController.startImageStream((image) {
//         _savedImage = image;
//         if (!_isDetecting && !_isProcessing) {
//           _isDetecting = true;
//           _doFaceDetection(image);
//         }
//       });
//     } catch (e) {
//       debugPrint("Camera Init Error: $e");
//     }
//   }
//
//   Future<void> _doFaceDetection(CameraImage image) async {
//     try {
//       final inputImage = _convertCameraImage(image);
//       if (inputImage != null) {
//         final faces = await _faceDetector.processImage(inputImage);
//         if (mounted) setState(() => _faces = faces);
//       }
//     } catch (e) {
//       // Ignore transient errors
//     } finally {
//       if(mounted) _isDetecting = false;
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
//         bytes: _mlService.concatenatePlanes(image.planes),
//         metadata: InputImageMetadata(
//           size: Size(image.width.toDouble(), image.height.toDouble()),
//           rotation: rotation,
//           format: Platform.isAndroid ? InputImageFormat.nv21 : InputImageFormat.bgra8888,
//           bytesPerRow: image.planes[0].bytesPerRow,
//         ),
//       );
//     } catch (e) { return null; }
//   }
//
//   // 🔴 3. MAIN LOGIC (Crash Fix here)
//   Future<void> _handleRegistration() async {
//     if (_faces.isEmpty || _savedImage == null) {
//       _showTopNotification("No face detected! Look at camera.", true);
//       return;
//     }
//
//     setState(() => _isProcessing = true);
//
//     try {
//       // A. Stop Stream FIRST (Critical to prevent crash)
//       if (_controller != null && _controller!.value.isStreamingImages) {
//         await _controller!.stopImageStream();
//         await Future.delayed(const Duration(milliseconds: 200)); // Safety Pause
//       }
//
//       // B. Generate Embedding (Using last saved frame)
//       List<double> emb = await _mlService.getEmbedding(_savedImage!, _faces[0]);
//
//       // C. Check Duplicacy (API Call)
//       var result = await _apiService.checkFaceExistence(emb);
//
//       if (result['code'] == 422 || result['code'] == 409) {
//         // 🔥 Already Exists -> Show Error & Restart Camera
//         _showTopNotification(result['message'], true);
//         setState(() => _isProcessing = false);
//         _initializeCamera(); // Restart immediately
//         return;
//       }
//
//       // D. Take High-Res Photo (Ab safe hai kyunki stream band hai)
//       XFile photo = await _controller!.takePicture();
//       File imageFile = File(photo.path);
//
//       // E. Open Dialog
//       if (mounted) {
//         _showFullRegistrationForm(emb, imageFile);
//       }
//
//     } catch (e) {
//       debugPrint("Registration Error: $e");
//       _showTopNotification("Error: Please try again.", true);
//       _initializeCamera(); // Restart if failed
//     } finally {
//       // Don't set isProcessing false here, let dialog handle it
//     }
//   }
//
//   // DATE PICKER
//   Future<void> _selectDate(BuildContext context) async {
//     DateTime? picked = await showDatePicker(
//       context: context,
//       initialDate: DateTime.now(),
//       firstDate: DateTime(2000),
//       lastDate: DateTime(2100),
//       builder: (context, child) => Theme(data: Theme.of(context).copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFF2E3192))), child: child!),
//     );
//     if (picked != null) {
//       setState(() => _dateController.text = DateFormat('yyyy-MM-dd').format(picked));
//     }
//   }
//
//   // 🔴 4. FORM DIALOG
//   void _showFullRegistrationForm(List<double> embedding, File facePhoto) {
//     showDialog(
//       context: context,
//       barrierDismissible: false,
//       builder: (c) => StatefulBuilder(
//         builder: (context, setStateDialog) {
//           return Dialog(
//             shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
//             backgroundColor: Colors.white,
//             child: SingleChildScrollView(
//               child: Column(
//                 mainAxisSize: MainAxisSize.min,
//                 children: [
//                   Container(
//                     width: double.infinity,
//                     padding: const EdgeInsets.symmetric(vertical: 20),
//                     decoration: const BoxDecoration(
//                       gradient: LinearGradient(colors: [Color(0xFF2E3192), Color(0xFF1BFFFF)]),
//                       borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
//                     ),
//                     child: const Center(child: Text("New Profile", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
//                   ),
//
//                   Padding(
//                     padding: const EdgeInsets.all(20),
//                     child: Column(
//                       children: [
//                         CircleAvatar(radius: 40, backgroundImage: FileImage(facePhoto)),
//                         const SizedBox(height: 20),
//
//                         // Date Field
//                         TextField(
//                           controller: _dateController,
//                           readOnly: true,
//                           onTap: () => _selectDate(context),
//                           decoration: InputDecoration(
//                               prefixIcon: const Icon(Icons.calendar_today, size: 20),
//                               labelText: "Joining Date",
//                               border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))
//                           ),
//                         ),
//                         const SizedBox(height: 10),
//
//                         _buildTextField(_nameController, "Full Name", Icons.person),
//                         const SizedBox(height: 10),
//                         _buildTextField(_emailController, "Email", Icons.email, type: TextInputType.emailAddress),
//                         const SizedBox(height: 10),
//                         _buildTextField(_phoneController, "Phone", Icons.phone, type: TextInputType.phone),
//                         const SizedBox(height: 10),
//                         _buildTextField(_designationController, "Designation", Icons.work),
//                         const SizedBox(height: 10),
//
//                         _isLoadingDropdowns
//                             ? const LinearProgressIndicator()
//                             : Column(
//                           children: [
//                             _buildDropdown(
//                                 value: _departmentList.any((d) => d['_id'] == _selectedDepartmentId) ? _selectedDepartmentId : null,
//                                 hint: "Department",
//                                 items: _departmentList.map((d) => DropdownMenuItem<String>(value: d['_id'], child: Text(d['name']))).toList(),
//                                 onChanged: (v) => setStateDialog(() => _selectedDepartmentId = v)
//                             ),
//                             const SizedBox(height: 10),
//
//                             // Multi Select Location UI
//                             InkWell(
//                               onTap: () async {
//                                 await showDialog(
//                                   context: context,
//                                   builder: (ctx) {
//                                     return StatefulBuilder(builder: (context, setInnerState) {
//                                       return AlertDialog(
//                                         title: const Text("Select Locations"),
//                                         content: SizedBox(
//                                           width: double.maxFinite,
//                                           child: ListView.builder(
//                                             shrinkWrap: true,
//                                             itemCount: _locationList.length,
//                                             itemBuilder: (context, index) {
//                                               final loc = _locationList[index];
//                                               final isSelected = _selectedLocationIds.contains(loc['_id']);
//                                               return CheckboxListTile(
//                                                 value: isSelected,
//                                                 title: Text(loc['name']),
//                                                 activeColor: Colors.indigo,
//                                                 onChanged: (bool? checked) {
//                                                   setInnerState(() {
//                                                     if (checked == true) _selectedLocationIds.add(loc['_id']);
//                                                     else _selectedLocationIds.remove(loc['_id']);
//                                                   });
//                                                   setStateDialog(() {});
//                                                 },
//                                               );
//                                             },
//                                           ),
//                                         ),
//                                         actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Done"))],
//                                       );
//                                     });
//                                   },
//                                 );
//                               },
//                               child: Container(
//                                 padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
//                                 decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(12)),
//                                 child: Row(
//                                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                                   children: [
//                                     Expanded(child: Text(_selectedLocationsText, style: TextStyle(color: _selectedLocationIds.isEmpty ? Colors.grey[600] : Colors.black87))),
//                                     const Icon(Icons.arrow_drop_down, color: Colors.grey),
//                                   ],
//                                 ),
//                               ),
//                             ),
//
//                             const SizedBox(height: 10),
//                             _buildDropdown(
//                                 value: _shiftList.any((s) => s['_id'] == _selectedShiftId) ? _selectedShiftId : null,
//                                 hint: "Shift",
//                                 items: _shiftList.map((s) => DropdownMenuItem<String>(value: s['_id'], child: Text(s['name']))).toList(),
//                                 onChanged: (v) => setStateDialog(() => _selectedShiftId = v)
//                             ),
//                           ],
//                         ),
//                         const SizedBox(height: 10),
//
//                         _buildDropdown(
//                             value: _selectedGender,
//                             hint: "Gender",
//                             items: const [DropdownMenuItem(value: 1, child: Text("Male")), DropdownMenuItem(value: 2, child: Text("Female"))],
//                             onChanged: (v) => setStateDialog(() => _selectedGender = v ?? 1)
//                         ),
//
//                         const SizedBox(height: 25),
//
//                         Row(
//                           children: [
//                             Expanded(child: TextButton(onPressed: () {
//                               Navigator.pop(context); // Close Dialog
//                               _initializeCamera(); // Restart Camera on Cancel
//                               setState(() => _isProcessing = false);
//                             }, child: const Text("Cancel"))),
//
//                             Expanded(child: ElevatedButton(
//                                 style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
//                                 onPressed: () async {
//                                   // Validation
//                                   if (_nameController.text.isEmpty || _selectedLocationIds.isEmpty || _selectedShiftId == null || _selectedDepartmentId == null) {
//                                     _showTopNotification("Fill all fields", true);
//                                     return;
//                                   }
//
//                                   Navigator.pop(c); // Close Dialog
//                                   setState(() => _isProcessing = true);
//                                   _showTopNotification("Registering...", false);
//
//                                   // API CALL
//                                   var result = await _apiService.registerEmployee(
//                                     name: _nameController.text,
//                                     email: _emailController.text,
//                                     phone: _phoneController.text,
//                                     gender: _selectedGender,
//                                     designation: _designationController.text,
//                                     departmentId: _selectedDepartmentId!,
//                                     locationIds: _selectedLocationIds,
//                                     shiftId: _selectedShiftId!,
//                                     imageFile: facePhoto,
//                                     faceEmbedding: embedding,
//                                     joiningDate: _dateController.text,
//                                   );
//
//                                   if (result['success'] == true) {
//                                     _showTopNotification(result['message'], false);
//
//                                     // 🔴 5. SUCCESS: Clear & Restart for Next
//                                     _clearControllers();
//                                     await Future.delayed(const Duration(seconds: 1));
//                                     if(mounted) _initializeCamera();
//
//                                   } else {
//                                     _showTopNotification(result['message'] ?? "Error", true);
//                                     if(mounted) {
//                                       setState(() => _isProcessing = false);
//                                       _initializeCamera();
//                                     }
//                                   }
//                                 },
//                                 child: const Text("Save", style: TextStyle(color: Colors.white))
//                             )),
//                           ],
//                         )
//                       ],
//                     ),
//                   )
//                 ],
//               ),
//             ),
//           );
//         },
//       ),
//     );
//   }
//
//   Widget _buildTextField(TextEditingController ctrl, String hint, IconData icon, {TextInputType type = TextInputType.text}) {
//     return TextField(
//       controller: ctrl,
//       keyboardType: type,
//       decoration: InputDecoration(
//           prefixIcon: Icon(icon, size: 20),
//           hintText: hint,
//           border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
//           contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0)
//       ),
//     );
//   }
//
//   Widget _buildDropdown<T>({required T? value, required String hint, required List<DropdownMenuItem<T>> items, required Function(T?) onChanged}) {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 10),
//       decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(12)),
//       child: DropdownButtonHideUnderline(
//         child: DropdownButton<T>(
//           value: value,
//           isExpanded: true,
//           hint: Text(hint),
//           items: items,
//           onChanged: onChanged,
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
//                 decoration: BoxDecoration(
//                     color: err ? Colors.redAccent : Colors.green,
//                     borderRadius: BorderRadius.circular(30),
//                     boxShadow: [const BoxShadow(color: Colors.black26, blurRadius: 10)]
//                 ),
//                 child: Text(m, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
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
//     _controller?.dispose();
//     _faceDetector.close();
//     super.dispose();
//   }
//
//   @override
//   void didChangeAppLifecycleState(AppLifecycleState state) {
//     if (state == AppLifecycleState.resumed) {
//       _initializeCamera();
//     } else if (state == AppLifecycleState.inactive) {
//       _controller?.dispose();
//     }
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: Colors.black,
//       body: Stack(
//         children: [
//           if (_controller != null && _controller!.value.isInitialized)
//             SizedBox.expand(
//               child: FittedBox(
//                 fit: BoxFit.cover,
//                 child: SizedBox(
//                   width: _controller!.value.previewSize!.height,
//                   height: _controller!.value.previewSize!.width,
//                   child: CameraPreview(
//                     _controller!,
//                     child: CustomPaint(painter: FacePainter(faces: _faces, imageSize: _controller!.value.previewSize!)),
//                   ),
//                 ),
//               ),
//             )
//           else
//             const Center(child: CircularProgressIndicator(color: Colors.white)),
//
//           Positioned(top: 50, left: 20, child: GestureDetector(onTap: () => Navigator.pop(context), child: Container(padding: const EdgeInsets.all(8), decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle), child: const Icon(Icons.arrow_back, color: Colors.white)))),
//
//           Positioned(
//             bottom: 0, left: 0, right: 0,
//             child: ClipRRect(
//               borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
//               child: BackdropFilter(
//                 filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
//                 child: Container(
//                   padding: const EdgeInsets.fromLTRB(20, 30, 20, 40),
//                   decoration: BoxDecoration(color: Colors.black.withOpacity(0.6)),
//                   child: Column(
//                     children: [
//                       Text(_isProcessing ? "Processing..." : "Align Face to Register", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
//                       const SizedBox(height: 20),
//                       SizedBox(width: double.infinity, height: 55, child: ElevatedButton(onPressed: _isProcessing ? null : _handleRegistration, style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), child: Ink(decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF2E3192), Color(0xFF1BFFFF)]), borderRadius: BorderRadius.circular(15)), child: Center(child: _isProcessing ? const CircularProgressIndicator(color: Colors.white) : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.camera, color: Colors.white), SizedBox(width: 10), Text("CAPTURE & REGISTER", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white))])))))
//                     ],
//                   ),
//                 ),
//               ),
//             ),
//           ),
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
//
//
//
//
//
//
//
// // import 'dart:async';
// // import 'dart:ui';
// // import 'dart:io';
// // import 'package:camera/camera.dart';
// // import 'package:flutter/material.dart';
// // import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
// // import 'package:intl/intl.dart'; // 🔴 DATE FORMATTING KE LIYE
// //
// // import '../../constants/app_colors.dart';
// // import '../../main.dart'; // Ensure 'cameras' list is accessible
// // import '../../services/api_service.dart';
// // import '../../services/ml_service.dart';
// // import '../../widgets/face_painter.dart';
// //
// // class AttendanceRegisterScreen extends StatefulWidget {
// //   const AttendanceRegisterScreen({super.key});
// //
// //   @override
// //   State<AttendanceRegisterScreen> createState() => _AttendanceRegisterScreenState();
// // }
// //
// // class _AttendanceRegisterScreenState extends State<AttendanceRegisterScreen> with WidgetsBindingObserver {
// //   final MLService _mlService = MLService();
// //   final ApiService _apiService = ApiService();
// //
// //   // Text Controllers
// //   final TextEditingController _nameController = TextEditingController();
// //   final TextEditingController _emailController = TextEditingController();
// //   final TextEditingController _phoneController = TextEditingController();
// //   final TextEditingController _designationController = TextEditingController();
// //
// //   // 🔴 CHANGE 1: DATE CONTROLLER
// //   final TextEditingController _dateController = TextEditingController();
// //
// //   // Dropdown Data
// //   List<dynamic> _locationList = [];
// //   List<dynamic> _departmentList = [];
// //   List<dynamic> _shiftList = [];
// //
// //   // Location List
// //   List<String> _selectedLocationIds = [];
// //
// //   String? _selectedShiftId;
// //   String? _selectedDepartmentId;
// //   int _selectedGender = 1;
// //   bool _isLoadingDropdowns = false;
// //
// //   // Camera & ML
// //   CameraController? _controller;
// //   late FaceDetector _faceDetector;
// //   List<Face> _faces = [];
// //   CameraImage? _savedImage;
// //
// //   bool _isDetecting = false;
// //   bool _isProcessing = false;
// //
// //   @override
// //   void initState() {
// //     super.initState();
// //     WidgetsBinding.instance.addObserver(this);
// //     _faceDetector = FaceDetector(options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast));
// //
// //     // 🔴 Default Date = Aaj ki date
// //     _dateController.text = DateFormat('yyyy-MM-dd').format(DateTime.now());
// //
// //     _fetchDropdownData();
// //     _initializeCamera();
// //   }
// //
// //   // 🔴 CHANGE 2: COMPLETE RESET FUNCTION
// //   void _clearControllers() {
// //     _nameController.clear();
// //     _emailController.clear();
// //     _phoneController.clear();
// //     _designationController.clear();
// //
// //     // Date wapis aaj pe set kardo
// //     _dateController.text = DateFormat('yyyy-MM-dd').format(DateTime.now());
// //
// //     // Dropdowns Reset
// //     if (mounted) {
// //       setState(() {
// //         _selectedLocationIds = [];
// //         _selectedShiftId = null;
// //         _selectedDepartmentId = null;
// //         _selectedGender = 1;
// //         _faces = []; // Chehra hatao
// //         _savedImage = null; // Image hatao
// //       });
// //     }
// //   }
// //
// //   // Helper to show selected locations text
// //   String get _selectedLocationsText {
// //     if (_selectedLocationIds.isEmpty) return "Select Locations";
// //     if (_locationList.isEmpty) return "Loading...";
// //
// //     List<String> names = [];
// //     for (var id in _selectedLocationIds) {
// //       var loc = _locationList.firstWhere((element) => element['_id'] == id, orElse: () => null);
// //       if (loc != null) names.add(loc['name']);
// //     }
// //     return names.join(", ");
// //   }
// //
// //   void _fetchDropdownData() async {
// //     setState(() => _isLoadingDropdowns = true);
// //     try {
// //       var locs = await _apiService.getLocations();
// //       var shifts = await _apiService.getShifts();
// //       var departments = await _apiService.getDepartments();
// //
// //       if (mounted) {
// //         setState(() {
// //           _locationList = locs;
// //           _shiftList = shifts;
// //           _departmentList = departments;
// //
// //           // Auto Select First Options
// //           if (_departmentList.isNotEmpty) _selectedDepartmentId = _departmentList[0]['_id'];
// //           if (_shiftList.isNotEmpty) _selectedShiftId = _shiftList[0]['_id'];
// //
// //           _isLoadingDropdowns = false;
// //         });
// //       }
// //     } catch (e) {
// //       debugPrint("Dropdown Error: $e");
// //       if (mounted) setState(() => _isLoadingDropdowns = false);
// //     }
// //   }
// //
// //   void _initializeCamera() async {
// //     if (cameras.isEmpty) return;
// //
// //     final oldController = _controller;
// //     if (mounted) {
// //       setState(() {
// //         _controller = null;
// //         _isDetecting = false;
// //         _faces = [];
// //       });
// //     }
// //
// //     if (oldController != null) {
// //       try {
// //         await oldController.dispose();
// //       } catch (e) {
// //         debugPrint("Error disposing camera: $e");
// //       }
// //     }
// //
// //     CameraDescription? selectedCamera;
// //     for (var cam in cameras) {
// //       if (cam.lensDirection == CameraLensDirection.front) {
// //         selectedCamera = cam;
// //         break;
// //       }
// //     }
// //     if (selectedCamera == null && cameras.isNotEmpty) selectedCamera = cameras[0];
// //
// //     if (selectedCamera == null) return;
// //
// //     CameraController newController = CameraController(
// //         selectedCamera,
// //         ResolutionPreset.medium,
// //         enableAudio: false,
// //         imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888
// //     );
// //
// //     try {
// //       await newController.initialize();
// //       if (!mounted) return;
// //
// //       setState(() {
// //         _controller = newController;
// //       });
// //
// //       newController.startImageStream((image) {
// //         _savedImage = image;
// //         if (mounted && !_isDetecting && !_isProcessing) {
// //           _doFaceDetection(image);
// //         }
// //       });
// //     } catch (e) {
// //       debugPrint("Camera Init Error: $e");
// //     }
// //   }
// //
// //   Future<void> _doFaceDetection(CameraImage image) async {
// //     if (_isDetecting || !mounted) return;
// //     _isDetecting = true;
// //
// //     try {
// //       final inputImage = _convertCameraImage(image);
// //       if (inputImage != null) {
// //         final faces = await _faceDetector.processImage(inputImage);
// //         if (mounted) setState(() => _faces = faces);
// //       }
// //     } catch (e) {
// //       debugPrint("Face Detection Error: $e");
// //     } finally {
// //       if (mounted) _isDetecting = false;
// //     }
// //   }
// //
// //   InputImage? _convertCameraImage(CameraImage image) {
// //     if (_controller == null) return null;
// //     try {
// //       final camera = _controller!.description;
// //       final sensorOrientation = camera.sensorOrientation;
// //       InputImageRotation rotation = InputImageRotation.rotation0deg;
// //
// //       if (Platform.isAndroid) {
// //         var rotationCompensation = (sensorOrientation + 0) % 360;
// //         rotation = InputImageRotationValue.fromRawValue(rotationCompensation) ?? InputImageRotation.rotation270deg;
// //       }
// //
// //       return InputImage.fromBytes(
// //         bytes: _mlService.concatenatePlanes(image.planes),
// //         metadata: InputImageMetadata(
// //           size: Size(image.width.toDouble(), image.height.toDouble()),
// //           rotation: rotation,
// //           format: Platform.isAndroid ? InputImageFormat.nv21 : InputImageFormat.bgra8888,
// //           bytesPerRow: image.planes[0].bytesPerRow,
// //         ),
// //       );
// //     } catch (e) {
// //       return null;
// //     }
// //   }
// //
// //   Future<void> _handleRegistration() async {
// //     if (_faces.isEmpty || _savedImage == null) {
// //       _showTopNotification("No face detected!", true);
// //       return;
// //     }
// //
// //     setState(() => _isProcessing = true);
// //
// //     try {
// //       List<double> emb = await _mlService.getEmbedding(_savedImage!, _faces[0]);
// //
// //       // Check Duplicacy
// //       Map<String, dynamic> result = await _apiService.checkFaceExistence(emb);
// //
// //       if (result['code'] == 422 || result['code'] == 409) {
// //         // 🔥 Backend Message Show
// //         _showTopNotification(result['message'], true);
// //         setState(() => _isProcessing = false);
// //
// //         // Wait and Restart Camera (Taaki wo atak na jaye)
// //         await Future.delayed(const Duration(seconds: 2));
// //         _initializeCamera();
// //         return;
// //       }
// //
// //       XFile photo = await _controller!.takePicture();
// //       File imageFile = File(photo.path);
// //
// //       await _safeStopCamera();
// //
// //       if (mounted) {
// //         _showFullRegistrationForm(emb, imageFile);
// //       }
// //
// //     } catch (e) {
// //       debugPrint("Register Error: $e");
// //       _showTopNotification("Failed. Try again.", true);
// //       _initializeCamera();
// //     } finally {
// //       if (mounted) setState(() => _isProcessing = false);
// //     }
// //   }
// //
// //   Future<void> _safeStopCamera() async {
// //     if (_controller != null && _controller!.value.isStreamingImages) {
// //       try {
// //         await _controller!.stopImageStream();
// //       } catch (_) {}
// //     }
// //   }
// //
// //   // 🔴 CHANGE 3: DATE PICKER LOGIC
// //   Future<void> _selectDate(BuildContext context) async {
// //     DateTime? picked = await showDatePicker(
// //       context: context,
// //       initialDate: DateTime.now(),
// //       firstDate: DateTime(2000),
// //       lastDate: DateTime(2100),
// //       builder: (context, child) {
// //         return Theme(
// //           data: Theme.of(context).copyWith(
// //             colorScheme: const ColorScheme.light(primary: Color(0xFF2E3192)),
// //           ),
// //           child: child!,
// //         );
// //       },
// //     );
// //     if (picked != null) {
// //       setState(() {
// //         _dateController.text = DateFormat('yyyy-MM-dd').format(picked);
// //       });
// //     }
// //   }
// //
// //   void _showFullRegistrationForm(List<double> embedding, File facePhoto) {
// //     showDialog(
// //       context: context,
// //       barrierDismissible: false,
// //       builder: (c) => StatefulBuilder(
// //         builder: (context, setStateDialog) {
// //           return Dialog(
// //             shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
// //             backgroundColor: Colors.white,
// //             child: SingleChildScrollView(
// //               child: Column(
// //                 mainAxisSize: MainAxisSize.min,
// //                 children: [
// //                   Container(
// //                     width: double.infinity,
// //                     padding: const EdgeInsets.symmetric(vertical: 20),
// //                     decoration: const BoxDecoration(
// //                       gradient: LinearGradient(colors: [Color(0xFF2E3192), Color(0xFF1BFFFF)]),
// //                       borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
// //                     ),
// //                     child: const Center(child: Text("New Profile", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
// //                   ),
// //
// //                   Padding(
// //                     padding: const EdgeInsets.all(20),
// //                     child: Column(
// //                       children: [
// //                         CircleAvatar(radius: 40, backgroundImage: FileImage(facePhoto)),
// //                         const SizedBox(height: 20),
// //
// //                         // 🔴 DATE PICKER FIELD ADDED
// //                         TextField(
// //                           controller: _dateController,
// //                           readOnly: true, // Keyboard nahi khulega
// //                           onTap: () => _selectDate(context),
// //                           decoration: InputDecoration(
// //                               prefixIcon: const Icon(Icons.calendar_today, size: 20),
// //                               hintText: "Joining Date",
// //                               labelText: "Joining Date",
// //                               border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
// //                               contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0)
// //                           ),
// //                         ),
// //                         const SizedBox(height: 10),
// //
// //                         _buildTextField(_nameController, "Full Name", Icons.person),
// //                         const SizedBox(height: 10),
// //                         _buildTextField(_emailController, "Email", Icons.email, type: TextInputType.emailAddress),
// //                         const SizedBox(height: 10),
// //                         _buildTextField(_phoneController, "Phone", Icons.phone, type: TextInputType.phone),
// //                         const SizedBox(height: 10),
// //                         _buildTextField(_designationController, "Designation", Icons.work),
// //                         const SizedBox(height: 10),
// //
// //                         _isLoadingDropdowns
// //                             ? const LinearProgressIndicator()
// //                             : Column(
// //                           children: [
// //                             _buildDropdown(
// //                                 value: _departmentList.any((d) => d['_id'] == _selectedDepartmentId) ? _selectedDepartmentId : null,
// //                                 hint: "Department",
// //                                 items: _departmentList.map((d) => DropdownMenuItem<String>(value: d['_id'], child: Text(d['name']))).toList(),
// //                                 onChanged: (v) => setStateDialog(() => _selectedDepartmentId = v)
// //                             ),
// //                             const SizedBox(height: 10),
// //
// //                             // Multi Select Location
// //                             InkWell(
// //                               onTap: () async {
// //                                 await showDialog(
// //                                   context: context,
// //                                   builder: (ctx) {
// //                                     return StatefulBuilder(
// //                                       builder: (context, setInnerState) {
// //                                         return AlertDialog(
// //                                           title: const Text("Select Locations"),
// //                                           content: SizedBox(
// //                                             width: double.maxFinite,
// //                                             child: ListView.builder(
// //                                               shrinkWrap: true,
// //                                               itemCount: _locationList.length,
// //                                               itemBuilder: (context, index) {
// //                                                 final loc = _locationList[index];
// //                                                 final isSelected = _selectedLocationIds.contains(loc['_id']);
// //                                                 return CheckboxListTile(
// //                                                   value: isSelected,
// //                                                   title: Text(loc['name']),
// //                                                   activeColor: Colors.indigo,
// //                                                   onChanged: (bool? checked) {
// //                                                     setInnerState(() {
// //                                                       if (checked == true) {
// //                                                         _selectedLocationIds.add(loc['_id']);
// //                                                       } else {
// //                                                         _selectedLocationIds.remove(loc['_id']);
// //                                                       }
// //                                                     });
// //                                                     setStateDialog(() {});
// //                                                   },
// //                                                 );
// //                                               },
// //                                             ),
// //                                           ),
// //                                           actions: [
// //                                             TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Done"))
// //                                           ],
// //                                         );
// //                                       },
// //                                     );
// //                                   },
// //                                 );
// //                               },
// //                               child: Container(
// //                                 padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
// //                                 decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(12)),
// //                                 child: Row(
// //                                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
// //                                   children: [
// //                                     Expanded(
// //                                       child: Text(
// //                                         _selectedLocationsText,
// //                                         style: TextStyle(color: _selectedLocationIds.isEmpty ? Colors.grey[600] : Colors.black87, overflow: TextOverflow.ellipsis),
// //                                       ),
// //                                     ),
// //                                     const Icon(Icons.arrow_drop_down, color: Colors.grey),
// //                                   ],
// //                                 ),
// //                               ),
// //                             ),
// //
// //                             const SizedBox(height: 10),
// //                             _buildDropdown(
// //                                 value: _shiftList.any((s) => s['_id'] == _selectedShiftId) ? _selectedShiftId : null,
// //                                 hint: "Shift",
// //                                 items: _shiftList.map((s) => DropdownMenuItem<String>(value: s['_id'], child: Text(s['name']))).toList(),
// //                                 onChanged: (v) => setStateDialog(() => _selectedShiftId = v)
// //                             ),
// //                           ],
// //                         ),
// //                         const SizedBox(height: 10),
// //
// //                         _buildDropdown(
// //                             value: _selectedGender,
// //                             hint: "Gender",
// //                             items: const [DropdownMenuItem(value: 1, child: Text("Male")), DropdownMenuItem(value: 2, child: Text("Female"))],
// //                             onChanged: (v) => setStateDialog(() => _selectedGender = v ?? 1)
// //                         ),
// //
// //                         const SizedBox(height: 25),
// //
// //                         Row(
// //                           children: [
// //                             Expanded(child: TextButton(onPressed: () {
// //                               Navigator.pop(context);
// //                               _clearControllers();
// //                               _initializeCamera();
// //                             }, child: const Text("Cancel"))),
// //
// //                             Expanded(child: ElevatedButton(
// //                                 style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
// //                                 onPressed: () async {
// //                                   // Validation
// //                                   if (_nameController.text.isEmpty || _selectedLocationIds.isEmpty || _selectedShiftId == null || _selectedDepartmentId == null) {
// //                                     _showTopNotification("Fill all fields", true);
// //                                     return;
// //                                   }
// //
// //                                   // 🔴 CLOSE DIALOG FIRST (To Avoid Null Check Error)
// //                                   Navigator.pop(c);
// //
// //                                   // Show Loading
// //                                   setState(() => _isProcessing = true);
// //                                   _showTopNotification("Saving...", false);
// //
// //                                   var result = await _apiService.registerEmployee(
// //                                     name: _nameController.text,
// //                                     email: _emailController.text,
// //                                     phone: _phoneController.text,
// //                                     gender: _selectedGender,
// //                                     designation: _designationController.text,
// //                                     departmentId: _selectedDepartmentId!,
// //                                     locationIds: _selectedLocationIds,
// //                                     shiftId: _selectedShiftId!,
// //                                     imageFile: facePhoto,
// //                                     faceEmbedding: embedding,
// //
// //                                     // 🔴 PASSING SELECTED DATE
// //                                     joiningDate: _dateController.text,
// //                                   );
// //
// //                                   if (result['success'] == true) {
// //                                     // Success - Backend Message
// //                                     _showTopNotification(result['message'], false);
// //
// //                                     // 🔴 RESET FORM & RESTART CAMERA (No Navigator.pop for Screen)
// //                                     _clearControllers();
// //                                     setState(() {
// //                                       _isProcessing = false;
// //                                       _faces = []; // Clear face box
// //                                       _savedImage = null;
// //                                     });
// //
// //                                     await Future.delayed(const Duration(seconds: 1));
// //                                     if (mounted) _initializeCamera(); // Ready for next person
// //
// //                                   } else {
// //                                     // Error
// //                                     _showTopNotification(result['message'] ?? "Error", true);
// //                                     setState(() => _isProcessing = false);
// //                                     _initializeCamera();
// //                                   }
// //                                 },
// //                                 child: const Text("Save", style: TextStyle(color: Colors.white))
// //                             )),
// //                           ],
// //                         )
// //                       ],
// //                     ),
// //                   )
// //                 ],
// //               ),
// //             ),
// //           );
// //         },
// //       ),
// //     );
// //   }
// //
// //   Widget _buildTextField(TextEditingController ctrl, String hint, IconData icon, {TextInputType type = TextInputType.text}) {
// //     return TextField(
// //       controller: ctrl,
// //       keyboardType: type,
// //       decoration: InputDecoration(
// //           prefixIcon: Icon(icon, size: 20),
// //           hintText: hint,
// //           border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
// //           contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0)
// //       ),
// //     );
// //   }
// //
// //   Widget _buildDropdown<T>({required T? value, required String hint, required List<DropdownMenuItem<T>> items, required Function(T?) onChanged}) {
// //     return Container(
// //       padding: const EdgeInsets.symmetric(horizontal: 10),
// //       decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(12)),
// //       child: DropdownButtonHideUnderline(
// //         child: DropdownButton<T>(
// //           value: value,
// //           isExpanded: true,
// //           hint: Text(hint),
// //           items: items,
// //           onChanged: onChanged,
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
// //                 decoration: BoxDecoration(
// //                     color: err ? Colors.redAccent : Colors.green,
// //                     borderRadius: BorderRadius.circular(30),
// //                     boxShadow: [const BoxShadow(color: Colors.black26, blurRadius: 10)]
// //                 ),
// //                 child: Text(m, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
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
// //     _controller?.dispose();
// //     _faceDetector.close();
// //     super.dispose();
// //   }
// //
// //   @override
// //   void didChangeAppLifecycleState(AppLifecycleState state) {
// //     if (state == AppLifecycleState.resumed) {
// //       _initializeCamera();
// //     } else if (state == AppLifecycleState.inactive) {
// //       if (_controller != null) {
// //         final oldController = _controller;
// //         if (mounted) setState(() => _controller = null);
// //         oldController?.dispose();
// //       }
// //     }
// //   }
// //
// //   @override
// //   Widget build(BuildContext context) {
// //     return Scaffold(
// //       backgroundColor: Colors.black,
// //       body: Stack(
// //         children: [
// //           if (_controller != null && _controller!.value.isInitialized)
// //             SizedBox.expand(
// //               child: FittedBox(
// //                 fit: BoxFit.cover,
// //                 child: SizedBox(
// //                   width: _controller!.value.previewSize!.height,
// //                   height: _controller!.value.previewSize!.width,
// //                   child: CameraPreview(
// //                     _controller!,
// //                     child: CustomPaint(painter: FacePainter(faces: _faces, imageSize: _controller!.value.previewSize!)),
// //                   ),
// //                 ),
// //               ),
// //             )
// //           else
// //             const Center(child: CircularProgressIndicator(color: Colors.white)),
// //
// //           Positioned(top: 50, left: 20, child: GestureDetector(onTap: () => Navigator.pop(context), child: Container(padding: const EdgeInsets.all(8), decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle), child: const Icon(Icons.arrow_back, color: Colors.white)))),
// //
// //           Positioned(
// //             bottom: 0, left: 0, right: 0,
// //             child: ClipRRect(
// //               borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
// //               child: BackdropFilter(
// //                 filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
// //                 child: Container(
// //                   padding: const EdgeInsets.fromLTRB(20, 30, 20, 40),
// //                   decoration: BoxDecoration(color: Colors.black.withOpacity(0.6)),
// //                   child: Column(
// //                     children: [
// //                       Text(_isProcessing ? "Processing..." : "Align Face to Register", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
// //                       const SizedBox(height: 20),
// //                       SizedBox(width: double.infinity, height: 55, child: ElevatedButton(onPressed: _isProcessing ? null : _handleRegistration, style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), child: Ink(decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF2E3192), Color(0xFF1BFFFF)]), borderRadius: BorderRadius.circular(15)), child: Center(child: _isProcessing ? const CircularProgressIndicator(color: Colors.white) : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.camera, color: Colors.white), SizedBox(width: 10), Text("CAPTURE & REGISTER", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white))])))))
// //                     ],
// //                   ),
// //                 ),
// //               ),
// //             ),
// //           ),
// //         ],
// //       ),
// //     );
// //   }
// // }
