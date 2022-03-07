import 'dart:math';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gsheets/gsheets.dart';
import 'package:diurnal/SECRETS.dart' as SECRETS;

/// Your spreadsheet id
///
/// It can be found in the link to your spreadsheet -
/// link looks like so https://docs.google.com/spreadsheets/d/YOUR_SPREADSHEET_ID/edit#gid=0
/// [YOUR_SPREADSHEET_ID] in the path is the id your need
const _spreadsheetId = '';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const MyCustomForm(),
      theme: new ThemeData(
        scaffoldBackgroundColor: const Color.fromRGBO(0, 0, 0, 1.0),
        textTheme: Theme.of(context).textTheme.apply(
              fontFamily: 'ATT',
              bodyColor: Colors.white,
              displayColor: Colors.white,
            ),
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key}) : super(key: key);

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  // Keep track of number of builds.
  int numBuilds = 0;

  void getSheet() async {
    // init GSheets
    final gsheets = GSheets(SECRETS.credentials);
    // fetch spreadsheet by its id
    final ss = await gsheets.spreadsheet(_spreadsheetId);
    // get worksheet by its title
    var sheet = ss.worksheetByTitle('Sheet1');
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.

    numBuilds += 1;

    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;
    return Scaffold(
      body: Padding(
        padding: EdgeInsets.all(0.2 * min(width, height)),
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Invoke "debug painting" (press "p" in the console, choose the
          // "Toggle Debug Paint" action from the Flutter Inspector in Android
          // Studio, or the "Toggle Debug Paint" command in Visual Studio Code)
          // to see the wireframe for each widget.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).

          mainAxisAlignment: MainAxisAlignment.center,

          children: <Widget>[
            // Block information.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Brush.+Floss.+Tongue.+Mouthwash.',
                      style: TextStyle(fontSize: 24),
                    ),
                    Text('100min  3N', style: TextStyle(fontSize: 24)),
                    Text('Number of builds: $numBuilds',
                        style: TextStyle(fontSize: 24, color: Colors.yellow)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text('21:35 -> 23:15 UTC+0', style: TextStyle(fontSize: 24))
                  ],
                ),
              ],
            ),

            // Pass/fail buttons.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                TextButton(
                  onPressed: getSheet,
                  child: const Text('PASS',
                      style: TextStyle(fontSize: 24, color: Colors.white)),
                ),
                TextButton(
                  onPressed: null,
                  child: const Text('FAIL',
                      style: TextStyle(fontSize: 24, color: Colors.white)),
                ),
              ],
            ),

            // Time remaining.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[Text('00:35', style: TextStyle(fontSize: 24))],
            ),
          ],
        ),
      ),
    );
  }
}

// Define a custom Form widget.
class MyCustomForm extends StatefulWidget {
  const MyCustomForm({Key? key}) : super(key: key);

  @override
  MyCustomFormState createState() {
    return MyCustomFormState();
  }
}

// Define a corresponding State class.
// This class holds data related to the form.
class MyCustomFormState extends State<MyCustomForm> {
  // Create a global key that uniquely identifies the Form widget
  // and allows validation of the form.
  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    // Build a Form widget using the _formKey created above.
    final width = MediaQuery.of(context).size.width;
    return Scaffold(
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: 0.3 * width),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Form(
              key: _formKey,
              child: TextFormField(

                // The validator receives the text that the user has entered.
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter some text';
                  }
                  return null;
                },
                style: TextStyle(
                  fontSize: 20,
                ),
                maxLines: 20,
                cursorColor: Colors.white,
                decoration: const InputDecoration(
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(0.0)),
                    borderSide: const BorderSide(color: Color.fromRGBO(255,255,255,1.0), width: 2.0),
                  ),
                  enabledBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(0.0)),
                    borderSide: const BorderSide(color: Color.fromRGBO(255,255,255,0.7), width: 2.0),
                  ),
                  hintText: 'Service account private key',
                  hintStyle: TextStyle(color: Color.fromRGBO(255, 255, 255, 0.5)),
                  floatingLabelBehavior: FloatingLabelBehavior.never,
                ),
              ),
            ),
            TextButton(
              onPressed: () {

                // Validate returns true if the form is valid, or false otherwise.
                // If the form is valid, display a snackbar. In the real world,
                // you'd often call a server or save the information in a database.
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Processing Data')),
                );
              },
              child: const Text('Submit', style: TextStyle(fontSize: 24, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
