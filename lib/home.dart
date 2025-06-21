import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:live_emotion_detector_app/main.dart';
// import 'package:tflite/tflite.dart';
import 'package:tflite_flutter/tflite_flutter.dart' as tfl;

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  _HomeState createState() => _HomeState();
}

class _HomeState extends State<Home> {
  CameraImage? cameraImage;
  CameraController? cameraController;
  String prediction = '';
  double result = 0.0;

  @override
  void initState() {
    super.initState();
    loadCamera();
    // loadmodel();
  }

  loadCamera() {
    cameraController = CameraController(cameras![0], ResolutionPreset.high);
    cameraController!.initialize().then((value) {
      if (!mounted) {
        return;
      } else {
        setState(() {
          cameraController!.startImageStream((imageStream) {
            cameraImage = imageStream;
            runModel();
          });
        });
      }
    });
  }

  runModel() async {
    final interpreter = await tfl.Interpreter.fromAsset('assets/model.tflite');
    final inputs = cameraImage!.planes.map((plane) {
      return plane.bytes;
    }).toList();

    var output = List.filled(1, 0).reshape([1, 1]);
    interpreter.run(inputs, output);
    result = output[0][0];
    prediction = result.toString();
    print(output);
    setState(() {});
  }

  prints() {
    print(result);
    print(prediction);
  }

  // runModel() async {
  //   if (cameraImage != null) {
  //     var predictions = await Tflite.runModelOnFrame(
  //       bytesList: cameraImage!.planes.map((plane) {
  //         return plane.bytes;
  //       }).toList(),
  //       imageHeight: cameraImage!.height,
  //       imageWidth: cameraImage!.width,
  //       imageMean: 127.5,
  //       imageStd: 127.5,
  //       rotation: 90,
  //       numResults: 2,
  //       threshold: 0.1,
  //       asynch: true,
  //     );
  //     predictions!.forEach((element) {
  //       setState(() {
  //         output = element['label'];
  //       });
  //     });
  //   }
  // }

  // loadmodel() async {
  //   await Tflite.loadModel(
  //     model: "assets/model.tflite",
  //     labels: "assets/labels.txt",
  //   );
  // }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Live Emotion Detection App'),
        backgroundColor: Theme.of(context).primaryColor,
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(20),
            child: Container(
              height: MediaQuery.of(context).size.height * 0.7,
              width: MediaQuery.of(context).size.width,
              child: !cameraController!.value.isInitialized
                  ? Container(color: Colors.black)
                  : AspectRatio(
                      aspectRatio: cameraController!.value.aspectRatio,
                      child: CameraPreview(cameraController!),
                    ),
            ),
          ),
          Text(
            prediction,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 32),
          ),
          ElevatedButton(onPressed: prints(), child: Text("Get")),
        ],
      ),
    );
  }
}
