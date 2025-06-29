import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'dart:convert';

void main() => runApp(const IRApp());

class IRApp extends StatelessWidget {
  const IRApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'IR MQTT Control',
        home: const IRHome(),
        debugShowCheckedModeBanner: false,
      );
}

class IRHome extends StatefulWidget {
  const IRHome({super.key});
  @override
  State<IRHome> createState() => _IRHomeState();
}

class _IRHomeState extends State<IRHome> {
  late final MqttServerClient _client;
  Map<String, dynamic> _commands = {};

  @override
  void initState() {
    super.initState();
    _client = MqttServerClient('192.168.29.142', 'flutterClient')
      ..port = 1883
      ..logging(on: false)
      ..connectionMessage = MqttConnectMessage()
          .withClientIdentifier('flutterClient')
          .authenticateAs('hema', '@hema.')
          .startClean();
    _client.onConnected = _onConnected;
    _client.onDisconnected = () => setState(() => _commands.clear());
  
    _connect();
  }

  Future<void> _connect() async {
    try {
      await _client.connect();
    } catch (_) {}
  }

  void _onConnected() {
    // Subscribe to status and commands topics
    _client.subscribe('home/ac/status', MqttQos.atLeastOnce);
    _client.subscribe('home/ac/available_cmds', MqttQos.atLeastOnce);

    _client.updates?.listen((events) {
      final rec   = events[0];
      final topic = rec.topic;
      final msg   = rec.payload as MqttPublishMessage;
      final raw   = MqttPublishPayload.bytesToStringAsString(msg.payload.message);

      if (topic == 'home/ac/available_cmds') {
        try {
          var decoded = jsonDecode(raw);
          if (decoded is String) decoded = jsonDecode(decoded);
          setState(() => _commands = decoded as Map<String, dynamic>);
        } catch (_) {
          setState(() => _commands = {});
        }
      } else if (topic == 'home/ac/status') {
        // refresh list after delete/rename/learn
        if (raw.startsWith('Deleted') ||
            raw.startsWith('Renamed') ||
            raw.startsWith('Learned')) {
          Future.delayed(const Duration(milliseconds: 500), _requestList);
        }
      }
    });

    // initial list fetch
    _requestList();
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> events) {}

  void _requestList() {
    final b = MqttClientPayloadBuilder()..addString('');
    _client.publishMessage('home/ac/list', MqttQos.atLeastOnce, b.payload!);
  }

  void _send(String name) {
    final b = MqttClientPayloadBuilder()..addString(jsonEncode({'name': name}));
    _client.publishMessage('home/ac/send', MqttQos.atLeastOnce, b.payload!);
  }

  void _delete(String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Command'),
        content: Text('Are you sure you want to delete "$name"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () {
            final b = MqttClientPayloadBuilder()..addString(jsonEncode({'name': name}));
            _client.publishMessage('home/ac/delete', MqttQos.atLeastOnce, b.payload!);
            Navigator.pop(ctx);
          }, child: const Text('Delete')),
        ],
      ),
    );
  }

  void _rename(String oldName) async {
    final ctrl = TextEditingController(text: oldName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Command'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'New name'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () {
            final text = ctrl.text.trim();
            if (text.isNotEmpty && text != oldName) {
              Navigator.pop(ctx, text);
            }
          }, child: const Text('Rename')),
        ],
      ),
    );
    if (newName != null) {
      final b = MqttClientPayloadBuilder()
        ..addString(jsonEncode({'old': oldName, 'new': newName}));
      _client.publishMessage('home/ac/rename', MqttQos.atLeastOnce, b.payload!);
    }
  }

  Future<void> _learnNew() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New command name'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'e.g. POWER'), autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () {
            final text = ctrl.text.trim();
            if (text.isNotEmpty) Navigator.pop(ctx, text);
          }, child: const Text('OK')),
        ],
      ),
    );
    if (name != null) {
      final b = MqttClientPayloadBuilder()..addString(jsonEncode({'name': name}));
      _client.publishMessage('home/ac/learn', MqttQos.atLeastOnce, b.payload!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final names = _commands.keys.toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('IR Commands'),
        actions: [ IconButton(icon: const Icon(Icons.refresh), onPressed: _requestList) ],
      ),
      body: names.isEmpty
          ? const Center(child: Text('No commands yet'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: names.length,
              itemBuilder: (ctx, i) {
                final cmd = names[i];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    title: Text(cmd.toUpperCase()),
                    leading: IconButton(
                      icon: const Icon(Icons.send),
                      onPressed: () => _send(cmd),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _rename(cmd),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () => _delete(cmd),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _learnNew,
        child: const Icon(Icons.add),
      ),
    );
  }
}
