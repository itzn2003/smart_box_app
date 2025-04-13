import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'loginPage.dart';
import 'homePage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyAygol25943UY4FZk-v06UCtyoNqSX1HM4",
      authDomain: "smart-box-9424f.firebaseapp.com",
      projectId: "smart-box-9424f",
      storageBucket: "smart-box-9424f.firebasestorage.app",
      messagingSenderId: "545984881312",
      appId: "1:545984881312:web:23f46426fa8567b7115fc5",
      measurementId: "G-WNV4BCZNPG",
      databaseURL: "https://smart-box-9424f-default-rtdb.europe-west1.firebasedatabase.app/"
    ),
  );
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Box',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Show loading indicator while connection state is in progress
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }
        
        // If the snapshot has user data, then the user is logged in
        
        if (snapshot.hasData && snapshot.data != null) {
          return const HomePage();
        }
        
        
        // Otherwise, the user is not logged in
        return const LoginPage();
      },
    );
  }
}