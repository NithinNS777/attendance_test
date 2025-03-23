import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import 'dart:typed_data';
import 'dart:math';
import 'package:nfc_manager/nfc_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await Permission.camera.request();
  await Permission.storage.request();
  // NFC permission is handled by AndroidManifest.xml; no Permission.nfc.request() needed
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Face Attendance',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: InitialScreen(),
    );
  }
}

class InitialScreen extends StatefulWidget {
  @override
  _InitialScreenState createState() => _InitialScreenState();
}

class _InitialScreenState extends State<InitialScreen> {
  @override
  void initState() {
    super.initState();
    _startNfcListening();
  }

  Future<void> _startNfcListening() async {
    bool isNfcAvailable = await NfcManager.instance.isAvailable();
    print('NFC Availability Check: $isNfcAvailable'); // Debug log
    if (!isNfcAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('NFC is not available or enabled on this device'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    NfcManager.instance.startSession(onDiscovered: (NfcTag tag) async {
      print('NFC Tag Detected'); // Debug log
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CameraScreen(isCompareMode: true),
        ),
      );

      if (result != null && result is Map<String, dynamic>) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Attendance marked for ${result['username']} (Roll No: ${result['rollNo']})'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No match found'),
            backgroundColor: Colors.red,
          ),
        );
      }

      NfcManager.instance.stopSession();
      _startNfcListening(); // Restart listening
    });
  }

  Future<void> _navigateToCompareScreen() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CameraScreen(isCompareMode: true),
      ),
    );

    if (result != null && result is Map<String, dynamic>) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Attendance marked for ${result['username']} (Roll No: ${result['rollNo']})'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No match found'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Face Attendance'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => MyHomePage(title: 'Face Attendance'),
                  ),
                );
              },
              child: const Text('Register'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(200, 50),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _navigateToCompareScreen,
              child: const Text('Compare (Manual)'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(200, 50),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Tap an NFC sticker to mark attendance',
              style: TextStyle(fontSize: 16, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    NfcManager.instance.stopSession();
    super.dispose();
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
      print('Registered students in Firestore:');
      for (var student in students) {
        print('Username: ${student['username']}, Embedding sample: ${student['faceEmbedding'].sublist(0, 5)}...');
      }
    } catch (e) {
      print('Error fetching students: $e');
    }
  }

  Future<void> _navigateToCameraScreen() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CameraScreen(isCompareMode: false),
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
      _fetchStudents();
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
            const SizedBox(height: 24),
            const Text(
              'Registered Students',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
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
  final bool isCompareMode;

  const CameraScreen({Key? key, required this.isCompareMode}) : super(key: key);

  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _cameraController;
  bool _isCameraInitialized = false;
  bool _isProcessing = false;
  late Interpreter _interpreter;
  late FaceDetector _faceDetector;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _loadModel();
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: false,
        enableClassification: false,
        enableTracking: false,
        performanceMode: FaceDetectorMode.fast,
        minFaceSize: 0.1,
      ),
    );
    _initializeCamera();
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

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No cameras found'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _cameraController.initialize();
      if (!mounted) return;

      setState(() {
        _isCameraInitialized = true;
        print('Camera initialized');
      });

      if (widget.isCompareMode) {
        Future.delayed(Duration(seconds: 1), () {
          if (mounted) _captureAndAnalyze();
        });
      }
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

    final boundingBox = face.boundingBox;
    final croppedImage = img.copyCrop(
      image,
      x: boundingBox.left.toInt(),
      y: boundingBox.top.toInt(),
      width: boundingBox.width.toInt(),
      height: boundingBox.height.toInt(),
    );

    final resizedImage = img.copyResize(croppedImage, width: 160, height: 160);

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

    print('Generated embedding sample: ${output[0].sublist(0, 5)}...');
    return output[0];
  }

  double _calculateEuclideanDistance(List<double> embedding1, List<double> embedding2) {
    if (embedding1.length != embedding2.length) return double.infinity;
    double sum = 0;
    for (int i = 0; i < embedding1.length; i++) {
      sum += pow(embedding1[i] - embedding2[i], 2);
    }
    return sqrt(sum);
  }

  Future<Map<String, dynamic>?> _compareEmbedding(List<double> newEmbedding) async {
    print('Comparing embedding with Firestore');
    print('New embedding sample: ${newEmbedding.sublist(0, 5)}...');
    final QuerySnapshot snapshot = await _firestore.collection('students').get();
    const double threshold = 1.0;
    Map<String, dynamic>? bestMatch;
    double minDistance = double.infinity;

    for (var doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final storedEmbedding = (data['faceEmbedding'] as List<dynamic>).cast<double>();
      final distance = _calculateEuclideanDistance(newEmbedding, storedEmbedding);
      print('Distance to ${data['username']} (Roll No: ${data['rollNo']}): $distance');
      if (distance < minDistance) {
        minDistance = distance;
        bestMatch = data;
      }
    }

    if (minDistance < threshold && bestMatch != null) {
      print('Best match found: ${bestMatch['username']} with distance $minDistance');
      return bestMatch;
    } else {
      print('No match found within threshold $threshold, closest distance was $minDistance');
      return null;
    }
  }

  Future<void> _captureAndAnalyze() async {
    if (!_cameraController.value.isInitialized || _isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final image = await _cameraController.takePicture();
      print('Photo captured at: ${image.path}');

      final directory = await getTemporaryDirectory();
      final debugPath = '${directory.path}/${widget.isCompareMode ? 'compare' : 'register'}_photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(image.path).copy(debugPath);
      print('Photo saved for debug at: $debugPath');

      for (var rotation in [
        InputImageRotation.rotation0deg,
        InputImageRotation.rotation90deg,
        InputImageRotation.rotation270deg,
      ]) {
        final inputImage = InputImage.fromFilePath(image.path);

        print('Running face detection with rotation: $rotation');
        final faces = await _faceDetector.processImage(inputImage);
        print('Detected ${faces.length} faces with rotation: $rotation');

        if (faces.isNotEmpty) {
          print('Face detected successfully');
          final faceEmbedding = await _getFaceEmbedding(image.path, faces.first);

          if (widget.isCompareMode) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Scanning...'),
                backgroundColor: Colors.blue,
                duration: Duration(seconds: 2),
              ),
            );
            await Future.delayed(const Duration(seconds: 2));

            final match = await _compareEmbedding(faceEmbedding);
            Navigator.pop(context, match);
          } else {
            Navigator.pop(context, faceEmbedding);
          }
          return;
        }
      }

      print('No face detected in captured photo after trying all rotations');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No face detected. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
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
      appBar: AppBar(title: Text(widget.isCompareMode ? 'Compare Face' : 'Register Face')),
      body: _isCameraInitialized
          ? Stack(
              children: [
                CameraPreview(_cameraController),
                if (!widget.isCompareMode)
                  Positioned(
                    bottom: 20,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: ElevatedButton.icon(
                        onPressed: _isProcessing ? null : _captureAndAnalyze,
                        icon: const Icon(Icons.camera),
                        label: Text(_isProcessing ? 'Processing...' : 'Submit'),
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
    if (_isCameraInitialized) {
      _cameraController.dispose();
    }
    _interpreter.close();
    _faceDetector.close();
    super.dispose();
  }
}