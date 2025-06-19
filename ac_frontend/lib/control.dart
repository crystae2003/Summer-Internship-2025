import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class DynamicRemotePage extends StatefulWidget {
  @override
  _DynamicRemotePageState createState() => _DynamicRemotePageState();
}

class _DynamicRemotePageState extends State<DynamicRemotePage> {
  static const String espIp = '192.168.29.231';
  Map<String, dynamic> codes = {};
  bool _isResetting = false;

  @override
  void initState() {
    super.initState();
    _loadCodes();
  }

  Future<void> _loadCodes() async {
    final res = await http.get(Uri.parse('http://$espIp/list'));
    if (res.statusCode == 200) {
      setState(() => codes = jsonDecode(res.body));
    }
  }

  Future<void> _learn() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('New Button Name'),
        content: TextField(
          autofocus: true,
          decoration: InputDecoration(hintText: 'e.g., PowerOn'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
      ),
    );
    if (name != null && name.isNotEmpty) {
      final res = await http.get(Uri.parse('http://$espIp/learn?name=$name'));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.body)),
      );
      await _loadCodes();
    }
  }

  Future<void> _send(String name) async {
    final res = await http.get(Uri.parse('http://$espIp/send?name=$name'));
    final success = res.statusCode == 200;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? 'Sent $name' : 'Error: \${res.statusCode}'),
      ),
    );
  }

  Future<void> _resetWifi() async {
    setState(() { _isResetting = true; });
    try {
      final res = await http
        .get(Uri.parse('http://$espIp/reset'))
        .timeout(Duration(seconds: 3));
      final success = res.statusCode == 200;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? 'ESP32 rebooting to setup mode…'
              : 'Reset failed: \${res.statusCode}'),
        ),
      );
      if (success) Future.delayed(Duration(seconds: 2), _showNetworkDialog);
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ESP32 rebooting to setup mode…')),
      );
      Future.delayed(Duration(seconds: 2), _showNetworkDialog);
    } finally {
      setState(() { _isResetting = false; });
    }
  }

  void _showNetworkDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text('Connect to ESP32-Setup'),
        content: Text(
          'Open your Wi‑Fi settings, join the ESP32-Setup network, then reconfigure.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Dynamic IR Remote')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            ElevatedButton.icon(
              icon: Icon(Icons.add),
              label: Text('Learn New Button'),
              onPressed: _learn,
            ),
            SizedBox(height: 16),
            Expanded(
              child: codes.isEmpty
                  ? Center(child: Text('No buttons learned yet'))
                  : GridView.count(
                      crossAxisCount: 2,
                      children: codes.keys.map((name) => Padding(
                        padding: EdgeInsets.all(8),
                        child: ElevatedButton(
                          onPressed: () => _send(name),
                          child: Text(name),
                        ),
                      )).toList(),
                    ),
            ),
            SizedBox(height: 16),
            ElevatedButton.icon(
              icon: _isResetting
                ? SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)
                  )
                : Icon(Icons.refresh),
              label: Text(_isResetting ? 'Resetting Wi-Fi…' : 'Reset Wi-Fi'),
              onPressed: _isResetting ? null : _resetWifi,
            ),
          ],
        ),
      ),
    );
  }
}