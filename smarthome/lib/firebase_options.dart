import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDaF6tO61ZXCJDtcW-UX7YJ-DNifVjCsCs',
    appId: '1:776433831510:web:0aad83ac3f30c97a96f5f7',
    messagingSenderId: '776433831510',
    projectId: 'smart-dc20a',
    authDomain: 'smart-dc20a.firebaseapp.com',
    databaseURL: 'https://smart-dc20a-default-rtdb.firebaseio.com',
    storageBucket: 'smart-dc20a.firebasestorage.app',
    measurementId: 'G-W5BZSDW48L',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCFoP--rXQEnQ1ib8HdpJZEBNAYKN8dy8E',
    appId: '1:776433831510:android:3b2a7188bb447c5e96f5f7',
    messagingSenderId: '776433831510',
    projectId: 'smart-dc20a',
    databaseURL: 'https://smart-dc20a-default-rtdb.firebaseio.com',
    storageBucket: 'smart-dc20a.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCfz8gU-KlniqAjEJfCHOXvk7aNxVxtVCo',
    appId: '1:776433831510:ios:b3c67f6ec49dd22696f5f7',
    messagingSenderId: '776433831510',
    projectId: 'smart-dc20a',
    databaseURL: 'https://smart-dc20a-default-rtdb.firebaseio.com',
    storageBucket: 'smart-dc20a.firebasestorage.app',
    iosBundleId: 'com.example.smarthome',
  );
}
