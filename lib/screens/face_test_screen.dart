class FaceTestScreen extends StatefulWidget {
  @override
  _FaceTestScreenState createState() => _FaceTestScreenState();
}

class _FaceTestScreenState extends State<FaceTestScreen> {
  final FaceDetectionService _faceService = FaceDetectionService();
  final FirebaseService _firebaseService = FirebaseService();
  final TextEditingController _studentIdController = TextEditingController();
  Map<String, dynamic>? _faceData;
  bool _isProcessing = false;

  Future<void> _detectAndStoreFace() async {
    if (_studentIdController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter Student ID')),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
      _faceData = null;
    });

    try {
      // Detect face
      final faceData = await _faceService.detectFace();
      if (faceData == null) {
        throw 'No face detected';
      }

      // Store in Firebase
      await _firebaseService.storeFaceData(
        studentId: _studentIdController.text,
        faceData: faceData,
      );

      setState(() {
        _faceData = faceData;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Face data stored successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
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
      appBar: AppBar(title: Text('Face Registration')),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _studentIdController,
              decoration: InputDecoration(
                labelText: 'Student ID',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 20),
            if (_isProcessing)
              CircularProgressIndicator()
            else
              ElevatedButton(
                onPressed: _detectAndStoreFace,
                child: Text('Capture and Store Face Data'),
              ),
            if (_faceData != null) ...[
              SizedBox(height: 20),
              Text('Detection Confidence: ${_faceData!['confidence']}'),
              Text('Landmarks Found: ${_faceData!['landmarks'].length}'),
              Expanded(
                child: ListView(
                  children: [
                    Text('Stored Data:', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(JsonEncoder.withIndent('  ').convert(_faceData)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _studentIdController.dispose();
    super.dispose();
  }
} 