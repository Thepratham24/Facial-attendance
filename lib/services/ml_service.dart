import 'dart:math';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

class MLService {
  static final MLService _instance = MLService._internal();
  factory MLService() => _instance;
  MLService._internal();

  Interpreter? _interpreter;
  IsolateInterpreter? _isolateInterpreter;

  Future<void> initialize() async {
    if (_interpreter != null) return;
    try {
      _interpreter = await Interpreter.fromAsset('assets/mobilefacenet.tflite');
      _isolateInterpreter = await IsolateInterpreter.create(address: _interpreter!.address);
      debugPrint("ML Service: AI Brain Loaded");
    } catch (e) {
      debugPrint("ML Service Error: $e");
    }
  }

  Future<List<double>> getEmbedding(CameraImage cameraImage, Face face) async {
    if (_isolateInterpreter == null) {
      throw Exception("AI Brain not initialized yet");
    }

    img.Image image = _convertCameraImage(cameraImage);

    int x = (face.boundingBox.left - 10).toInt().clamp(0, image.width);
    int y = (face.boundingBox.top - 10).toInt().clamp(0, image.height);
    int w = (face.boundingBox.width + 20).toInt().clamp(0, image.width - x);
    int h = (face.boundingBox.height + 20).toInt().clamp(0, image.height - y);

    img.Image croppedFace = img.copyCrop(image, x: x, y: y, width: w, height: h);
    img.Image resizedFace = img.copyResize(croppedFace, width: 112, height: 112);

    Float32List input = _imageToByteListFloat32(resizedFace);
    var inputReshaped = input.reshape([1, 112, 112, 3]);
    var output = List.filled(1 * 192, 0.0).reshape([1, 192]);

    await _isolateInterpreter!.run(inputReshaped, output);
    return List<double>.from(output[0]);
  }

  img.Image _convertCameraImage(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    var imgBuffer = img.Image(width: width, height: height);

    for (int x = 0; x < width; x++) {
      for (int y = 0; y < height; y++) {
        final int index = y * width + x;
        final yp = image.planes[0].bytes[index];
        imgBuffer.setPixel(x, y, img.ColorRgb8(yp, yp, yp));
      }
    }
    return img.copyRotate(imgBuffer, angle: -90);
  }

  Float32List _imageToByteListFloat32(img.Image image) {
    var buffer = Float32List(1 * 112 * 112 * 3);
    int pixelIndex = 0;
    for (var y = 0; y < 112; y++) {
      for (var x = 0; x < 112; x++) {
        var pixel = image.getPixel(x, y);
        buffer[pixelIndex++] = (pixel.r - 128) / 128;
        buffer[pixelIndex++] = (pixel.g - 128) / 128;
        buffer[pixelIndex++] = (pixel.b - 128) / 128;
      }
    }
    return buffer;
  }

  Uint8List concatenatePlanes(List<Plane> planes) {
    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in planes) {
      allBytes.putUint8List(plane.bytes);
    }
    return allBytes.done().buffer.asUint8List();
  }
}