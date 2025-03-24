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
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Face Attendance',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.grey[100],
        appBarTheme: AppBarTheme(
          elevation: 4,
          shadowColor: Colors.deepPurple.withOpacity(0.3),
        ),
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
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _timetable = [];
  bool _isLoadingTimetable = true;

  @override
  void initState() {
    super.initState();
    _fetchTimetable();
    _startNfcListening();
  }

  Future<void> _fetchTimetable() async {
    try {
      print('Fetching timetable...');
      final snapshot = await _firestore.collection('timetable').get();
      setState(() {
        _timetable = snapshot.docs.map((doc) => doc.data()).toList();
        _isLoadingTimetable = false;
      });
      print('Timetable fetched successfully: $_timetable');
      if (_timetable.isEmpty) {
        print('Warning: Timetable is empty!');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Timetable is empty. Check Firestore setup.', style: TextStyle(fontSize: 18))),
        );
      }
    } catch (e) {
      print('Error fetching timetable: $e');
      setState(() {
        _isLoadingTimetable = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching timetable: $e', style: const TextStyle(fontSize: 18))),
      );
    }
  }

  String? _getCurrentSubject(DateTime now) {
    print('Determining current subject at: $now');
    for (var entry in _timetable) {
      final subject = entry['subject'] as String?;
      final startHour = entry['startHour'] as int?;
      final startMinute = entry['startMinute'] as int?;
      final endHour = entry['endHour'] as int?;
      final endMinute = entry['endMinute'] as int?;

      if (subject == null || startHour == null || startMinute == null || endHour == null || endMinute == null) {
        print('Invalid timetable entry: $entry');
        continue;
      }

      DateTime start = DateTime(now.year, now.month, now.day, startHour, startMinute);
      DateTime end = DateTime(now.year, now.month, now.day, endHour, endMinute);

      print('Checking $subject: $start to $end');
      if (now.isAfter(start) && now.isBefore(end)) {
        print('Current subject: $subject');
        return subject;
      }
    }
    print('No subject scheduled at this time');
    return null;
  }

  Future<bool> _isAttendanceMarked(String rollNo, String subject) async {
    try {
      final snapshot = await _firestore
          .collection('attendance')
          .where('rollNo', isEqualTo: rollNo)
          .where('subject', isEqualTo: subject)
          .where('date', isEqualTo: DateTime.now().toIso8601String().substring(0, 10))
          .get();
      print('Attendance check for $subject (Roll No: $rollNo): ${snapshot.docs.isNotEmpty ? 'Already marked' : 'Not marked'}');
      return snapshot.docs.isNotEmpty;
    } catch (e) {
      print('Error checking attendance: $e');
      return false;
    }
  }

  Future<void> _markAttendance(String nfcId, String subject, Map<String, dynamic> studentData) async {
    try {
      bool alreadyMarked = await _isAttendanceMarked(studentData['rollNo'], subject);
      if (alreadyMarked) {
        print('Attendance already marked for ${studentData['username']} in $subject');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Attendance already marked for ${studentData['username']} in $subject',
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
            backgroundColor: Colors.orange,
            elevation: 6,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }

      print('Attempting to mark attendance for ${studentData['username']} in $subject with NFC ID: $nfcId');
      await _firestore.collection('attendance').add({
        'nfcId': nfcId,
        'subject': subject,
        'date': DateTime.now().toIso8601String().substring(0, 10),
        'timestamp': FieldValue.serverTimestamp(),
        'username': studentData['username'],
        'rollNo': studentData['rollNo'],
      });
      print('Attendance successfully marked in Firestore for ${studentData['username']}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Attendance marked for ${studentData['username']} (Roll No: ${studentData['rollNo']}) in $subject',
            style: const TextStyle(color: Colors.white, fontSize: 18),
          ),
          backgroundColor: Colors.green,
          elevation: 6,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      print('Error marking attendance: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error marking attendance: $e', style: const TextStyle(fontSize: 18)),
        ),
      );
    }
  }

  Future<void> _startNfcListening() async {
    bool isNfcAvailable = await NfcManager.instance.isAvailable();
    print('NFC Availability: $isNfcAvailable');
    if (!isNfcAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('NFC is not available or enabled', style: TextStyle(fontSize: 18)),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    NfcManager.instance.startSession(onDiscovered: (NfcTag tag) async {
      print('NFC Tag Detected');
      var identifier = tag.data['nfca']['identifier'];
      String nfcId = identifier.map((e) => e.toRadixString(16).padLeft(2, '0')).join(':').toUpperCase();
      print('Scanned NFC ID: $nfcId');

      const String targetNfcId = '53:1E:97:86:12:00:01';

      if (nfcId == targetNfcId) {
        print('NFC ID matched');
        DateTime now = DateTime.now().toLocal();
        String? currentSubject = _getCurrentSubject(now);
        print('Current time: $now, Subject: $currentSubject');

        if (currentSubject == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No class scheduled at this time', style: TextStyle(fontSize: 18)),
              backgroundColor: Colors.orange,
            ),
          );
          NfcManager.instance.stopSession();
          _startNfcListening();
          return;
        }

        final result = await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => CameraScreen(isCompareMode: true)),
        );

        if (result != null && result is Map<String, dynamic>) {
          await _markAttendance(nfcId, currentSubject, result);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No match found', style: TextStyle(color: Colors.white, fontSize: 18)),
              backgroundColor: Colors.red,
              elevation: 6,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        print('NFC ID mismatch: $nfcId != $targetNfcId');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unrecognized NFC tag: $nfcId', style: const TextStyle(fontSize: 18)),
            backgroundColor: Colors.orange,
          ),
        );
      }

      NfcManager.instance.stopSession();
      _startNfcListening();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Face Attendance', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: _isLoadingTimetable
          ? const Center(child: CircularProgressIndicator())
          : Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.deepPurple.withOpacity(0.1), Colors.white],
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => MyHomePage(title: 'Face Attendance')),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(220, 60),
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        elevation: 8,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Register', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Tap an NFC sticker to mark attendance',
                      style: TextStyle(fontSize: 16, fontStyle: FontStyle.italic, color: Colors.deepPurple, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
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

  @override
  void initState() {
    super.initState();
  }

  Future<void> _navigateToCameraScreen() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => CameraScreen(isCompareMode: false)),
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
          content: Text('Face data stored successfully!', style: TextStyle(color: Colors.white, fontSize: 18)),
          backgroundColor: Colors.green,
          elevation: 6,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error submitting data: $e', style: const TextStyle(color: Colors.white, fontSize: 18)),
          backgroundColor: Colors.red,
          elevation: 6,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.deepPurple.withOpacity(0.1), Colors.white],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 400),
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.deepPurple.withOpacity(0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextField(
                      controller: _usernameController,
                      decoration: InputDecoration(
                        labelText: 'Username',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.grey[100],
                        contentPadding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _rollNoController,
                      decoration: InputDecoration(
                        labelText: 'Roll Number',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.grey[100],
                        contentPadding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _classController,
                      decoration: InputDecoration(
                        labelText: 'Class',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.grey[100],
                        contentPadding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
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
                              content: Text('Please fill all fields', style: TextStyle(color: Colors.white, fontSize: 18)),
                              backgroundColor: Colors.red,
                              elevation: 6,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(200, 60),
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        elevation: 8,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Submit', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
          ),
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
            content: Text('Camera permission is required', style: TextStyle(color: Colors.white, fontSize: 18)),
            backgroundColor: Colors.red,
            elevation: 6,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No cameras found', style: TextStyle(color: Colors.white, fontSize: 18)),
            backgroundColor: Colors.red,
            elevation: 6,
            behavior: SnackBarBehavior.floating,
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
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) _captureAndAnalyze();
        });
      }
    } catch (e) {
      print('Error initializing camera: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error initializing camera: $e', style: const TextStyle(color: Colors.white, fontSize: 18)),
            backgroundColor: Colors.red,
            elevation: 6,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  List<double> normalizeEmbedding(List<double> embedding) {
    double norm = sqrt(embedding.fold(0.0, (sum, e) => sum + e * e));
    if (norm == 0) return embedding;
    return embedding.map((e) => e / norm).toList();
  }

  double cosineSimilarity(List<double> v1, List<double> v2) {
    if (v1.length != v2.length) return 0.0;
    double dotProduct = 0.0;
    for (int i = 0; i < v1.length; i++) {
      dotProduct += v1[i] * v2[i];
    }
    return dotProduct;
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
        List<List<double>>.filled(160, List<double>.filled(3, 0)),
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
    List<double> embedding = output[0];
    List<double> normalizedEmbedding = normalizeEmbedding(embedding);
    print('Normalized embedding sample: ${normalizedEmbedding.sublist(0, 5)}...');
    return normalizedEmbedding;
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
    const double euclideanThreshold = 0.6;
    const double cosineThreshold = 0.7;
    Map<String, dynamic>? bestMatch;
    double minEuclideanDistance = double.infinity;
    double maxCosineSimilarity = -1.0;

    List<double> normalizedNewEmbedding = normalizeEmbedding(newEmbedding);

    for (var doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final storedEmbeddingDynamic = data['faceEmbedding'] as List<dynamic>;
      List<double> storedEmbedding = storedEmbeddingDynamic.cast<double>();
      List<double> normalizedStoredEmbedding = normalizeEmbedding(storedEmbedding);

      final euclideanDistance = _calculateEuclideanDistance(normalizedNewEmbedding, normalizedStoredEmbedding);
      final cosineSim = cosineSimilarity(normalizedNewEmbedding, normalizedStoredEmbedding);

      print('To ${data['username']} (Roll No: ${data['rollNo']}): '
          'Euclidean Distance = $euclideanDistance, Cosine Similarity = $cosineSim');

      if (euclideanDistance < minEuclideanDistance) {
        minEuclideanDistance = euclideanDistance;
        maxCosineSimilarity = cosineSim;
        bestMatch = data;
      }
    }

    if (minEuclideanDistance < euclideanThreshold &&
        maxCosineSimilarity > cosineThreshold &&
        bestMatch != null) {
      print('Best match found: ${bestMatch['username']} with '
          'Euclidean Distance $minEuclideanDistance, Cosine Similarity $maxCosineSimilarity');
      return bestMatch;
    } else {
      print('No match found. Closest: Euclidean Distance = $minEuclideanDistance, '
          'Cosine Similarity = $maxCosineSimilarity');
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
                content: Text('Scanning...', style: TextStyle(color: Colors.white, fontSize: 18)),
                backgroundColor: Colors.blue,
                elevation: 6,
                behavior: SnackBarBehavior.floating,
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
          content: Text('No face detected. Please try again.', style: TextStyle(color: Colors.white, fontSize: 18)),
          backgroundColor: Colors.red,
          elevation: 6,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      print('Error in face detection: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e', style: const TextStyle(color: Colors.white, fontSize: 18)),
          backgroundColor: Colors.red,
          elevation: 6,
          behavior: SnackBarBehavior.floating,
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
      appBar: AppBar(
        title: Text(
          widget.isCompareMode ? 'Compare Face' : 'Register Face',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: _isCameraInitialized
          ? Stack(
              children: [
                CameraPreview(_cameraController),
                if (!widget.isCompareMode)
                  Positioned(
                    bottom: 30,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: ElevatedButton.icon(
                        onPressed: _isProcessing ? null : _captureAndAnalyze,
                        icon: const Icon(Icons.camera_alt, size: 28),
                        label: Text(
                          _isProcessing ? 'Processing...' : 'Submit',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(220, 60),
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                          elevation: 8,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        ),
                      ),
                    ),
                  ),
              ],
            )
          : const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.deepPurple),
              ),
            ),
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