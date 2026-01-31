// lib/widgets/auto_barcode_scanner.dart
// Add this new file to your project

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import '../config/app_config.dart';

class AutoBarcodeScanner extends StatefulWidget {
  final Function(String imagePath, String barcode) onBarcodeDetected;
  final VoidCallback onCancel;

  const AutoBarcodeScanner({
    super.key,
    required this.onBarcodeDetected,
    required this.onCancel,
  });

  @override
  State<AutoBarcodeScanner> createState() => _AutoBarcodeScannerState();
}

class _AutoBarcodeScannerState extends State<AutoBarcodeScanner> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  final BarcodeScanner _barcodeScanner = BarcodeScanner();
  
  bool _isProcessing = false;
  bool _isCapturing = false;
  String? _detectedBarcode;
  bool _hasDetected = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _barcodeScanner.close();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      
      if (_cameras == null || _cameras!.isEmpty) {
        throw Exception('No cameras found');
      }

      // Use back camera
      final camera = _cameras!.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

      _cameraController = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid 
            ? ImageFormatGroup.nv21 
            : ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();

      if (mounted) {
        setState(() {});
        _startBarcodeDetection();
      }
    } catch (e) {
      AppConfig.debugPrint('❌ Camera initialization error: $e');
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Camera error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _startBarcodeDetection() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    _cameraController!.startImageStream((CameraImage image) {
      if (_isProcessing || _hasDetected) return;

      _isProcessing = true;
      _processCameraImage(image).then((_) {
        _isProcessing = false;
      });
    });
  }

  Future<void> _processCameraImage(CameraImage image) async {
    try {
      final inputImage = _convertCameraImage(image);
      if (inputImage == null) return;

      final barcodes = await _barcodeScanner.processImage(inputImage);

      if (barcodes.isNotEmpty && !_hasDetected && mounted) {
        final barcode = barcodes.first.rawValue;
        
        if (barcode != null && barcode.isNotEmpty) {
          _hasDetected = true;
          
          setState(() {
            _detectedBarcode = barcode;
          });

          AppConfig.debugPrint('✅ Barcode detected: $barcode');

          // Auto-capture photo
          await _capturePhoto(barcode);
        }
      }
    } catch (e) {
      AppConfig.debugPrint('❌ Barcode processing error: $e');
    }
  }

  InputImage? _convertCameraImage(CameraImage image) {
    try {
      final camera = _cameras!.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.back,
      );

      final sensorOrientation = camera.sensorOrientation;
      InputImageRotation? rotation;

      if (Platform.isIOS) {
        rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
      } else if (Platform.isAndroid) {
        var rotationCompensation = sensorOrientation;
        rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
      }

      if (rotation == null) return null;

      final format = Platform.isAndroid 
          ? InputImageFormat.nv21 
          : InputImageFormat.bgra8888;

      final plane = image.planes.first;

      return InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
    } catch (e) {
      AppConfig.debugPrint('❌ Image conversion error: $e');
      return null;
    }
  }

  Future<void> _capturePhoto(String barcode) async {
    if (_isCapturing || _cameraController == null) return;

    setState(() => _isCapturing = true);

    try {
      // Stop image stream
      await _cameraController!.stopImageStream();

      // Capture photo
      final XFile photo = await _cameraController!.takePicture();
      
      AppConfig.debugPrint('📸 Photo captured: ${photo.path}');

      // Return to parent with photo and barcode
      if (mounted) {
        widget.onBarcodeDetected(photo.path, barcode);
      }
    } catch (e) {
      AppConfig.debugPrint('❌ Photo capture error: $e');
      
      if (mounted) {
        setState(() {
          _isCapturing = false;
          _hasDetected = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to capture photo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text(
                'Initializing camera...',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera Preview
          Center(
            child: CameraPreview(_cameraController!),
          ),

          // Scanning overlay
          Center(
            child: Container(
              width: 300,
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(
                  color: _detectedBarcode != null ? Colors.orange : Colors.white,
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: _detectedBarcode != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle, color: Colors.orange, size: 48),
                          SizedBox(height: 8),
                          Text(
                            'Barcode Found!',
                            style: TextStyle(
                              color: Colors.orange,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            _detectedBarcode!,
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ],
                      ),
                    )
                  : null,
            ),
          ),

          // Instructions
          Positioned(
            top: 60,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              color: Colors.black.withOpacity(0.6),
              child: Text(
                _isCapturing 
                    ? 'Capturing photo...'
                    : _detectedBarcode != null
                        ? 'Barcode detected! Capturing...'
                        : 'Point camera at barcode',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),

          // Cancel button
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: ElevatedButton.icon(
                onPressed: _isCapturing ? null : widget.onCancel,
                icon: Icon(Icons.close),
                label: Text('Cancel'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                ),
              ),
            ),
          ),

          // Processing indicator
          if (_isCapturing)
            Container(
              color: Colors.black.withOpacity(0.7),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      'Capturing photo...',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}