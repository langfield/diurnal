import 'dart:math';
import 'dart:async';

import 'package:logger/logger.dart';
import 'package:gsheets/gsheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:diurnal/SECRETS.dart' as SECRETS;

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

// CONSTANTS

const String KEY = 'PRIVATE_KEY';

const int DAY_WIDTH = 7;
const int DAY_HEIGHT = 74;
const int DAY_START_ROW = 2;

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

// FUNCTIONS

// Run the main app.
void main() {
  runApp(const DiurnalApp());
}

// Authenticate with google and get a spreadsheet.
void getSheet(String credentials) async {
  final gsheets = GSheets(credentials);
  final ss = await gsheets.spreadsheet(SECRETS.ssid);
  var sheet = ss.worksheetByTitle('Sheet1');
  return;
}

void checkForPrivateKey(
    FlutterSecureStorage storage, BuildContext context) async {
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

String getCredentialsFromPrivateKey(String privateKey) {
  String escaped = privateKey.replaceAll('\n', '\\n');
  return SECRETS.credentials.replaceAll('@@@@@@', escaped);
}

// Validate private key by attempting to construct ``GSheets`` instance.
bool isValidPrivateKey(String? privateKey) {
  if (privateKey == null) {
    return false;
  }
  try {
    String credentials = getCredentialsFromPrivateKey(privateKey);
    final _ = GSheets(credentials);
    return true;
  } on ArgumentError catch (e) {
    print('Caught error: $e');
    return false;
  }
}


int getHoursFromDays(double days) {
  return (days * 24).floor();
}


int getMinutesFromDays(double days) {
  double hours = (days * 24);
  int wholeHours = hours.floor();
  double remainingHours = hours - wholeHours;
  return (remainingHours * 60).round();
}


void getCurrentBlock(FlutterSecureStorage storage, DateTime now) async {

  // Get private key, validate it, and get spreadsheet object.
  var logger = Logger(printer: PrettyPrinter(methodCount: 0));
  String? privateKey = await storage.read(key: KEY);
  if (!isValidPrivateKey(privateKey))
    return;
  privateKey = privateKey!;
  String credentials = getCredentialsFromPrivateKey(privateKey);
  final gsheets = GSheets(credentials);
  final ss = await gsheets.spreadsheet(SECRETS.ssid);

  // Get Sheet1.
  Worksheet? sheet = ss.worksheetByTitle('Sheet1');
  if (sheet == null) {
    print('Sheet1 not found :(');
    return;
  }

  // Get rows for current day of the week.
  final int startColumn = ((now.weekday - 1) * DAY_WIDTH) + 1;
  var rows = await sheet.cells.allRows(
      fromRow: DAY_START_ROW,
      fromColumn: startColumn,
      length: DAY_WIDTH,
      count: DAY_HEIGHT);

  logger.d(rows);

  // Get integral times in hr:min format for each row.
  for (final row in rows) {
    final DateTime blockDateTime = getDateFromBlockRow(row, now);
    logger.d('block DateTime: $blockDateTime');
  }

  return;
}

DateTime getDateFromBlockRow(List<Cell> row, DateTime now) {
  final String date = now.toString().split(' ')[0];
  Cell daysCell = row[DAY_WIDTH - 1];
  double days = double.parse(daysCell.value);
  int hours = getHoursFromDays(days);
  int mins = getMinutesFromDays(days);
  String hoursString = hours.toString().padLeft(2, '0');
  String minsString = mins.toString().padLeft(2, '0');
  String blockTime = '$hoursString:$minsString';
  String blockDateString = '$date $blockTime';
  DateTime blockDateTime = DateTime.parse(blockDateString);
  return blockDateTime;
}


// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

// WIDGET
// The main app, top-level widget.
class DiurnalApp extends StatelessWidget {
  const DiurnalApp({Key? key}) : super(key: key);

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
  final storage = new FlutterSecureStorage();

  // Build the state widget.
  @override
  Widget build(BuildContext context) {
    // Get current time so we can find the relevant block.
    var now = DateTime.now();
    print('Epoch ms: ${now.millisecondsSinceEpoch}');
    getCurrentBlock(storage, now);

    numBuilds += 1;

    // Dimensions of screen for setting padding.
    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;

    // Scaffold themed with the global theme set in ``DiurnalApp``.
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
    checkForPrivateKey(storage, context);

    // Build a Form widget using the _formKey created above.
    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;
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
                validator: (candidate) {
                  if (candidate == null || candidate.isEmpty) {
                    return 'Empty private key';
                  }
                  if (!isValidPrivateKey(candidate)) {
                    return 'Bad private key';
                  }
                  return null;
                },
                controller: controller,
                style: TextStyle(
                  fontSize: 20,
                ),
                maxLines: 20,
                cursorColor: Colors.white,

                decoration: const InputDecoration(
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(0.0)),
                    borderSide: const BorderSide(
                        color: Color.fromRGBO(255, 0, 0, 0.7), width: 2.0),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(0.0)),
                    borderSide: const BorderSide(color: Colors.red, width: 2.0),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(0.0)),
                    borderSide:
                        const BorderSide(color: Colors.white, width: 2.0),
                  ),
                  enabledBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(0.0)),
                    borderSide: const BorderSide(
                        color: Color.fromRGBO(255, 255, 255, 0.7), width: 2.0),
                  ),
                  errorStyle: TextStyle(fontSize: 24),
                  helperText: " ",
                  helperStyle: TextStyle(fontSize: 24),
                  hintText: 'Service account private key',
                  hintStyle:
                      TextStyle(color: Color.fromRGBO(255, 255, 255, 0.5)),
                  floatingLabelBehavior: FloatingLabelBehavior.never,
                ),
              ),
            ),

            // Button to submit private key.
            TextButton(
              // Validate private key and redirect to BlockDataRoute.
              onPressed: () async {
                // Get private key from form.
                final privateKey = controller.text;

                // If entered private key is valid, write private key to secure
                // storage and push BlockDataRoute.
                if (_formKey.currentState!.validate()) {
                  await storage.write(key: KEY, value: privateKey);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const BlockDataRoute()),
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
