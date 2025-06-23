import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() {
  runApp(const IRRemoteApp());
}

class IRRemoteApp extends StatelessWidget {
  const IRRemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESP32 IR Controller',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.light,
        ),
        cardTheme: const CardTheme(
          elevation: 2,
          margin: EdgeInsets.symmetric(vertical: 4),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey.shade50,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF6366F1), width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 2,
          ),
        ),
      ),
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
      TextEditingController(text: '192.168.29.230');
  final TextEditingController _commandController = TextEditingController();
  List<String> commands = [];
  bool isLoading = false;
  bool isConnected = false;

  @override
  void initState() {
    super.initState();
    _refreshCommandList();
  }

  @override
  void dispose() {
    _espIpController.dispose();
    _commandController.dispose();
    super.dispose();
  }

  Future<void> _learnCommand() async {
    final ip = _espIpController.text.trim();
    final cmd = _commandController.text.trim();
    if (cmd.isEmpty) {
      _showSnack('Please enter a command name.', isError: true);
      return;
    }
    
    setState(() => isLoading = true);
    try {
      final uri = Uri.http(ip, 'learn', {'name': cmd});
      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      _showSnack(res.body, isError: res.statusCode != 200);
      _commandController.clear();
      await _refreshCommandList();
    } catch (e) {
      _showSnack('Error learning command: $e', isError: true);
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _sendCommand(String name) async {

    final ip = _espIpController.text.trim();
    final cmd = Uri.encodeComponent(name.trim());
    try {
      final uri = Uri.http(ip, 'send', {'name': cmd});
      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      _showSnack(res.body, isError: res.statusCode != 200);
    } catch (e) {
      _showSnack('Error sending command: $e', isError: true);
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
        setState(() {
          commands = list.map((entry) => entry['name'] as String).toList();
          isConnected = true;
        });
      } else {
        setState(() => isConnected = false);
        _showSnack('Failed to load list: ${res.statusCode}', isError: true);
      }
    } catch (e) {
      setState(() => isConnected = false);
      debugPrint('Error loading list: $e');
      _showSnack('Error connecting to ESP32', isError: true);
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _deleteCommand(String name) async {
  final ip  = _espIpController.text.trim();
  final cmd = name.trim();

  
  final encodedName = Uri.encodeComponent(cmd);

  
  final rawUrl = 'http://$ip/delete?name=$encodedName';
  debugPrint('→ $rawUrl');

  try {
    final res = await http.get(Uri.parse(rawUrl))
                         .timeout(const Duration(seconds: 5));
    debugPrint('← ${res.statusCode}: ${res.body}');
    if (res.statusCode == 200) {
      _showSnack('Deleted "$name"');
      await _refreshCommandList();
    } else {
      _showSnack('Delete failed: ${res.statusCode}', isError: true);
    }
  } catch (e) {
    debugPrint('Error deleting: $e');
    _showSnack('Error deleting: $e', isError: true);
  }
}


  Future<void> _renameDialog(String oldName) async {
    final ctrl = TextEditingController(text: oldName);
    final newName = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Rename "$oldName"'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
              labelText: 'New command name',
              prefixIcon: Icon(Icons.edit),
            ),
            onSubmitted: (_) =>
                Navigator.of(dialogContext).pop(ctrl.text.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(ctrl.text.trim()),
              child: const Text('Rename'),
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
    final encodedOld = Uri.encodeComponent(oldName.trim());
    final encodedNew = Uri.encodeComponent(newName.trim());

    final uri = Uri.parse('http://$ip/rename?old=$encodedOld&new=$encodedNew');
    debugPrint('Rename URI → $uri');

    final res = await http.get(uri).timeout(const Duration(seconds: 5));
    debugPrint('◀ [rename] status=${res.statusCode} body=${res.body}');
    _showSnack(res.body, isError: res.statusCode != 200);
    await _refreshCommandList();
  } catch (e) {
    _showSnack('Error renaming: $e', isError: true);
  }
}

  Future<void> _resetESP() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reset ESP32'),
        content: const Text('Are you sure you want to reset the ESP32? This will restart the device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final ip = _espIpController.text.trim();
    try {
      final uri = Uri.http(ip, 'reset');
      await http.get(uri).timeout(const Duration(seconds: 5));
      _showSnack('ESP32 is resetting...');
    } catch (e) {
      _showSnack('Error resetting: $e', isError: true);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(msg)),
          ],
        ),
        backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: Duration(seconds: isError ? 4 : 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('ESP32 IR Controller'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        elevation: 0,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isConnected ? Icons.wifi : Icons.wifi_off,
                  color: isConnected ? Colors.green : Colors.red,
                  size: 20,
                ),
                const SizedBox(width: 4),
                Text(
                  isConnected ? 'Connected' : 'Disconnected',
                  style: TextStyle(
                    color: isConnected ? Colors.green : Colors.red,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshCommandList,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Connection Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.settings_ethernet,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Connection Settings',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _espIpController,
                        decoration: const InputDecoration(
                          labelText: 'ESP32 IP Address',
                          prefixIcon: Icon(Icons.computer),
                          hintText: '192.168.1.100',
                        ),
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: isLoading ? null : _refreshCommandList,
                          icon: isLoading 
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh),
                          label: Text(isLoading ? 'Connecting...' : 'Test Connection'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 20),
              
              // Learn Command Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.school,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Learn New Command',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _commandController,
                        decoration: const InputDecoration(
                          labelText: 'Command Name',
                          prefixIcon: Icon(Icons.label),
                          hintText: 'e.g., TV Power, Volume Up',
                        ),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _learnCommand(),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: isLoading ? null : _learnCommand,
                          icon: const Icon(Icons.add_circle),
                          label: const Text('Learn Command'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 20),
              
              // Commands List Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.list,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Saved Commands',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${commands.length}',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (isLoading)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: CircularProgressIndicator(),
                          ),
                        ),
                      if (!isLoading && commands.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(40),
                          child: Column(
                            children: [
                              Icon(
                                Icons.not_interested,
                                size: 64,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No commands found',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Learn your first IR command above',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (!isLoading && commands.isNotEmpty)
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: commands.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final cmd = commands[i];
                            return Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: Colors.transparent,
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    Icons.settings_remote ,
                                    size: 20,
                                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                                  ),
                                ),
                                title: Text(
                                  cmd,
                                  style: const TextStyle(fontWeight: FontWeight.w500),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit, size: 20),
                                      onPressed: () => _renameDialog(cmd),
                                      tooltip: 'Rename',
                                      style: IconButton.styleFrom(
                                        backgroundColor: Colors.blue.shade50,
                                        foregroundColor: Colors.blue.shade700,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      icon: const Icon(Icons.delete, size: 20),
                                      onPressed: () => _deleteCommand(cmd),
                                      tooltip: 'Delete',
                                      style: IconButton.styleFrom(
                                        backgroundColor: Colors.red.shade50,
                                        foregroundColor: Colors.red.shade700,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      icon: const Icon(Icons.send, size: 20),
                                      onPressed: () => _sendCommand(cmd),
                                      tooltip: 'Send',
                                      style: IconButton.styleFrom(
                                        backgroundColor: Colors.green.shade50,
                                        foregroundColor: Colors.green.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 20),
              
              // Reset Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _resetESP,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Reset ESP32'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}