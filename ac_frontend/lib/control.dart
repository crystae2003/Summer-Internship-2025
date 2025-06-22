import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';


// Flutter calls ESP32 over local Wi-Fi (port 80)
// ESP32 acts as a middleman:
//   - It receives commands from Flutter (HTTP GET)
//   - It sends/receives data to/from the FastAPI backend (HTTP POST/GET/PUT/DELETE)
//   - FastAPI backend talks to PostgreSQL database


void main() {
  runApp(const IRRemoteApp());
}

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
      TextEditingController(text: '192.168.29.231');
  final TextEditingController _commandController = TextEditingController();
  List<String> commands = [];
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _refreshCommandList(); //Auto-load saved commands on app launch
  }

  @override
  void dispose() {
    _espIpController.dispose();
    _commandController.dispose();// this is for controllers, which listens everytime and occupies the space, "dispose" helps in free the memory.
    super.dispose();
  }

  Future<void> _learnCommand() async {
    final ip = _espIpController.text.trim();
    final cmd = _commandController.text.trim();
    if (cmd.isEmpty) {
      _showSnack('Please enter a command name.');
      return;
    }
    try {
      final uri = Uri.http(ip, 'learn', {'name': cmd});// exactly behave like this -> http://<ESP32_IP>/learn?name=<cmd>
      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      _showSnack(res.body);
      _commandController.clear();
      await _refreshCommandList();
    } catch (e) {
      _showSnack('Error learning command: $e');
    }
  }

  Future<void> _sendCommand(String name) async {
    final ip = _espIpController.text.trim();
    final cmd = name.trim();
    try {
      final uri = Uri.http(ip, 'send', {'name': cmd});
      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      _showSnack(res.body);
    } catch (e) {
      _showSnack('Error sending command: $e');
    }
  }

  Future<void> _refreshCommandList() async {
    final ip = _espIpController.text.trim();
    setState(() => isLoading = true);
    try {
      final uri = Uri.http(ip, 'list');
      debugPrint('→ GET $uri');
      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      debugPrint('← ${res.statusCode}: ${res.body}');
      if (res.statusCode == 200) {
        final List<dynamic> list = json.decode(res.body);
        setState(() => commands = list
          .map((entry) => entry['name'] as String)
          .toList());
      }
      else {
        _showSnack('Failed to load list: ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('Error loading list: $e');
      _showSnack('Error loading list: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _deleteCommand(String name) async {
    final ip = _espIpController.text.trim();
    final uri = Uri.http(ip, 'delete', {'name': name});
    try {
      debugPrint('→ GET $uri');
      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      debugPrint('← ${res.statusCode}: ${res.body}');
      if (res.statusCode == 200) {
        _showSnack('Deleted "$name"');
        await _refreshCommandList();
      } else {
        _showSnack('Delete failed: ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('Error deleting: $e');
      _showSnack('Error deleting: $e');
    }
  }


  Future<void> _renameDialog(String oldName) async {
      final ctrl = TextEditingController(text: oldName);
      final newName = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: Text('Rename "$oldName"'),
            content: TextField(
              controller: ctrl,
              onSubmitted: (_) =>
                  Navigator.of(dialogContext).pop(ctrl.text.trim()),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(ctrl.text.trim()),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
      if (newName == null) return;
      final trimmedNew = newName.trim();
      final trimmedOld = oldName.trim();
      if (trimmedNew.isEmpty || trimmedNew == trimmedOld) return;
      await _renameCommand(trimmedOld, trimmedNew);
  }

  Future<void> _renameCommand(String oldName, String newName) async {
    final ip = _espIpController.text.trim();
    try {
      final uri = Uri.http(ip, 'rename', {'old': oldName, 'new': newName});
      debugPrint('Rename URI → $uri');
      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      debugPrint('◀ [rename] status=${res.statusCode} body=${res.body}');
      _showSnack(res.body);
      await _refreshCommandList();
    } catch (e) {
      _showSnack('Error renaming: $e');
    }
  }

  Future<void> _resetESP() async {
    final ip = _espIpController.text.trim();
    try {
      final uri = Uri.http(ip, 'reset');
      await http.get(uri).timeout(const Duration(seconds: 5));
      _showSnack('Resetting ESP32...');
    } catch (e) {
      _showSnack('Error resetting: $e');
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

    @override
    Widget build(BuildContext context) {
      return Scaffold(
        appBar: AppBar(title: const Text('ESP32 IR Controller')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _espIpController,
                decoration: const InputDecoration(labelText: 'ESP32 IP Address'),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _commandController,
                decoration: const InputDecoration(labelText: 'New Command Name'),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _learnCommand(),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _learnCommand,
                icon: const Icon(Icons.add_circle),
                label: const Text('Learn Command'),
              ),
              const Divider(height: 30),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Saved Commands:', style: TextStyle(fontSize: 16)),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _refreshCommandList,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (isLoading)
                const Center(child: CircularProgressIndicator()),
              if (!isLoading)
                Expanded(
                  child: commands.isEmpty
                      ? const Center(child: Text('No commands found'))
                      : ListView.builder(
                          itemCount: commands.length,
                          itemBuilder: (_, i) {
                            final cmd = commands[i];
                            return ListTile(
                              title: Text(cmd),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit),
                                    onPressed: () => _renameDialog(cmd),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete),
                                    onPressed: () => _deleteCommand(cmd),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.send),
                                    onPressed: () => _sendCommand(cmd),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: _resetESP,
                icon: const Icon(Icons.restart_alt),
                label: const Text('Reset ESP32'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              ),
            ],
          ),
        ),
      );
    }
  }
