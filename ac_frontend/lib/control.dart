import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() => runApp(const IRRemoteApp());

class IRRemoteApp extends StatelessWidget {
  const IRRemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESP32 IR Controller',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.transparent,
        ),
        cardTheme: CardTheme(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          color: Colors.white,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey.shade50,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF1565C0), width: 2),
          ),
          contentPadding: const EdgeInsets.all(16),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
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
  final _espIpController = TextEditingController(text: '192.168.29.230');
  final _commandController = TextEditingController();
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

Future<void> _apiCall(String endpoint, [Map<String, String>? params]) async {
  final ip = _espIpController.text.trim();
  try {
    final uri = Uri.http(ip, endpoint, params);
    print('DEBUG: Sending GET to $uri'); // DEBUG
    final res = await http.get(uri).timeout(const Duration(seconds: 5));
    print('DEBUG: Response [${res.statusCode}] - ${res.body}'); // DEBUG

    if (endpoint == 'list' && res.statusCode == 200) {
      final List<dynamic> list = json.decode(res.body);
      setState(() {
        commands = list.map((e) => e['name'] as String).toList();
        isConnected = true;
      });
      print('DEBUG: Command list updated (${commands.length} commands)'); // DEBUG
    } else {
      _showSnack(res.body, isError: res.statusCode != 200);
      if (endpoint == 'learn' || endpoint == 'delete' || endpoint == 'rename') {
        print('DEBUG: Refreshing command list after $endpoint'); // DEBUG
        await _refreshCommandList();
      }
    }
  } catch (e) {
    print('DEBUG: Exception during $endpoint call → $e'); // DEBUG
    if (endpoint == 'list') setState(() => isConnected = false);
    _showSnack('Connection error', isError: true);
  }
}

Future<void> _learnCommand() async {
  final cmd = _commandController.text.trim();
  if (cmd.isEmpty) {
    _showSnack('Please enter command name', isError: true);
    print('DEBUG: Command name was empty on Learn'); // DEBUG
    return;
  }
  print('DEBUG: Learning command → $cmd'); // DEBUG
  setState(() => isLoading = true);
  final prevText = _commandController.text;
  await _apiCall('learn', {'name': cmd});
  if (isConnected) _commandController.clear();
  else _commandController.text = prevText; // restore it if learning failed
  
  setState(() => isLoading = false);
}

Future<void> _sendCommand(String name) async {
  print('DEBUG: Sending command → $name'); // DEBUG
  await _apiCall('send', {'name': Uri.encodeComponent(name)});
}

Future<void> _refreshCommandList() async {
  print('DEBUG: Refreshing command list...'); // DEBUG
  setState(() => isLoading = true);
  await _apiCall('list');
  setState(() => isLoading = false);
}

Future<void> _deleteCommand(String name) async {
  print('DEBUG: Deleting command → $name'); // DEBUG
  await _apiCall('delete', {'name': Uri.encodeComponent(name)});
}

Future<void> _renameCommand(String oldName, String newName) async {
  print('DEBUG: Renaming command → $oldName → $newName'); // DEBUG
  await _apiCall('rename', {
    'old': Uri.encodeComponent(oldName),
    'new': Uri.encodeComponent(newName)
  });
}

Future<void> _renameDialog(String oldName) async {
  final ctrl = TextEditingController(text: oldName);
  final newName = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Rename Command', style: TextStyle(color: Colors.grey.shade800)),
      content: TextField(
        controller: ctrl,
        decoration: InputDecoration(
          labelText: 'New name',
          prefixIcon: Icon(Icons.edit, color: Theme.of(context).primaryColor),
        ),
        onSubmitted: (_) => Navigator.pop(context, ctrl.text.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, ctrl.text.trim()),
          child: const Text('Rename'),
        ),
      ],
    ),
  );


  if (newName != null && newName.trim().isNotEmpty && newName != oldName) {
    print('DEBUG: Renaming confirmed: $oldName → $newName'); // DEBUG
    await _renameCommand(oldName, newName.trim());
  } else {
    print('DEBUG: Rename cancelled or unchanged'); // DEBUG
  }
}

Future<void> _resetESP() async {
  final confirmed = await showDialog<bool>(
    context: context,
        builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.orange.shade600),
            const SizedBox(width: 8),
            const Text('Reset ESP32'),
          ],
        ),
        content: const Text('This will reset WiFi settings. You\'ll need to reconnect.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

  if (confirmed == true) {
    print('DEBUG: Resetting ESP32...'); // DEBUG
    await _apiCall('reset');
  } else {
    print('DEBUG: Reset cancelled'); // DEBUG
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
            const SizedBox(width: 12),
            Expanded(child: Text(msg)),
          ],
        ),
        backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('IR Controller', style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isConnected ? Colors.green.shade50 : Colors.red.shade50,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isConnected ? Colors.green.shade200 : Colors.red.shade200,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.circle,
                  color: isConnected ? Colors.green.shade600 : Colors.red.shade600,
                  size: 8,
                ),
                const SizedBox(width: 6),
                Text(
                  isConnected ? 'Online' : 'Offline',
                  style: TextStyle(
                    color: isConnected ? Colors.green.shade700 : Colors.red.shade700,
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
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Connection Card
              _buildCard(
                icon: Icons.wifi_rounded,
                title: 'Connection',
                child: Column(
                  children: [
                    TextField(
                      controller: _espIpController,
                      decoration: const InputDecoration(
                        labelText: 'ESP32 IP Address',
                        prefixIcon: Icon(Icons.router),
                        hintText: '192.168.1.100',
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: isLoading ? null : _refreshCommandList,
                        icon: isLoading 
                          ? const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded),
                        label: Text(isLoading ? 'Connecting...' : 'Test Connection'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Learn Command Card
              _buildCard(
                icon: Icons.add_circle_outline,
                title: 'Learn Command',
                child: Column(
                  children: [
                    TextField(
                      controller: _commandController,
                      decoration: const InputDecoration(
                        labelText: 'Command Name',
                        prefixIcon: Icon(Icons.label_outline),
                        hintText: 'e.g., TV Power, Volume Up',
                      ),
                      onSubmitted: (_) => _learnCommand(),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: isLoading ? null : _learnCommand,
                        icon: const Icon(Icons.school_outlined),
                        label: const Text('Learn'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade600,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Commands List
              _buildCard(
                icon: Icons.list_rounded,
                title: 'Commands (${commands.length})',
                child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : commands.isEmpty
                    ? _buildEmptyState()
                    : _buildCommandsList(),
              ),
              
              const SizedBox(height: 16),
              
              // Reset Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _resetESP,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Reset ESP32'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade600,
                    side: BorderSide(color: Colors.red.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard({required IconData icon, required String title, required Widget child}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).primaryColor, size: 24),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(Icons.settings_remote, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'No Commands Yet',
            style: TextStyle(fontSize: 18, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            'Learn your first IR command above',
            style: TextStyle(color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildCommandsList() {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: commands.length,
      separatorBuilder: (_, __) => Divider(color: Colors.grey.shade200, height: 1),
      itemBuilder: (_, i) {
        final cmd = commands[i];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.settings_remote,
              color: Theme.of(context).primaryColor,
              size: 20,
            ),
          ),
          title: Text(cmd, style: const TextStyle(fontWeight: FontWeight.w500)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildActionButton(Icons.edit, Colors.blue, () => _renameDialog(cmd)),
              _buildActionButton(Icons.delete, Colors.red, () => _deleteCommand(cmd)),
              _buildActionButton(Icons.send, Colors.green, () => _sendCommand(cmd)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionButton(IconData icon, Color color, VoidCallback onPressed) {
    return Container(
      margin: const EdgeInsets.only(left: 4),
      child: Material(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, color: color, size: 18),
          ),
        ),
      ),
    );
  }
}