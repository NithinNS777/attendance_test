# Face Recognition Attendance System using Flutter & Firebase

![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![Firebase](https://img.shields.io/badge/Firebase-FFCA28?style=for-the-badge&logo=firebase&logoColor=black)
![TensorFlow](https://img.shields.io/badge/TensorFlow-FF6F00?style=for-the-badge&logo=tensorflow&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white)

A cross-platform mobile application built with Flutter that provides a modern solution for marking attendance using on-device face recognition and NFC technology.

---

> **Note**
> _Strongly recommend adding a GIF or screenshots here to showcase the app in action!_
>
> `![App Demo GIF](link_to_your_gif.gif)`

## ✨ Features

* [cite_start]**Student Registration**: Register new students by capturing their facial data along with their name and roll number[cite: 201, 210, 212].
* [cite_start]**On-Device Machine Learning**: Utilizes a TensorFlow Lite (`.tflite`) model (FaceNet) to convert facial features into a unique numerical "embedding" directly on the device[cite: 244, 266].
* [cite_start]**NFC-Triggered Attendance**: Attendance marking is initiated by scanning a pre-configured NFC tag, providing a quick and secure starting point[cite: 188, 189].
* [cite_start]**Real-Time Face Verification**: On scanning an NFC tag, the app captures the user's face in real-time and compares it against all registered student embeddings to find a match[cite: 190, 287].
* [cite_start]**Cloud Data Storage**: All student data, face embeddings, class timetables, and attendance logs are securely stored and managed in Google Firebase Firestore[cite: 159, 181, 212].
* [cite_start]**Timetable Integration**: The app automatically detects the current subject based on a timetable fetched from Firestore before marking attendance[cite: 159, 166].
* [cite_start]**Duplicate Prevention**: Checks to ensure a student cannot mark attendance more than once for the same class on the same day[cite: 173, 177].

## 🛠️ Technology Stack

* [cite_start]**Framework**: Flutter [cite: 17, 71]
* [cite_start]**Language**: Dart [cite: 152]
* [cite_start]**Database**: Google Firebase Firestore (NoSQL Cloud Database) [cite: 73, 159]
* **Machine Learning**:
    * [cite_start]**Face Detection**: Google ML Kit Face Detection [cite: 73, 242]
    * [cite_start]**Face Recognition**: TensorFlow Lite model (`facenet_model.tflite`) running on-device via the `tflite_flutter` package[cite: 73, 244].
* **Hardware Integration**:
    * [cite_start]`camera`: For accessing the device camera[cite: 73].
    * [cite_start]`nfc_manager`: For reading NFC tags[cite: 73].

## ⚙️ How It Works

The application has two primary workflows:

#### 1. Face Registration
1.  [cite_start]A user fills in their details (Username, Roll No, Class) on the registration form[cite: 217, 220].
2.  [cite_start]Upon submission, the camera screen opens to capture the user's face[cite: 210].
3.  [cite_start]Google's ML Kit first detects the presence and bounding box of a face in the camera view[cite: 283].
4.  [cite_start]The detected face is cropped, processed, and passed to the FaceNet TFLite model[cite: 261, 266].
5.  [cite_start]The model generates a 128-element list of numbers (a face embedding) that represents the face mathematically[cite: 266].
6.  [cite_start]The student's details and this face embedding are uploaded and stored in the `students` collection in Firebase Firestore[cite: 212].

#### 2. Attendance Marking
1.  [cite_start]The app actively listens for an NFC tag to be scanned[cite: 188].
2.  [cite_start]When a specific, pre-defined NFC tag ID is detected, the face comparison camera screen is triggered[cite: 188, 190].
3.  The app captures the user's face and generates a new face embedding using the same process as registration.
4.  [cite_start]This new embedding is compared against every embedding stored in the Firebase `students` collection[cite: 269].
5.  [cite_start]The comparison is done using both Euclidean distance and Cosine Similarity to find the closest match[cite: 257, 267, 274].
6.  [cite_start]If a match is found that meets a specific accuracy threshold, the app checks the `timetable` collection to identify the current subject[cite: 271, 166].
7.  [cite_start]Finally, a new attendance record is created in the `attendance` collection in Firestore, logging the student's name, roll number, subject, and timestamp[cite: 181].

## 🔧 Setup and Installation

To run this project locally, follow these steps:

1.  **Clone the Repository**
    ```bash
    git clone [https://github.com/Rxjkxmxl/attendance_test.git](https://github.com/Rxjkxmxl/attendance_test.git)
    cd attendance_test
    ```

2.  **Set Up Firebase**
    * Create a new project on the [Firebase Console](https://console.firebase.google.com/).
    * Enable **Firestore Database** in your Firebase project.
    * Register a new Android and/or iOS app in your Firebase project settings.
    * Follow the instructions to download the `google-services.json` file for Android and the `GoogleService-Info.plist` file for iOS.
    * [cite_start]Place the `google-services.json` file in the `android/app/` directory[cite: 1].
    * [cite_start]Place the `GoogleService-Info.plist` file in the `ios/Runner/` directory[cite: 7].
    * The project uses the FlutterFire CLI for configuration. Your specific keys will be populated in `lib/firebase_options.dart`. [cite_start]Make sure this file is correctly configured for your Firebase project[cite: 139].

3.  **Get Flutter Packages**
    ```bash
    flutter pub get
    ```

4.  **Run the App**
    ```bash
    flutter run
    ```

## ⚙️ Configuration

* **NFC Tag ID**: The app is currently hardcoded to respond to a specific NFC tag ID. [cite_start]You can change this value in `lib/main.dart`[cite: 188].
    ```dart
    // in _startNfcListening() method
    const String targetNfcId = '53:1E:97:86:12:00:01'; 
    ```
* **Firebase Rules**: For production use, ensure you have set up proper security rules in your Firestore database to protect user data.

## 🚀 Future Improvements

* **Admin Dashboard**: A web-based dashboard for admins to view attendance reports, manage students, and update the timetable.
* **Batch Registration**: Allow for registering multiple students at once.
* **Liveness Detection**: Add a liveness check during face capture to prevent spoofing with photos.
* **Offline Support**: Cache the timetable and student data to allow attendance marking even without an internet connection, syncing the data later.
