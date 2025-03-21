import 'package:cloud_firestore/cloud_firestore.dart';

class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> storeFaceData({
    required String studentId,
    required Map<String, dynamic> faceData,
  }) async {
    try {
      await _firestore.collection('students').doc(studentId).set({
        'faceData': faceData,
        'registeredAt': FieldValue.serverTimestamp(),
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error storing face data: $e');
      rethrow;
    }
  }
} 