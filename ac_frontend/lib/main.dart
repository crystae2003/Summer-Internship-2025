import 'package:flutter/material.dart';
import 'control.dart';


void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AC Controller',
      home: IRRemoteApp(),
      // home: BleSetupPage(),

      debugShowCheckedModeBanner: false,
    );
  }
}
