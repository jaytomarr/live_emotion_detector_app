import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:live_emotion_detector_app/main.dart';
import 'package:tflite_flutter/tflite_flutter.dart' as tfl;

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  CameraImage? cameraImage;
  CameraController? cameraController;
  String prediction = 'No emotion detected';
  String confidence = '';
  bool isModelLoaded = false;
  bool isCameraInitialized = false;
  bool isProcessing = false;
  bool isCameraOn = true;
  bool isDetectionActive = true;
  tfl.Interpreter? interpreter;
  List<String> labels = ['Happy', 'Angry', 'Sad'];
  DateTime? lastProcessTime;

  @override
  void initState() {
    super.initState();
    loadModel();
    loadCamera();
  }

  @override
  void dispose() {
    cameraController?.dispose();
    interpreter?.close();
    super.dispose();
  }

  loadModel() async {
    try {
      interpreter = await tfl.Interpreter.fromAsset('assets/model.tflite');

      // Print model input/output details for debugging
      var inputDetails = interpreter!.getInputTensors();
      var outputDetails = interpreter!.getOutputTensors();

      print(
        'Model input details: ${inputDetails.map((t) => t.shape).toList()}',
      );
      print(
        'Model output details: ${outputDetails.map((t) => t.shape).toList()}',
      );

      setState(() {
        isModelLoaded = true;
      });
    } catch (e) {
      print('Error loading model: $e');
      setState(() {
        prediction = 'Error loading model';
      });
    }
  }

  loadCamera() async {
    try {
      cameraController = CameraController(cameras![0], ResolutionPreset.high);
      await cameraController!.initialize();

      if (!mounted) return;

      setState(() {
        isCameraInitialized = true;
      });

      cameraController!.startImageStream((imageStream) {
        if (!isProcessing && isModelLoaded && isDetectionActive) {
          // Limit processing to every 500ms for better performance
          final now = DateTime.now();
          if (lastProcessTime == null ||
              now.difference(lastProcessTime!).inMilliseconds > 500) {
            cameraImage = imageStream;
            lastProcessTime = now;
            runModel();
          }
        }
      });
    } catch (e) {
      print('Error initializing camera: $e');
      setState(() {
        prediction = 'Error initializing camera';
      });
    }
  }

  runModel() async {
    if (cameraImage == null ||
        interpreter == null ||
        isProcessing ||
        !isDetectionActive)
      return;

    setState(() {
      isProcessing = true;
    });

    try {
      // Convert camera image to proper format for the model
      final input = _preprocessImage(cameraImage!);

      // Debug: Print input shape
      print(
        'Input shape: [${input.length}, ${input[0].length}, ${input[0][0].length}, ${input[0][0][0].length}]',
      );

      // Prepare output tensor
      var output = List.filled(1 * 3, 0.0).reshape([1, 3]);

      // Run inference
      interpreter!.run(input, output);

      // Get predictions
      List<double> predictions = List<double>.from(output[0]);

      // Find the emotion with highest confidence
      if (predictions.isNotEmpty) {
        int maxIndex = predictions.indexOf(
          predictions.reduce((a, b) => a > b ? a : b),
        );
        double maxConfidence = predictions[maxIndex];

        // Only update if confidence is above threshold
        if (maxConfidence > 0.1) {
          if (mounted) {
            setState(() {
              prediction = labels[maxIndex];
              confidence = '${(maxConfidence * 100).toStringAsFixed(1)}%';
            });
          }
        }
      }
    } catch (e) {
      print('Error running model: $e');
      if (mounted) {
        setState(() {
          prediction = 'Error in prediction';
          confidence = '';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          isProcessing = false;
        });
      }
    }
  }

  // Camera control functions
  void toggleCamera() {
    setState(() {
      isCameraOn = !isCameraOn;
    });

    if (isCameraOn) {
      loadCamera();
    } else {
      cameraController?.dispose();
      setState(() {
        isCameraInitialized = false;
        prediction = 'Camera turned off';
        confidence = '';
      });
    }
  }

  void toggleDetection() {
    setState(() {
      isDetectionActive = !isDetectionActive;
    });

    if (!isDetectionActive) {
      setState(() {
        prediction = 'Detection paused';
        confidence = '';
      });
    }
  }

  List<List<List<List<double>>>> _preprocessImage(CameraImage cameraImage) {
    // Preprocessing for RGB image at 224x224 resolution
    final int width = cameraImage.width;
    final int height = cameraImage.height;
    final int targetSize = 224;

    // Create input tensor for 224x224 RGB image
    // Shape: [batch_size, height, width, channels] = [1, 224, 224, 3]
    List<List<List<List<double>>>> input = List.generate(
      1,
      (_) => List.generate(
        targetSize,
        (_) => List.generate(targetSize, (_) => List.generate(3, (_) => 0.0)),
      ),
    );

    // Convert YUV420 to RGB and resize to 224x224
    for (int y = 0; y < targetSize; y++) {
      for (int x = 0; x < targetSize; x++) {
        // Map target coordinates to source coordinates
        int sourceX = (x * width) ~/ targetSize;
        int sourceY = (y * height) ~/ targetSize;

        // Clamp to valid range
        sourceX = sourceX.clamp(0, width - 1);
        sourceY = sourceY.clamp(0, height - 1);

        // Get YUV values
        int yIndex = sourceY * cameraImage.planes[0].bytesPerRow + sourceX;
        int uIndex =
            (sourceY ~/ 2) * cameraImage.planes[1].bytesPerRow + (sourceX ~/ 2);
        int vIndex =
            (sourceY ~/ 2) * cameraImage.planes[2].bytesPerRow + (sourceX ~/ 2);

        if (yIndex < cameraImage.planes[0].bytes.length &&
            uIndex < cameraImage.planes[1].bytes.length &&
            vIndex < cameraImage.planes[2].bytes.length) {
          int yValue = cameraImage.planes[0].bytes[yIndex];
          int uValue = cameraImage.planes[1].bytes[uIndex];
          int vValue = cameraImage.planes[2].bytes[vIndex];

          // Convert YUV to RGB
          int r = (yValue + (1.402 * (vValue - 128))).round().clamp(0, 255);
          int g =
              (yValue -
                      (0.344136 * (uValue - 128)) -
                      (0.714136 * (vValue - 128)))
                  .round()
                  .clamp(0, 255);
          int b = (yValue + (1.772 * (uValue - 128))).round().clamp(0, 255);

          // Normalize to 0-1 range and assign to RGB channels
          input[0][y][x][0] = r / 255.0; // Red
          input[0][y][x][1] = g / 255.0; // Green
          input[0][y][x][2] = b / 255.0; // Blue
        }
      }
    }

    return input;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Live Emotion Detection'),
        backgroundColor: Theme.of(context).primaryColor,
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Camera Preview Section
          Expanded(
            flex: 3,
            child: Container(
              margin: EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 10,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: !isCameraOn
                    ? Container(
                        color: Colors.black,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.videocam_off,
                                size: 64,
                                color: Colors.white54,
                              ),
                              SizedBox(height: 16),
                              Text(
                                'Camera is turned off',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Tap "Turn On Camera" to start',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : !isCameraInitialized
                    ? Container(
                        color: Colors.black,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(color: Colors.white),
                              SizedBox(height: 16),
                              Text(
                                'Initializing Camera...',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : AspectRatio(
                        aspectRatio: cameraController!.value.aspectRatio,
                        child: CameraPreview(cameraController!),
                      ),
              ),
            ),
          ),

          // Emotion Display Section
          Expanded(
            flex: 2,
            child: Container(
              margin: EdgeInsets.symmetric(horizontal: 16),
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 5,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!isModelLoaded)
                    Column(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text(
                          'Loading AI Model...',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    )
                  else ...[
                    // Emotion Icon
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: _getEmotionColor(prediction),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _getEmotionColor(
                              prediction,
                            ).withValues(alpha: 0.3),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Icon(
                        _getEmotionIcon(prediction),
                        size: 40,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 16),

                    // Emotion Text
                    Text(
                      prediction,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: _getEmotionColor(prediction),
                      ),
                    ),

                    // Confidence Score
                    if (confidence.isNotEmpty)
                      Text(
                        'Confidence: $confidence',
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),

                    // Status Indicator
                    SizedBox(height: 8),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isCameraOn
                            ? (isDetectionActive
                                  ? Colors.green.withValues(alpha: 0.1)
                                  : Colors.orange.withValues(alpha: 0.1))
                            : Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: isCameraOn
                              ? (isDetectionActive
                                    ? Colors.green
                                    : Colors.orange)
                              : Colors.red,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        isCameraOn
                            ? (isDetectionActive
                                  ? '🔴 Live Detection'
                                  : '⏸️ Detection Paused')
                            : '📷 Camera Off',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isCameraOn
                              ? (isDetectionActive
                                    ? Colors.green
                                    : Colors.orange)
                              : Colors.red,
                        ),
                      ),
                    ),

                    SizedBox(height: 20),

                    // Control Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Camera Toggle Button
                        ElevatedButton.icon(
                          onPressed: toggleCamera,
                          icon: Icon(
                            isCameraOn ? Icons.videocam_off : Icons.videocam,
                          ),
                          label: Text(
                            isCameraOn ? 'Turn Off Camera' : 'Turn On Camera',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isCameraOn
                                ? Colors.red
                                : Colors.green,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ),

                        // Detection Toggle Button
                        ElevatedButton.icon(
                          onPressed: toggleDetection,
                          icon: Icon(
                            isDetectionActive ? Icons.pause : Icons.play_arrow,
                          ),
                          label: Text(
                            isDetectionActive
                                ? 'Pause Detection'
                                : 'Start Detection',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _getEmotionColor(prediction),
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getEmotionColor(String emotion) {
    switch (emotion.toLowerCase()) {
      case 'happy':
        return Colors.green;
      case 'angry':
        return Colors.red;
      case 'sad':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  IconData _getEmotionIcon(String emotion) {
    switch (emotion.toLowerCase()) {
      case 'happy':
        return Icons.sentiment_very_satisfied;
      case 'angry':
        return Icons.sentiment_very_dissatisfied;
      case 'sad':
        return Icons.sentiment_dissatisfied;
      default:
        return Icons.sentiment_neutral;
    }
  }
}
