import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';



class IRRemoteApp extends StatelessWidget {
  const IRRemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESP32 IR Controller',
      theme: ThemeData(primarySwatch: Colors.indigo),
      home: const IRHomePage(),
    );
  }
}

class IRHomePage extends StatefulWidget {
  const IRHomePage({super.key});

  @override
  State<IRHomePage> createState() => _IRHomePageState();
}

class _IRHomePageState extends State<IRHomePage> {
  final TextEditingController _espIpController =
      TextEditingController(text: "192.168.29.231");
  final TextEditingController _commandController = TextEditingController();
  List<String> commands = [];

  Future<void> _learnCommand() async {
    final ip = _espIpController.text;
    final cmd = _commandController.text.trim();
    if (cmd.isEmpty) return;

    final res = await http.get(Uri.parse("http://$ip/learn?name=$cmd"));
    _showSnack(res.body);
    _commandController.clear();
    await _getList();
  }

  Future<void> _sendCommand(String name) async {
    final ip = _espIpController.text;
    final res = await http.get(Uri.parse("http://$ip/send?name=$name"));
    _showSnack(res.body);
  }

  Future<void> _getList() async {
    final ip = _espIpController.text;
    final res = await http.get(Uri.parse("http://$ip/list"));
    if (res.statusCode == 200) {
      final data = json.decode(res.body);
      setState(() => commands = List<String>.from(data.keys));
    } else {
      _showSnack("Failed to load command list");
    }
  }

  Future<void> _resetESP() async {
    final ip = _espIpController.text;
    await http.get(Uri.parse("http://$ip/reset"));
    _showSnack("Resetting ESP32...");
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  @override
  void initState() {
    super.initState();
    _getList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("ESP32 IR Controller")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _espIpController,
              decoration: const InputDecoration(labelText: "ESP32 IP Address"),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _commandController,
              decoration: const InputDecoration(labelText: "New Command Name"),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _learnCommand,
              icon: const Icon(Icons.add_circle),
              label: const Text("Learn Command"),
            ),
            const Divider(height: 30),
            const Text("Saved Commands:", style: TextStyle(fontSize: 16)),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: commands.length,
                itemBuilder: (_, index) {
                  final cmd = commands[index];
                  return ListTile(
                    title: Text(cmd),
                    trailing: IconButton(
                      icon: const Icon(Icons.send),
                      onPressed: () => _sendCommand(cmd),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: _resetESP,
              icon: const Icon(Icons.restart_alt),
              label: const Text("Reset ESP32"),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            ),
          ],
        ),
      ),
    );
  }
}
