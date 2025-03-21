import 'dart:io';
import 'package:google_cloud_vision/google_cloud_vision.dart';
import 'package:image_picker/image_picker.dart';
import '../config/vision_api_config.dart';

class FaceDetectionService {
  final GoogleCloudVision vision;
  final ImagePicker _picker = ImagePicker();

  FaceDetectionService() 
      : vision = GoogleCloudVision(
          credentials: VisionApiConfig.credentialsJson,
        );

  Future<Map<String, dynamic>?> detectFace() async {
    try {
      // 1. Capture Image
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        quality: 100,
      );
      
      if (image == null) return null;

      // 2. Process Image
      final File imageFile = File(image.path);
      final List<int> imageBytes = await imageFile.readAsBytes();

      // 3. Create API Request
      final request = AnnotateImageRequest(
        image: GoogleCloudVisionImage(
          content: imageBytes.toString(),
        ),
        features: [
          GoogleCloudVisionFeature(
            type: 'FACE_DETECTION',
            maxResults: 1,
          ),
        ],
      );

      // 4. Get API Response
      final response = await vision.annotate(requests: [request]);

      if (response.responses.isEmpty || 
          response.responses.first.faceAnnotations.isEmpty) {
        throw 'No face detected';
      }

      // 5. Extract Face Data
      final face = response.responses.first.faceAnnotations.first;
      return {
        'landmarks': face.landmarks.map((l) => {
          'type': l.type,
          'position': {
            'x': l.position.x,
            'y': l.position.y,
            'z': l.position.z,
          }
        }).toList(),
        'confidence': face.detectionConfidence,
        'joy': face.joyLikelihood,
        'angles': {
          'roll': face.rollAngle,
          'pan': face.panAngle,
          'tilt': face.tiltAngle,
        }
      };
    } catch (e) {
      print('Error in face detection: $e');
      rethrow;
    }
  }
} 