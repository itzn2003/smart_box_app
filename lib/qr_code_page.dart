import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'firebase_service.dart';

class QRCodePage extends StatefulWidget {
  const QRCodePage({Key? key}) : super(key: key);

  @override
  State<QRCodePage> createState() => _QRCodePageState();
}

class _QRCodePageState extends State<QRCodePage> {
  final FirebaseService _firebaseService = FirebaseService();
  final GlobalKey _qrKey = GlobalKey();
  bool _isLoading = false;
  
  // Generate the QR code data with user ID
  String get _qrData {
    // Using the user's ID to create a unique link
    final userId = _firebaseService.currentUserId;
    // Replace with your actual web app URL
    return 'https://smart-box-9424f.web.app/auth?userId=$userId';
  }
  
  // Capture QR code as image
  Future<Uint8List?> _captureQrCode() async {
    try {
      // Find the QR code rendering
      final RenderRepaintBoundary boundary = 
          _qrKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      
      // Capture as image
      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      
      if (byteData != null) {
        return byteData.buffer.asUint8List();
      }
      return null;
    } catch (e) {
      debugPrint('Error capturing QR code: $e');
      return null;
    }
  }
  
  // Save QR code and share
  Future<void> _shareQrCode() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      final imageBytes = await _captureQrCode();
      
      if (imageBytes != null) {
        // Get temporary directory to save image
        final directory = await getTemporaryDirectory();
        final imagePath = '${directory.path}/smart_box_qr.png';
        final imageFile = File(imagePath);
        
        // Save image to file
        await imageFile.writeAsBytes(imageBytes);
        
        // Share the image
        await Share.shareXFiles(
          [XFile(imagePath)],
          text: 'My Smart Box QR Code',
        );
      } else {
        _showErrorSnackBar('Failed to generate QR image');
      }
    } catch (e) {
      _showErrorSnackBar('Error sharing QR code: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  
  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your QR Code'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      Icon(
                        Icons.qr_code_scanner,
                        size: 64,
                        color: Theme.of(context).primaryColor,
                      ),
                      const SizedBox(height: 16),
                      
                      Text(
                        'Your Smart Box QR Code',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                      const SizedBox(height: 12),
                      
                      const Text(
                        'Show this QR code to the delivery person for authentication',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 32),
                      
                      // QR Code (wrapped in RepaintBoundary for image capture)
                      RepaintBoundary(
                        key: _qrKey,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: QrImageView(
                            data: _qrData,
                            version: QrVersions.auto,
                            size: 240,
                            backgroundColor: Colors.white,
                            errorStateBuilder: (context, error) {
                              return const Center(
                                child: Text(
                                  'Error generating QR code',
                                  style: TextStyle(color: Colors.red),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      
                      // User ID indicator
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.person,
                              size: 16,
                              color: Colors.grey.shade700,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'User ID: ${_firebaseService.currentUserId?.substring(0, 8) ?? 'Unknown'}',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              
              // Share button
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _shareQrCode,
                  icon: const Icon(Icons.share),
                  label: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Share QR Code'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              // QR usage info
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade100),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.blue.shade700,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'How it works',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '1. Show this QR code to the delivery person\n'
                      '2. They scan it with their scanner\n'
                      '3. You\'ll receive a PIN request on this device\n'
                      '4. Approve the request to complete authentication',
                      style: TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
