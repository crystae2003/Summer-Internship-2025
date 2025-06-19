// import 'package:flutter/material.dart';
// import 'package:flutter_blue/flutter_blue.dart';
// import 'dart:convert';

// class BleSetupPage extends StatefulWidget {
//   @override
//   _BleSetupPageState createState() => _BleSetupPageState();
// }

// class _BleSetupPageState extends State<BleSetupPage> {
//   FlutterBlue flutterBlue = FlutterBlue.instance;
//   BluetoothDevice? device;
//   List<BluetoothService> services = [];

//   final TextEditingController _ssidCtrl = TextEditingController();
//   final TextEditingController _passCtrl = TextEditingController();

//   final String svcUUID   = "12345678-1234-1234-1234-1234567890ab";
//   final String ssidUUID  = "12345678-1234-1234-1234-1234567890ac";
//   final String passUUID  = "12345678-1234-1234-1234-1234567890ad";
//   final String applyUUID = "12345678-1234-1234-1234-1234567890ae";

//   void scanAndConnect() {
//     flutterBlue.startScan(timeout: Duration(seconds: 5));
//     flutterBlue.scanResults.listen((results) {
//       for (var r in results) {
//         if (r.device.name == 'ESP32-Config') {
//           flutterBlue.stopScan();
//           device = r.device;
//           device!.connect().then((_) => discoverServices());
//           break;
//         }
//       }
//     });
//   }

//   void discoverServices() async {
//     services = await device!.discoverServices();
//     setState(() {});
//   }

//   Future<void> writeCharacteristic(String charUuid, List<int> value) async {
//     final c = services
//       .expand((s) => s.characteristics ?? [])
//       .firstWhere((c) => c.uuid.toString() == charUuid);
//     await c.write(value, withoutResponse: false);
//   }

//   void submitConfig() async {
//     final ssid = utf8.encode(_ssidCtrl.text);
//     final pass = utf8.encode(_passCtrl.text);
//     // 1) Write SSID
//     await writeCharacteristic(ssidUUID, ssid);
//     // 2) Write PASS
//     await writeCharacteristic(passUUID, pass);
//     // 3) Write Apply ('1')
//     await writeCharacteristic(applyUUID, utf8.encode('1'));
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(content: Text('Credentials sent — device will restart'))
//     );
//     device?.disconnect();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: Text('BLE Wi‑Fi Setup')),
//       body: Padding(
//         padding: EdgeInsets.all(16),
//         child: Column(children: [
//           ElevatedButton(
//             onPressed: scanAndConnect,
//             child: Text('Scan & Connect'),
//           ),
//           if (device != null && services.isNotEmpty) ...[
//             TextField(
//               controller: _ssidCtrl,
//               decoration: InputDecoration(labelText: 'SSID'),
//             ),
//             TextField(
//               controller: _passCtrl,
//               decoration: InputDecoration(labelText: 'Password'),
//               obscureText: true,
//             ),
//             SizedBox(height: 16),
//             ElevatedButton(
//               onPressed: submitConfig,
//               child: Text('Save & Restart'),
//             ),
//           ],
//         ]),
//       ),
//     );
//   }
// }
