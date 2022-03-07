import 'dart:math';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gsheets/gsheets.dart';
import 'package:diurnal/SECRETS.dart' as SECRETS;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

// CONSTANTS

/// Your spreadsheet id
///
/// It can be found in the link to your spreadsheet -
/// link looks like so https://docs.google.com/spreadsheets/d/YOUR_SPREADSHEET_ID/edit#gid=0
/// [YOUR_SPREADSHEET_ID] in the path is the id your need
const _spreadsheetId = '';
const KEY = 'PRIVATE_KEY';

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

// FUNCTIONS

// Run the main app.
void main() {
  runApp(const MyApp());
}

// Authenticate with google and get a spreadsheet.
void getSheet(String credentials) async {
  final gsheets = GSheets(credentials);
  final ss = await gsheets.spreadsheet(_spreadsheetId);
  var sheet = ss.worksheetByTitle('Sheet1');
  return;
}

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

// WIDGET
// The main app, top-level widget.
class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // Build the main application, and set the global theme.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const PrivateKeyFormRoute(),
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

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

// WIDGET
class BlockDataRoute extends StatefulWidget {
  const BlockDataRoute({Key? key}) : super(key: key);

  // Set the state of the route.
  @override
  State<BlockDataRoute> createState() => _BlockDataRouteState();
}

// STATE
class _BlockDataRouteState extends State<BlockDataRoute> {
  int numBuilds = 0;

  // Build the state widget.
  @override
  Widget build(BuildContext context) {
    numBuilds += 1;

    // Dimensions of screen for setting padding.
    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;

    // Scaffold themed with the global theme set in ``MyApp``.
    return Scaffold(

      // Pad all content with a margin.
      body: Padding(
        padding: EdgeInsets.all(0.2 * min(width, height)),

        // Main column containing several centered rows (block, buttons, timer).
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[

            // Block row.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[

                // Title, properties, number of builds.
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[

                    // Block title.
                    Text(
                      'Brush.+Floss.+Tongue.+Mouthwash.',
                      style: TextStyle(fontSize: 24),
                    ),

                    // Block duration and weight.
                    Text('100min  3N', style: TextStyle(fontSize: 24)),

                    // Debug number of builds.
                    Text('Number of builds: $numBuilds',
                        style: TextStyle(fontSize: 24, color: Colors.yellow)),
                  ],
                ),

                // Start and end time.
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
                  onPressed: () => getSheet(''),
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

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

// WIDGET
// Form for prompting user to enter private key.
class PrivateKeyFormRoute extends StatefulWidget {
  const PrivateKeyFormRoute({Key? key}) : super(key: key);

  @override
  PrivateKeyFormRouteState createState() {
    return PrivateKeyFormRouteState();
  }
}


void storageDemo(FlutterSecureStorage storage, BuildContext context) async {
  // Read value
  String? value = await storage.read(key: KEY);
  if (value != null) {
    print('Found existing private key.');
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const BlockDataRoute()),
    );
    return;
  }
  print("Couldn't find private key.");
}

// STATE
class PrivateKeyFormRouteState extends State<PrivateKeyFormRoute> {
  // Create a global key that uniquely identifies the Form widget
  // and allows validation of the form.
  final _formKey = GlobalKey<FormState>();
  final storage = new FlutterSecureStorage();
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    // Check for existing private key.
    storageDemo(storage, context);

    // Build a Form widget using the _formKey created above.
    final width = MediaQuery.of(context).size.width;
    return Scaffold(
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: 0.2 * width),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Form(
              key: _formKey,
              child: TextFormField(

                // The validator receives the text that the user has entered.
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Empty private key';
                  }
                  try {
                    String escaped = value.replaceAll('\n', '\\n');
                    String credentials = SECRETS.credentials.replaceAll('@@@@@@', escaped);
                    final _ = GSheets(credentials);
                    return null;
                  } on ArgumentError catch(e) {
                    print('Caught error: $e');
                    return 'Bad private key';
                  }
                  return 'FATAL: error not caught; please report this';
                },
                controller: controller,
                style: TextStyle(
                  fontSize: 20,
                ),
                maxLines: 20,
                cursorColor: Colors.white,
                decoration: const InputDecoration(
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(0.0)),
                    borderSide: const BorderSide(
                        color: Color.fromRGBO(255, 255, 255, 1.0), width: 2.0),
                  ),
                  enabledBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(0.0)),
                    borderSide: const BorderSide(
                        color: Color.fromRGBO(255, 255, 255, 0.7), width: 2.0),
                  ),
                  hintText: 'Service account private key',
                  hintStyle:
                      TextStyle(color: Color.fromRGBO(255, 255, 255, 0.5)),
                  floatingLabelBehavior: FloatingLabelBehavior.never,
                ),
              ),
            ),

            TextButton(
              onPressed: () {
                final privateKey = controller.text;
                if (_formKey.currentState!.validate()) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const BlockDataRoute()),
                  );
                } else {
                  print('Failed to validate input: $privateKey');
                }
              },
              child: const Text('Submit',
                  style: TextStyle(fontSize: 24, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
