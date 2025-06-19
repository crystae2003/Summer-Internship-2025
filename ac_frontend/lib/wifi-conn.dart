import 'package:flutter/material.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'control.dart';

class WifiScanPage extends StatefulWidget {
  @override
  _WifiScanPageState createState() => _WifiScanPageState();
}

class _WifiScanPageState extends State<WifiScanPage> {
  List<WifiNetwork>? _networks;

  Future<void> scan() async {
    final list = await WiFiForIoTPlugin.loadWifiList();
    setState(() => _networks = list);
  }

  @override
  void initState() {
    super.initState();
    scan();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Select ESP32 Wi‑Fi')),
      body: ListView(
        children: (_networks ?? []).map((net) {
          return ListTile(
            title: Text(net.ssid ?? "Unknown"),
            subtitle: Text("Signal: ${net.level}"),
            onTap: () async {
              // assume password is known
              await WiFiForIoTPlugin.connect(
                net.ssid!,
                password: '12345678',
                security: NetworkSecurity.WPA,
                withInternet: false,
                joinOnce: true,
              );
              Navigator.push(context,
                MaterialPageRoute(builder: (_) => ControlPage()));
            },
          );
        }).toList(),
      ),
    );
  }
}
