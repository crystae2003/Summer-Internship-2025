import 'package:flutter/material.dart';
import 'control.dart';


void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AC Controller',
      home: ControlPage(),
      // home: BleSetupPage(),

      debugShowCheckedModeBanner: false,
    );
  }
}
