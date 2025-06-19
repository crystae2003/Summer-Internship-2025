import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:async';

class ControlPage extends StatefulWidget {
  @override
  _ControlPageState createState() => _ControlPageState();
}

class _ControlPageState extends State<ControlPage>
    with TickerProviderStateMixin {
  // Replace with the IP your ESP32 printed
  static const String baseUrl = 'http://192.168.29.231';

  final GlobalKey<ScaffoldMessengerState> _scaffoldKey =
      GlobalKey<ScaffoldMessengerState>();

  // Track which button is currently pressed
  String? _pressedButton;
  bool _isResetting = false;

  // Animation controllers for button press effects
  late Map<String, AnimationController> _animationControllers;
  late Map<String, Animation<double>> _scaleAnimations;

  @override
  void initState() {
    super.initState();
    
    // Initialize animation controllers for each button
    final buttonKeys = ['play', 'pause', 'prev', 'fwd', 'reset'];
    _animationControllers = {};
    _scaleAnimations = {};
    
    for (String key in buttonKeys) {
      _animationControllers[key] = AnimationController(
        duration: Duration(milliseconds: 150),
        vsync: this,
      );
      _scaleAnimations[key] = Tween<double>(
        begin: 1.0,
        end: 0.95,
      ).animate(CurvedAnimation(
        parent: _animationControllers[key]!,
        curve: Curves.easeInOut,
      ));
    }
  }

  @override
  void dispose() {
    _animationControllers.values.forEach((controller) => controller.dispose());
    super.dispose();
  }

  Future<void> _send(String cmd) async {
    await _animateButtonPress(cmd);
    
    setState(() {
      _pressedButton = cmd;
    });

    final uri = Uri.parse('$baseUrl/send?cmd=$cmd');
    try {
      final res = await http.get(uri).timeout(Duration(seconds: 2));
      if (res.statusCode == 200) {
        _scaffoldKey.currentState?.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('Successfully sent: $cmd'),
              ],
            ),
            backgroundColor: Colors.grey[800],
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        _scaffoldKey.currentState?.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error, color: Colors.red),
                SizedBox(width: 8),
                Text('Error ${res.statusCode}'),
              ],
            ),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    } catch (e) {
      _scaffoldKey.currentState?.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error, color: Colors.red),
              SizedBox(width: 8),
              Text('Connection error: ${e.toString().split(':').first}'),
            ],
          ),
          backgroundColor: Colors.red[700],
        ),
      );
    } finally {
      // Clear the pressed state after a delay
      Future.delayed(Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() {
            _pressedButton = null;
          });
        }
      });
    }
  }
  Future<void> _resetWifi() async {
    await _animateButtonPress('reset');
    
    setState(() {
      _isResetting = true;
      _pressedButton = 'reset';
    });

    final uri = Uri.parse('$baseUrl/reset');
    bool success = false;

    try {
      final res = await http.get(uri).timeout(Duration(seconds: 3));
      success = res.statusCode == 200;
    } on Exception catch (e) {
      // Treat a timeout as success (ESP32 rebooting)
      if (e is TimeoutException) {
        success = true;
      } else {
        debugPrint('Reset error: $e');
      }
    }

    _scaffoldKey.currentState?.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              success ? Icons.check_circle : Icons.error,
              color: success ? Colors.green : Colors.red,
            ),
            SizedBox(width: 8),
            Text(success
                ? 'ESP32 is rebooting to setup mode…'
                : 'Reset failed'),
          ],
        ),
        backgroundColor: success ? Colors.grey[800] : Colors.red[700],
        duration: Duration(seconds: 3),
      ),
    );

    if (success) {
      // after a brief delay, show the dialog guiding the user
      Future.delayed(Duration(seconds: 3), () {
        if (mounted) _showNetworkConnectionDialog();
      });
    }

    setState(() {
      _isResetting = false;
      _pressedButton = null;
    });
  }


  void _showNetworkConnectionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.wifi_find, color: Colors.blue, size: 28),
              SizedBox(width: 12),
              Text(
                'Connect to Network',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.indigo[700],
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ESP32 is now in setup mode.',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[700],
                ),
              ),
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.settings, color: Colors.blue[600], size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Next Steps:',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.blue[700],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    Text(
                      '1. Go to your device Settings\n'
                      '2. Open Wi-Fi/Network settings\n'
                      '3. Look for ESP32 network in the list\n'
                      '4. Connect to configure your speaker',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text(
                'Got it!',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.blue[600],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _animateButtonPress(String buttonKey) async {
    final controller = _animationControllers[buttonKey];
    if (controller != null) {
      await controller.forward();
      await controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: _scaffoldKey,
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          title: Text(
            'Speaker Control',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          backgroundColor: Colors.indigo,
          foregroundColor: Colors.white,
          elevation: 2,
        ),
        body: Container(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Status indicator
                Container(
                  padding: EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                  decoration: BoxDecoration(
                    color: Colors.indigo[50],
                    borderRadius: BorderRadius.circular(25),
                    border: Border.all(color: Colors.indigo[200]!),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Connected to ESP32',
                        style: TextStyle(
                          color: Colors.indigo[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 40),
                
                // Control buttons
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  alignment: WrapAlignment.center,
                  children: [
                    _buildControlButton(
                      'play',
                      '▶️',
                      'Play',
                      Colors.green,
                      () => _send('play'),
                    ),
                    _buildControlButton(
                      'pause',
                      '⏸',
                      'Pause',
                      Colors.orange,
                      () => _send('pause'),
                    ),
                    _buildControlButton(
                      'prev',
                      '⏮',
                      'Previous',
                      Colors.blue,
                      () => _send('prev'),
                    ),
                    _buildControlButton(
                      'fwd',
                      '⏭',
                      'Next',
                      Colors.blue,
                      () => _send('fwd'),
                    ),
                  ],
                ),
                
                SizedBox(height: 40),
                
                // Reset button (separate section)
                Container(
                  width: double.infinity,
                  height: 1,
                  color: Colors.grey[300],
                  margin: EdgeInsets.symmetric(horizontal: 40),
                ),
                SizedBox(height: 30),
                
                _buildResetButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControlButton(
    String key,
    String emoji,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    final isPressed = _pressedButton == key;
    
    return AnimatedBuilder(
      animation: _scaleAnimations[key]!,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimations[key]!.value,
          child: AnimatedContainer(
            duration: Duration(milliseconds: 200),
            child: ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: isPressed ? color.withOpacity(0.8) : Colors.white,
                foregroundColor: isPressed ? Colors.white : color,
                elevation: isPressed ? 8 : 2,
                shadowColor: color.withOpacity(0.3),
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: isPressed ? color : color.withOpacity(0.3),
                    width: isPressed ? 2 : 1,
                  ),
                ),
                minimumSize: Size(120, 80),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    emoji,
                    style: TextStyle(fontSize: 24),
                  ),
                  SizedBox(height: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildResetButton() {
    final isPressed = _pressedButton == 'reset';
    
    return AnimatedBuilder(
      animation: _scaleAnimations['reset']!,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimations['reset']!.value,
          child: AnimatedContainer(
            duration: Duration(milliseconds: 200),
            child: ElevatedButton.icon(
              onPressed: _isResetting ? null : _resetWifi,
              icon: _isResetting
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Icon(Icons.refresh),
              label: Text(
                _isResetting ? 'Resetting...' : 'Reset Wi‑Fi',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: isPressed 
                    ? Colors.red[600] 
                    : (_isResetting ? Colors.grey : Colors.red[500]),
                foregroundColor: Colors.white,
                elevation: isPressed ? 8 : 3,
                shadowColor: Colors.red.withOpacity(0.3),
                padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                minimumSize: Size(200, 56),
              ),
            ),
          ),
        );
      },
    );
  }
}