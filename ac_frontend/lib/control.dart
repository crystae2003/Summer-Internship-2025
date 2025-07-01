import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'dart:convert';

// void main() => runApp(const IRControllerApp());

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
  List<String> _commands = [];

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
    _client.updates?.listen(_onMessage);
  }

  Future<void> _connect() async {
    try {
      await _client.connect();
    } catch (e) {
      setState(() => _status = 'MQTT connect failed');
    }
  }

  void _onConnected() {
    setState(() => _status = 'Connected');
    _client.subscribe('home/ac/status', MqttQos.atLeastOnce);
    _client.subscribe('home/ac/available_cmds', MqttQos.atLeastOnce);
    _requestList();
  }

  void _onDisconnected() {
    setState(() {
      _status   = 'Disconnected';
      _commands = [];
    });
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage?>> events) {
    final rec   = events[0];
    final topic = rec.topic;
    final msg   = (rec.payload as MqttPublishMessage)
                      .payload.message;
    final raw   = MqttPublishPayload.bytesToStringAsString(msg);

    if (topic == 'home/ac/status') {
      setState(() => _status = raw);
      if (raw.startsWith('Learned')) {
        Future.delayed(const Duration(milliseconds: 500), _requestList);
      }
    }
    else if (topic == 'home/ac/available_cmds') {
      dynamic decoded = jsonDecode(raw);
      if (decoded is String) decoded = jsonDecode(decoded);
      final map = decoded as Map<String, dynamic>;
      setState(() => _commands = map.keys.toList());
    }
  }

  void _requestList() {
    final builder = MqttClientPayloadBuilder()..addString('');
    _client.publishMessage('home/ac/list', MqttQos.atLeastOnce, builder.payload!);
  }

  void _sendCommand(String name) {
    final builder = MqttClientPayloadBuilder()
      ..addString(jsonEncode({'name': name}));
    _client.publishMessage('home/ac/send', MqttQos.atLeastOnce, builder.payload!);
  }

  void _sendEraseAll() {
  final builder = MqttClientPayloadBuilder()..addString('');
  _client.publishMessage('home/ac/erase_all', MqttQos.atLeastOnce, builder.payload!);
}
void _resetWiFi() {
  final builder = MqttClientPayloadBuilder()..addString('reset');
  _client.publishMessage('home/ac/reset_wifi', MqttQos.atLeastOnce, builder.payload!);
}


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('IR MQTT Controller'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _requestList),
          IconButton(icon: const Icon(Icons.delete), onPressed: _sendEraseAll, tooltip: 'Erase All Commands',),
          IconButton(
          icon: const Icon(Icons.settings_backup_restore),
          tooltip: 'Reset Wi-Fi',
          onPressed: () {
            _resetWiFi();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Reset command sent to ESP32'))
            );
          },
  ),
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
            child: _commands.isEmpty
                ? const Center(child: Text('No commands learned yet.'))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _commands.length,
                    itemBuilder: (ctx, i) {
                      final cmd = _commands[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: ElevatedButton(
                          onPressed: () => _sendCommand(cmd),
                          child: Text(cmd.toUpperCase()),
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
