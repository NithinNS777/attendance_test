import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For WriteBuffer
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart'; // Updated import
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import 'dart:typed_data';
import 'dart:collection'; // For UnmodifiableUint8ListView

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp();

  // Request permissions
  await Permission.camera.request();
  await Permission.storage.request();

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Attendance App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: MyHomePage(title: 'Attendance App'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  final String title;
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _rollNoController = TextEditingController();
  final TextEditingController _classController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> students = [];

  @override
  void initState() {
    super.initState();
    _fetchStudents();
  }

  Future<void> _fetchStudents() async {
    try {
      final QuerySnapshot snapshot = await _firestore.collection('students').get();
      setState(() {
        students = snapshot.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();
      });
    } catch (e) {
      print('Error fetching students: $e');
    }
  }

  Future<void> _navigateToCameraScreen() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CameraScreen(),
      ),
    );

    if (result != null && result is List<double>) {
      await _submitData(result);
    }
  }

  Future<void> _submitData(List<double> faceEmbedding) async {
    try {
      await _firestore.collection('students').add({
        'username': _usernameController.text,
        'rollNo': _rollNoController.text,
        'class': _classController.text,
        'timestamp': FieldValue.serverTimestamp(),
        'faceEmbedding': faceEmbedding,
      });

      _usernameController.clear();
      _rollNoController.clear();
      _classController.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Face data stored successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error submitting data: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 300),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        border: UnderlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(vertical: 8.0),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _rollNoController,
                      decoration: const InputDecoration(
                        labelText: 'Roll Number',
                        border: UnderlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(vertical: 8.0),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _classController,
                      decoration: const InputDecoration(
                        labelText: 'Class',
                        border: UnderlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(vertical: 8.0),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () {
                        if (_usernameController.text.isNotEmpty &&
                            _rollNoController.text.isNotEmpty &&
                            _classController.text.isNotEmpty) {
                          _navigateToCameraScreen();
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please fill all fields'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
                      child: const Text('Submit'),
                    ),
                  ],
                ),
              ),
            ),
            // Student list
            const SizedBox(height: 24),
            const Text(
              'Registered Students',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            ListView.builder(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              itemCount: students.length,
              itemBuilder: (context, index) {
                final student = students[index];
                return ListTile(
                  title: Text(student['username'] ?? ''),
                  subtitle: Text('Roll No: ${student['rollNo']} | Class: ${student['class']}'),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _rollNoController.dispose();
    _classController.dispose();
    super.dispose();
  }
}

class CameraScreen extends StatefulWidget {
  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _cameraController;
  bool _isCameraInitialized = false;
  bool _isProcessing = false;
  late Interpreter _interpreter;
  late FaceDetector _faceDetector;
  Face? detectedFace;
  Size? imageSize;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _loadModel();
    // Updated FaceDetector instantiation for google_mlkit_face_detection
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: true,
        enableClassification: true,
        enableTracking: true,
        performanceMode: FaceDetectorMode.accurate,
      ),
    );
  }

  Future<void> _loadModel() async {
    try {
      final modelPath = 'assets/facenet_model.tflite';
      _interpreter = await Interpreter.fromAsset(modelPath);
      print('FaceNet model loaded successfully');
    } catch (e) {
      print('Error loading FaceNet model: $e');
    }
  }

  Future<void> _initializeCamera() async {
    try {
      // Request camera permission
      final status = await Permission.camera.request();
      if (status.isDenied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Camera permission is required'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      print('Getting available cameras...');
      final cameras = await availableCameras();
      print('Available cameras: ${cameras.length}');

      if (cameras.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No cameras found'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      print('Selecting front camera...');
      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      print('Selected camera: ${frontCamera.name}');

      print('Initializing camera controller...');
      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.medium, // Changed to medium for better compatibility
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      print('Waiting for controller initialization...');
      await _cameraController.initialize();
      print('Camera controller initialized');

      if (!mounted) return;

      setState(() {
        _isCameraInitialized = true;
      });
      print('Camera initialization complete');
    } catch (e) {
      print('Error initializing camera: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error initializing camera: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<List<double>> _getFaceEmbedding(String imagePath, Face face) async {
    final imageFile = File(imagePath);
    final imageBytes = await imageFile.readAsBytes();
    final image = img.decodeImage(imageBytes);

    if (image == null) throw Exception('Failed to decode image');

    // Crop face region using updated copyCrop method
    final boundingBox = face.boundingBox;
    final croppedImage = img.copyCrop(
      image,
      x: boundingBox.left.toInt(),
      y: boundingBox.top.toInt(),
      width: boundingBox.width.toInt(),
      height: boundingBox.height.toInt(),
    );

    // Resize to FaceNet input size
    final resizedImage = img.copyResize(croppedImage, width: 160, height: 160);

    // Convert to float array and normalize
    var input = List<List<List<List<double>>>>.filled(
      1,
      List<List<List<double>>>.filled(
        160,
        List<List<double>>.filled(
          160,
          List<double>.filled(3, 0),
        ),
      ),
    );

    for (var y = 0; y < 160; y++) {
      for (var x = 0; x < 160; x++) {
        final pixel = resizedImage.getPixel(x, y);
        input[0][y][x][0] = (pixel.r.toDouble() - 127.5) / 128;
        input[0][y][x][1] = (pixel.g.toDouble() - 127.5) / 128;
        input[0][y][x][2] = (pixel.b.toDouble() - 127.5) / 128;
      }
    }

    var output = List<List<double>>.filled(1, List<double>.filled(128, 0));
    _interpreter.run(input, output);

    return output[0];
  }

  Future<void> _processImage(CameraImage image) async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());
      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: imageSize,
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.bgra8888,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );

      final faces = await _faceDetector.processImage(inputImage);
      if (faces.isNotEmpty) {
        setState(() {
          detectedFace = faces.first;
          this.imageSize = imageSize;
        });
      }
    } catch (e) {
      print('Error processing image: $e');
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _captureAndAnalyze() async {
    if (!_cameraController.value.isInitialized || _isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final image = await _cameraController.takePicture();

      // Detect face using ML Kit
      final inputImage = InputImage.fromFilePath(image.path);
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No face detected. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Get face embedding using FaceNet
      final faceEmbedding = await _getFaceEmbedding(image.path, faces.first);

      // Return the embedding to previous screen
      Navigator.pop(context, faceEmbedding);
    } catch (e) {
      print('Error in face detection: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Take Photo')),
      body: _isCameraInitialized
          ? Stack(
              children: [
                CameraPreview(_cameraController),
                if (detectedFace != null && imageSize != null)
                  CustomPaint(
                    painter: FacePainter(
                      face: detectedFace!,
                      imageSize: imageSize!,
                      previewSize: MediaQuery.of(context).size,
                    ),
                  ),
                Positioned(
                  bottom: 20,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing ? null : _captureAndAnalyze,
                      icon: const Icon(Icons.camera),
                      label: Text(_isProcessing ? 'Processing...' : 'Capture Photo'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(200, 50),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }

  @override
  void dispose() {
    _cameraController.dispose();
    _interpreter.close();
    _faceDetector.close();
    super.dispose();
  }
}

class FacePainter extends CustomPainter {
  final Face face;
  final Size imageSize;
  final Size previewSize;

  FacePainter({
    required this.face,
    required this.imageSize,
    required this.previewSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.red;

    final double scaleX = previewSize.width / imageSize.width;
    final double scaleY = previewSize.height / imageSize.height;

    final Rect scaledRect = Rect.fromLTRB(
      face.boundingBox.left * scaleX,
      face.boundingBox.top * scaleY,
      face.boundingBox.right * scaleX,
      face.boundingBox.bottom * scaleY,
    );

    canvas.drawRect(scaledRect, paint);

    // Draw facial landmarks with updated API
    paint.color = Colors.blue;
    face.landmarks.forEach((type, landmark) {
      if (landmark != null) {
        canvas.drawCircle(
          Offset(
            landmark.position.x * scaleX,
            landmark.position.y * scaleY,
          ),
          2,
          paint,
        );
      }
    });
  }

  @override
  bool shouldRepaint(FacePainter oldDelegate) => true;
}