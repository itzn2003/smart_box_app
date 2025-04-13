import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:async';
import 'firebase_service.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PinRequestPage extends StatefulWidget {
  const PinRequestPage({Key? key}) : super(key: key);

  @override
  State<PinRequestPage> createState() => _PinRequestPageState();
}

class _PinRequestPageState extends State<PinRequestPage> {
  final FirebaseService _firebaseService = FirebaseService();
  final List<Map<String, dynamic>> _pendingRequests = [];
  bool _isLoading = true;
  bool _isProcessingRequest = false;
  StreamSubscription? _rtdbSubscription;

  @override
  void initState() {
    super.initState();
    _loadPendingRequestsFromRTDB();
  }

  @override
  void dispose() {
    _rtdbSubscription?.cancel();
    super.dispose();
  }

  // Load pending requests ONLY from Realtime Database
  void _loadPendingRequestsFromRTDB() {
    setState(() {
      _isLoading = true;
      _pendingRequests.clear();
    });

    _rtdbSubscription = _firebaseService.getPinRequestsFromRTDB().listen(
      (event) {
        if (!mounted) return;
        
        if (event.snapshot.exists) {
          final data = event.snapshot.value as Map<dynamic, dynamic>?;
          
          if (data != null) {
            final rtdbRequests = <Map<String, dynamic>>[];
            
            data.forEach((key, value) {
              if (value is Map && value['status'] == 'pending') {
                rtdbRequests.add({
                  'id': key,
                  ...Map<String, dynamic>.from(value as Map),
                });
              }
            });
            
            setState(() {
              _pendingRequests.clear();
              _pendingRequests.addAll(rtdbRequests);
              _isLoading = false;
            });
          } else {
            setState(() {
              _pendingRequests.clear();
              _isLoading = false;
            });
          }
        } else {
          setState(() {
            _pendingRequests.clear();
            _isLoading = false;
          });
        }
      },
      onError: (error) {
        print('Error loading requests from RTDB: $error');
        if (mounted) {
          setState(() {
            _pendingRequests.clear();
            _isLoading = false;
          });
          _showErrorSnackBar('Error loading requests: $error');
        }
      },
    );
  }

  // Simplified method to approve a request
  Future<void> _approveRequest(String requestId) async {
    if (_isProcessingRequest) return;
    
    setState(() {
      _isProcessingRequest = true;
    });
    
    try {
      // Generate a PIN
      final pin = _generatePin();
      print('Generated PIN: $pin for request: $requestId');
      
      // Show PIN dialog immediately with the generated PIN
      if (mounted) {
        setState(() {
          _isProcessingRequest = false;
        });
        
        _showPinDialog(pin, requestId);
        
        // Update databases in the background
        _updatePinInDatabase(requestId, pin);
      }
    } catch (e) {
      print('Error in _approveRequest: $e');
      if (mounted) {
        setState(() {
          _isProcessingRequest = false;
        });
        _showErrorSnackBar('Error: $e');
      }
    }
  }
  
  // Generate a random 4-digit PIN
  String _generatePin() {
    final random = Random();
    return List.generate(4, (_) => random.nextInt(10)).join();
  }
  
  // Update PIN in RTDB (and optionally Firestore for consistency)
  Future<void> _updatePinInDatabase(String requestId, String pin) async {
    try {
      print('Sending PIN to database: $requestId - $pin');
      
      // First update RTDB
      await _firebaseService.database.ref('pin_requests/$requestId').update({
        'pin': pin,
        'generatedAt': ServerValue.timestamp,
        'status': 'pending',
        'pinVerified': false
      });
      
      print('RTDB update successful');
      
      // Optionally update Firestore for consistency
      try {
        await _firebaseService.firestore.collection('pin_requests').doc(requestId).update({
          'pin': pin,
          'generatedAt': FieldValue.serverTimestamp(),
        });
        print('Firestore update successful');
      } catch (e) {
        print('Error updating Firestore (non-critical): $e');
        // Continue even if Firestore update fails
      }
    } catch (e) {
      print('Error updating PIN in database: $e');
      // Since we already showed the PIN to the user, we don't need to show an error
      // The dialog is already displaying the PIN
    }
  }
  
  // Simplified PIN dialog with direct PIN display
  void _showPinDialog(String pin, String requestId) {
    print('Opening PIN dialog with PIN: $pin');
    
    // Variable to track if PIN has been verified
    bool isPinVerified = false;
    StreamSubscription? verificationSubscription;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // Set up listener for verification
            verificationSubscription ??= _firebaseService.database
                .ref('pin_requests/$requestId')
                .onValue
                .listen((event) {
              if (!context.mounted) return;
              
              if (event.snapshot.exists) {
                final data = event.snapshot.value as Map<dynamic, dynamic>?;
                
                if (data != null && data['pinVerified'] == true) {
                  print('PIN verified in RTDB!');
                  setDialogState(() {
                    isPinVerified = true;
                  });
                }
              }
            });
            
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24.0),
              ),
              elevation: 0,
              backgroundColor: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.rectangle,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10.0,
                      offset: Offset(0.0, 10.0),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isPinVerified)
                      // Show PIN content
                      Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Theme.of(context).primaryColor.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.vpn_key,
                              size: 48,
                              color: Theme.of(context).primaryColor,
                            ),
                          ),
                          const SizedBox(height: 24),
                          
                          const Text(
                            'PIN Generated',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          const Text(
                            'The following PIN has been sent to the web application:',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                          const SizedBox(height: 24),
                          
                          // PIN Display - Show the PIN directly
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.shade200),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.grey.shade200,
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              pin, // Display the PIN directly
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 16,
                                color: Theme.of(context).primaryColor,
                              ),
                            ),
                          ),
                          
                          const SizedBox(height: 24),
                          
                          ElevatedButton(
                            onPressed: () {
                              verificationSubscription?.cancel();
                              Navigator.of(context).pop();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).primaryColor,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(double.infinity, 54),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: const Text('Close'),
                          ),
                        ],
                      )
                    else
                      // Show success state
                      Column(
                        children: [
                          Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              color: Colors.green[50],
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.check_circle,
                              color: Colors.green[500],
                              size: 64,
                            ),
                          ),
                          const SizedBox(height: 24),
                          
                          const Text(
                            'Authentication Successful!',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          const Text(
                            'The user has successfully entered the PIN',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                          const SizedBox(height: 24),
                          
                          ElevatedButton(
                            onPressed: () {
                              verificationSubscription?.cancel();
                              Navigator.of(context).pop();
                              _completeRequest(requestId);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(double.infinity, 54),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: const Text('Done'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            );
          }
        );
      },
    ).then((_) {
      verificationSubscription?.cancel();
    });
  }
  
  // Mark request as completed
  Future<void> _completeRequest(String requestId) async {
    try {
      print('Completing request: $requestId');
      
      // Update RTDB
      await _firebaseService.database.ref('pin_requests/$requestId').update({
        'status': 'completed',
        'completedAt': ServerValue.timestamp,
      });
      
      print('RTDB request completion successful');
      
      // Update Firestore for consistency
      try {
        await _firebaseService.firestore.collection('pin_requests').doc(requestId).update({
          'status': 'completed',
          'completedAt': FieldValue.serverTimestamp(),
        });
        print('Firestore request completion successful');
      } catch (e) {
        print('Error updating Firestore (non-critical): $e');
      }
      
      // Refresh the list after completing a request
      _loadPendingRequestsFromRTDB();
    } catch (e) {
      print('Error completing request: $e');
      _showErrorSnackBar('Error completing request: $e');
    }
  }
  
  // Deny a PIN request
  Future<void> _denyRequest(String requestId) async {
    try {
      setState(() {
        _isProcessingRequest = true;
      });
      
      await _completeRequest(requestId);
      
      if (mounted) {
        setState(() {
          _isProcessingRequest = false;
        });
        _showSuccessSnackBar('Request denied');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessingRequest = false;
        });
        _showErrorSnackBar('Error denying request: $e');
      }
    }
  }

  // Format timestamp from various sources
  String _formatTimestamp(dynamic timestamp) {
    DateTime? dateTime;
    
    try {
      // Handle different timestamp formats
      if (timestamp is int) {
        // RTDB timestamp (milliseconds since epoch)
        dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      } else if (timestamp is String) {
        try {
          dateTime = DateTime.parse(timestamp);
        } catch (e) {
          print('Error parsing timestamp string: $e');
        }
      } else if (timestamp is Map) {
        if (timestamp.containsKey('seconds')) {
          final seconds = timestamp['seconds'] as int;
          final nanoseconds = timestamp['nanoseconds'] as int? ?? 0;
          dateTime = DateTime.fromMillisecondsSinceEpoch(
            seconds * 1000 + (nanoseconds / 1000000).round(),
          );
        }
      }
    } catch (e) {
      print('Error processing timestamp: $e');
    }
    
    if (dateTime == null) {
      return 'Unknown time';
    }
    
    final now = DateTime.now();
    
    // Today
    if (dateTime.year == now.year && dateTime.month == now.month && dateTime.day == now.day) {
      return 'Today at ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
    
    // Yesterday
    final yesterday = now.subtract(const Duration(days: 1));
    if (dateTime.year == yesterday.year && dateTime.month == yesterday.month && dateTime.day == yesterday.day) {
      return 'Yesterday at ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
    
    // Other dates
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
  
  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Text(message),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('PIN Requests'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(24),
          ),
        ),
        actions: [
          // Add refresh button
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPendingRequestsFromRTDB,
            tooltip: 'Refresh requests',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _pendingRequests.isEmpty
              ? _buildEmptyState()
              : _buildRequestsList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.notifications_off_outlined,
              size: 64,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'No Pending Requests',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'You\'ll be notified when a new request arrives',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _loadPendingRequestsFromRTDB,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestsList() {
    return Stack(
      children: [
        ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _pendingRequests.length,
          itemBuilder: (context, index) {
            final request = _pendingRequests[index];
            
            final timestamp = request['timestamp'];
            final dateString = _formatTimestamp(timestamp);
            
            final userName = request['userName'] as String? ?? 'Unknown User';
            final phoneNumber = request['phoneNumber'] as String? ?? 'No Phone';

            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.shade200,
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.vpn_key_outlined,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'PIN Authentication Request',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                'From: $userName',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Content
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildDetailRow(Icons.person_outline, 'Name', userName),
                        const SizedBox(height: 12),
                        
                        _buildDetailRow(Icons.phone_outlined, 'Phone', phoneNumber),
                        const SizedBox(height: 12),
                        
                        _buildDetailRow(Icons.access_time_outlined, 'Time', dateString),
                        const SizedBox(height: 12),
                        
                        _buildDetailRow(
                          Icons.devices_outlined,
                          'Platform',
                          request['platform'] ?? 'Unknown',
                        ),
                        
                        const SizedBox(height: 20),
                        
                        // Request ID (truncated)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.tag,
                                size: 16,
                                color: Colors.grey.shade700,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'ID: ${request['id'].toString().substring(0, min(8, request['id'].toString().length))}...',
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 24),
                        
                        // Action buttons
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _isProcessingRequest
                                    ? null
                                    : () => _denyRequest(request['id']),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                  side: const BorderSide(color: Colors.red),
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text('Deny'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: ElevatedButton(
                                onPressed: _isProcessingRequest
                                    ? null
                                    : () => _approveRequest(request['id']),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Theme.of(context).primaryColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: _isProcessingRequest
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text('Approve & Generate PIN'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        
        // Processing overlay
        if (_isProcessingRequest)
          Container(
            color: Colors.black.withOpacity(0.3),
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          ),
      ],
    );
  }
  
  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: Colors.grey.shade600,
        ),
        const SizedBox(width: 12),
        Text(
          '$label:',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }
}