import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'dart:convert';

class IRControllerApp extends StatelessWidget {
  const IRControllerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IR MQTT Controller',
      home: const IRHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class IRHomePage extends StatefulWidget {
  const IRHomePage({super.key});
  @override
  State<IRHomePage> createState() => _IRHomePageState();
}

class _IRHomePageState extends State<IRHomePage> {
  late final MqttServerClient _client;
  String _status = 'Connecting…';
  List<String> _commandNames = [];
  Map<String, List<int>> _commandMap = {};
 

  @override
  void initState() {
    super.initState();
    _setupMqtt();
    _connect();
  }

  void _setupMqtt() {
  _client = MqttServerClient('192.168.29.142', 'flutterClient')
    ..port = 1883
    ..logging(on: false)
    ..keepAlivePeriod = 20
    ..connectionMessage = MqttConnectMessage()
        .withClientIdentifier('flutterClient')
        .authenticateAs('hema', '@hema.')
        .startClean();

  _client.onConnected    = _onConnected;
  _client.onDisconnected = _onDisconnected;
}


  Future<void> _connect() async {
    try {
      await _client.connect();
    } catch (e) {
      setState(() => _status = 'MQTT connect failed: $e');
    }
  }

  void _onConnected() {
    _client.updates?.listen(_onMessage);
    setState(() => _status = 'Connected');
    _client.subscribe('home/ac/status', MqttQos.atLeastOnce);
    _client.subscribe('home/ac/available_cmds', MqttQos.atLeastOnce);
    _requestList();
    
  }

  void _onDisconnected() {
    setState(() {
      _status = 'Disconnected';
      _commandNames = [];
      _commandMap.clear();
    });
  }

void _onMessage(List<MqttReceivedMessage<MqttMessage>>? events) {
  if (events == null || events.isEmpty) return;

  final rec = events[0];
  final MqttPublishMessage message = rec.payload as MqttPublishMessage;
  final payloadBytes = message.payload.message;

  final payloadString = MqttPublishPayload.bytesToStringAsString(payloadBytes);
  debugPrint('[MQTT] Received on ${rec.topic}: $payloadString');

  if (rec.topic == 'home/ac/status') {
    setState(() => _status = payloadString);
    if (payloadString.startsWith('Learned')) {
      Future.delayed(const Duration(milliseconds: 500), _requestList);
    }
  } else if (rec.topic == 'home/ac/available_cmds') {
      try {
        final decoded = jsonDecode(payloadString);
        if (decoded is Map<String, dynamic>) {
          setState(() {
            _commandNames = decoded.keys.toList();  // ✅ Correct list used for rendering
            _commandMap = decoded.map((k, v) => MapEntry(k, List<int>.from(v)));
          });
        }
      } catch (e) {
        debugPrint('[ERROR] Failed to parse available_cmds: $e');
      }
    }

}


  void _requestList() {
    final b = MqttClientPayloadBuilder()..addString('');
    _client.publishMessage('home/ac/list', MqttQos.atLeastOnce, b.payload!);
  }

  void _sendCommand(String name) {
    final b = MqttClientPayloadBuilder()
      ..addString(jsonEncode({'name': name}));
    _client.publishMessage('home/ac/send', MqttQos.atLeastOnce, b.payload!);
  }

  void _sendEraseAll() {
    final b = MqttClientPayloadBuilder()..addString('');
    _client.publishMessage('home/ac/erase_all', MqttQos.atLeastOnce, b.payload!);
  }

  void _resetWiFi() {
    final b = MqttClientPayloadBuilder()..addString('reset');
    _client.publishMessage('home/ac/reset_wifi', MqttQos.atLeastOnce, b.payload!);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reset command sent to ESP32')),
    );
  }
  void _showEditDialog(String oldName) {
  final controller = TextEditingController(text: oldName);

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Rename Command'),
      content: TextField(controller: controller),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final newName = controller.text.trim();
            Navigator.pop(ctx);
            if (newName.isNotEmpty && newName != oldName) {
              _renameCommand(oldName, newName);
            }
          },
          child: const Text('Rename'),
        )
      ],
    ),
  );
}

void _renameCommand(String oldName, String newName) {
  final payload = jsonEncode({
    "old_name": oldName,
    "new_name": newName
  });
  debugPrint('[MQTT] Sent rename payload: $payload'); 


  final builder = MqttClientPayloadBuilder()..addString(payload);
  _client.publishMessage('home/ac/rename', MqttQos.atLeastOnce, builder.payload!);
}


void _confirmDelete(String name) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete Command'),
      content: Text('Are you sure you want to delete "$name"?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(ctx);
            _deleteCommand(name);
          },
          child: const Text('Delete'),
        )
      ],
    ),
  );
}

void _deleteCommand(String name) {
  final b = MqttClientPayloadBuilder()
    ..addString(jsonEncode({"name": name}));
  _client.publishMessage('home/ac/delete_one', MqttQos.atLeastOnce, b.payload!);
}


  void _showTimingsDialog(String name) {
    final timings = _commandMap[name];
    if (timings == null || timings.isEmpty) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Raw Timings for "$name"'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(timings.join(', ')),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('IR MQTT Controller'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _requestList),
          IconButton(icon: const Icon(Icons.delete), onPressed: _sendEraseAll),
          IconButton(icon: const Icon(Icons.settings_backup_restore), onPressed: _resetWiFi),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Colors.grey[200],
            padding: const EdgeInsets.all(12),
            child: Text('Status: $_status'),
          ),
          Expanded(
            child: _commandNames.isEmpty
                ? const Center(child: Text('No commands learned yet.'))
                :ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _commandNames.length,
                  itemBuilder: (ctx, i) {
                    final cmd = _commandNames[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Card(
                        child: ListTile(
                          title: Text(cmd.toUpperCase()),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: () => _showEditDialog(cmd),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete),
                                onPressed: () => _confirmDelete(cmd),
                              ),
                            ],
                          ),
                          onTap: () => _sendCommand(cmd),
                          onLongPress: () => _showTimingsDialog(cmd),
                        ),
                      ),
                    );
                  },
                ),

          ),
        ],
      ),
    );
  }
}
