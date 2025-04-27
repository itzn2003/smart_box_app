import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:math';

class FirebaseService {
  // Authentication
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  
  FirebaseFirestore get firestore => _firestore;
  FirebaseDatabase get database => _database;
  
  // Get current user
  User? get currentUser => _auth.currentUser;
  
  // Get current user ID
  String? get currentUserId => _auth.currentUser?.uid;
  
  // Auth state changes stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Listen for PIN verification status changes in Realtime Database
  Stream<DatabaseEvent> getPinRequestsFromRTDB() {
    return _database.ref('pin_requests').onValue;
  }

  
  // Sign in with email and password
  Future<UserCredential> signInWithEmailAndPassword(String email, String password) async {
    try {
      // First ensure any previous sessions are cleared to avoid state conflicts
      if (_auth.currentUser != null) {
        await _auth.signOut();
      }
      
      // Basic authentication with error handling
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      // Add a slight delay to ensure Firebase auth state is fully processed
      await Future.delayed(const Duration(milliseconds: 500));
      
      return credential;
    } on FirebaseAuthException catch (e) {
      // Handle specific Firebase Auth errors
      print('Firebase Auth Error: ${e.code} - ${e.message}');
      rethrow; // Rethrow to be handled by the UI
    } catch (e) {
      // Handle unexpected errors
      print('Unexpected error during login: $e');
      rethrow;
    }
  }
  
  // Sign out
  Future<void> signOut() async {
    try {
      await _auth.signOut();
      // Add a slight delay to ensure Firebase auth state is fully processed
      await Future.delayed(const Duration(milliseconds: 300));
    } catch (e) {
      print('Error during sign out: $e');
      rethrow;
    }
  }
  
  // PIN Request Functions
  
  // Listen for ALL pending PIN requests
  Stream<QuerySnapshot> getPinRequests() {
    return _firestore
      .collection('pin_requests')
      .where('status', isEqualTo: 'pending')
      .snapshots();
  }
  
  // Generate a random 4-digit PIN
  String generatePin() {
    final random = Random();
    return List.generate(4, (_) => random.nextInt(10)).join();
  }
  
  // Modified sendPinToRequest method
  Future<void> sendPinToRequest(String requestId, String pin) async {
    try {
      print('Starting PIN request update for $requestId with PIN: $pin');
      
      try {
        print('Updating RTDB first...');
        // Create RTDB update with essential fields
        final rtdbUpdateData = {
          'pin': pin,
          'generatedAt': ServerValue.timestamp,
          'status': 'pending',
          'pinVerified': false
        };
        
        // Update RTDB
        await _database.ref('pin_requests/$requestId').update(rtdbUpdateData);
        print('RTDB update successful');
      } catch (rtdbError) {
        print('RTDB update failed: $rtdbError');      }
    } catch (e) {
      print('Error in sendPinToRequest: $e');
      rethrow;
    }
  }
  
  // Add the completeRequest method
  Future<void> completeRequest(String requestId) async {
    try {
      print('Completing request: $requestId');
      
      // Update Realtime Database
      bool rtdbSuccess = false;
      try {
        await _database.ref('pin_requests/$requestId').update({
          'status': 'completed',
          'completedAt': ServerValue.timestamp,
        });
        print('RTDB request completion successful');
        rtdbSuccess = true;
      } catch (e) {
        print('Error updating RTDB completion status: $e');
      }
        // If RTDB failed throw an error
        if (!rtdbSuccess) {
          throw Exception('Failed to complete request in both databases');
        }
    } catch (e) {
      print('Error in completeRequest: $e');
      // Rethrow to be handled by UI
      rethrow;
    }
  }
  
  // Listen for PIN verification status changes for a specific request
  Stream<DatabaseEvent> getPinRequestStatusFromRTDB(String requestId) {
    return _database.ref('pin_requests/$requestId').onValue;
  }
  
  Future<void> markPinVerified(String requestId) async {
    try {
      print('Marking PIN verified for request: $requestId');
      
      try {
        await _database.ref('pin_requests/$requestId').update({
          'pinVerified': true,
          'verifiedAt': ServerValue.timestamp,
        });
        print('RTDB pinVerified update completed');
      } catch (e) {
        print('Error updating RTDB verification status: $e');
      }
    } catch (e) {
      print('Error in markPinVerified: $e');
      rethrow;
    }
  }

  void syncPinVerificationStatus(String requestId) {
    print('Setting up verification sync for request: $requestId');
    
    // Listen to Realtime Database changes
    _database.ref('pin_requests/$requestId').onValue.listen((event) {
      if (event.snapshot.exists) {
        final data = event.snapshot.value as Map<dynamic, dynamic>?;
        if (data != null && data['pinVerified'] == true) {
          print('RTDB: PIN verified status detected for $requestId');
        }
      }
    }, onError: (error) {
      print('Error in RTDB listener: $error');
    });
  }
}