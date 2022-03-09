import 'dart:math';
import 'dart:async';

import 'package:intl/intl.dart';
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
const int TITLE = 0;
const int DONE = 1;
const int WEIGHT = 2;
const int ACTUAL = 3;
const int MINS = 4;
const int LATE = 5;
const int TIME = 6;

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

// FUNCTIONS

// Run the main app.
void main() {
  runApp(const DiurnalApp());
}

// Authenticate with google and get a spreadsheet.
void getSheet({required String credentials}) async {
  final gsheets = GSheets(credentials);
  final ss = await gsheets.spreadsheet(SECRETS.ssid);
  var sheet = ss.worksheetByTitle('Sheet1');
  return;
}

void checkForPrivateKey(
    {required FlutterSecureStorage storage,
    required BuildContext context}) async {
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

String getCredentialsFromPrivateKey({required String privateKey}) {
  String escaped = privateKey.replaceAll('\n', '\\n');
  return SECRETS.credentials.replaceAll('@@@@@@', escaped);
}

// Validate private key by attempting to construct ``GSheets`` instance.
bool isValidPrivateKey({required String? privateKey}) {
  if (privateKey == null) {
    return false;
  }
  try {
    String credentials = getCredentialsFromPrivateKey(privateKey: privateKey);
    final _ = GSheets(credentials);
    return true;
  } on ArgumentError catch (e) {
    print('Caught error: $e');
    return false;
  }
}

DateTime getDateFromBlockRow({required List<Cell> row, required DateTime now}) {
  final String date = now.toString().split(' ')[0];
  Cell daysCell = row[DAY_WIDTH - 1];
  double days = double.parse(daysCell.value);
  int hours = getHoursFromDays(days: days);
  int mins = getMinutesFromDays(days: days);
  String hoursString = hours.toString().padLeft(2, '0');
  String minsString = mins.toString().padLeft(2, '0');
  String blockTime = '$hoursString:$minsString';
  String blockDateString = '$date $blockTime';
  DateTime blockDateTime = DateTime.parse(blockDateString);
  return blockDateTime;
}

int getHoursFromDays({required double days}) {
  return (days * 24).floor();
}

int getMinutesFromDays({required double days}) {
  double hours = (days * 24);
  int wholeHours = hours.floor();
  double remainingHours = hours - wholeHours;
  return (remainingHours * 60).round();
}

/// Return true if any cells are empty strings.
bool hasEmptyFields({required List<Cell> row}) {
  for (final Cell cell in row) {
    if (cell.value == '') {
      return true;
    }
  }
  return false;
}

/// Get the end DateTime of the block, where ``row`` is assumed to be nonempty.
DateTime getBlockEndTime({required List<Cell> row, required DateTime now}) {
  final DateTime startTime = getDateFromBlockRow(row: row, now: now);
  final Duration duration = Duration(minutes: int.parse(row[MINS].value));
  final DateTime endTime = startTime.add(duration);
  return endTime;
}

bool isDone({required List<Cell> row}) {
  final String doneString = row[DONE].value;
  final double doneDecimal = double.parse(doneString);
  final int done = doneDecimal.floor();
  if (done == 1) {
    return true;
  }
  return false;
}

Future<GSheets?> getGSheets({required FlutterSecureStorage storage}) async {
  String? privateKey = await storage.read(key: KEY);
  if (!isValidPrivateKey(privateKey: privateKey)) return null;
  privateKey = privateKey!;
  String credentials = getCredentialsFromPrivateKey(privateKey: privateKey);
  final gsheets = GSheets(credentials);
  return gsheets;
}

Widget consoleMessage({required String text}) {
  return Scaffold(body: Text(text, style: TextStyle(fontSize: 24)));
}

/// Return empty list if there are no blocks with future end times.
Future<List<Cell>> getFirstIncompleteBlockWithEndTimeInFuture(
    {required GSheets gsheets,
    required DateTime now,
    required List<Cell> lastBlock,
    required DateTime lastBlockFetchTime}) async {
  var logger = Logger(printer: PrettyPrinter(methodCount: 0));

  // Crude caching.
  if (lastBlockFetchTime.add(Duration(minutes: 1)).isAfter(now)) {
    print('Using cached block');
    return lastBlock;
  }

  final ss = await gsheets.spreadsheet(SECRETS.ssid);

  // Get Sheet1.
  Worksheet? sheet = ss.worksheetByTitle('Sheet1');
  if (sheet == null) {
    print('Sheet1 not found :(');
    return [];
  }

  // Get rows for current day of the week.
  final int startColumn = ((now.weekday - 1) * DAY_WIDTH) + 1;
  final rows = await sheet.cells.allRows(
      fromRow: DAY_START_ROW,
      fromColumn: startColumn,
      length: DAY_WIDTH,
      count: DAY_HEIGHT);

  final nonEmptyRows = rows.where((row) => !hasEmptyFields(row: row)).toList();

  final nonEmptyIncompleteRows =
      nonEmptyRows.where((row) => !isDone(row: row)).toList();
  print('Nonempty incomplete blocks: ${nonEmptyIncompleteRows.length}');

  List<Cell>? firstIncompleteBlockWithEndTimeInFuture;

  // Iterate over blocks and return as soon as we find one with future end time.
  for (final row in nonEmptyIncompleteRows) {
    final DateTime blockDateTime = getDateFromBlockRow(row: row, now: now);
    final DateTime blockEndTime = getBlockEndTime(row: row, now: now);
    if (blockEndTime.isAfter(now)) {
      firstIncompleteBlockWithEndTimeInFuture = [...row];
      print('Returning!');
      return firstIncompleteBlockWithEndTimeInFuture;
    }
    print('block DateTime: $blockDateTime');
  }

  // Otherwise, return empty list.
  print('Couldn\'t find block, returning empty list :(');
  return [];
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
  DateTime lastBlockFetchTime = DateTime.utc(1944, 6, 6);
  List<Cell> lastBlock = [];
  GSheets? gsheets;

  // Initialize state.
  @override
  void initState() {
    print('Init state called.');
    super.initState();
    getGSheets(storage: storage).then((GSheets? gsheets) {
      this.gsheets = gsheets;
      setState(() {});
    });
  }

  // Build the state widget.
  @override
  Widget build(BuildContext context) {
    // Get current time so we can find the relevant block.
    var now = DateTime.now();
    numBuilds += 1;
    print('Num builds: $numBuilds');

    if (gsheets == null) {
      return Scaffold(
          body: Text('Failed to connect to gsheets.',
              style: TextStyle(fontSize: 24)));
    }

    // Dimensions of screen for setting padding.
    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;

    // Scaffold themed with the global theme set in ``DiurnalApp``.
    return FutureBuilder<List<Cell>>(
      future: getFirstIncompleteBlockWithEndTimeInFuture(
          gsheets: gsheets!,
          now: now,
          lastBlock: lastBlock,
          lastBlockFetchTime: lastBlockFetchTime),
      builder: (BuildContext context, AsyncSnapshot<List<Cell>> snapshot) {
        if (snapshot.hasError) {
          return Center(
              child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(
                Icons.error_outline,
                color: Colors.red,
                size: 60,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text('Error: ${snapshot.error}'),
              )
            ],
          ));
        } else if (!snapshot.hasData) {
          return Scaffold(
              body:
                  Text('Awaiting for future.', style: TextStyle(fontSize: 24)));
        } else {
          // Get block from future.
          List<Cell>? block = snapshot.data;

          // Record last fetch time.
          lastBlockFetchTime = now;

          if (block == null) {
            print('Block is null!');
            return consoleMessage(text: 'Null block');
          }

          if (block.length == 0) {
            print('Block is empty!');
            return consoleMessage(text: 'Empty block');
          }

          // Cache block.
          lastBlock = block;

          final DateTime blockStartTime =
              getDateFromBlockRow(row: block, now: now);
          final DateTime blockEndTime = getBlockEndTime(row: block, now: now);
          final DateFormat formatter = DateFormat.Hm();
          final String blockStartStr = formatter.format(blockStartTime);
          final String blockEndStr = formatter.format(blockEndTime);

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
                            block[TITLE].value,
                            style: TextStyle(fontSize: 24),
                          ),

                          // Block duration and weight.
                          Text(
                              '${int.parse(block[MINS].value)}min  ${int.parse(block[WEIGHT].value)}N',
                              style: TextStyle(fontSize: 24)),

                          // Debug number of builds.
                          Text('Number of builds: $numBuilds',
                              style: TextStyle(
                                  fontSize: 24, color: Colors.yellow)),
                        ],
                      ),

                      // Start and end time.
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          Text('$blockStartStr -> $blockEndStr UTC+0',
                              style: TextStyle(fontSize: 24))
                        ],
                      ),
                    ],
                  ),

                  // Pass/fail buttons.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      TextButton(
                        onPressed: () => getSheet(credentials: ''),
                        child: const Text('PASS',
                            style:
                                TextStyle(fontSize: 24, color: Colors.white)),
                      ),
                      TextButton(
                        onPressed: null,
                        child: const Text('FAIL',
                            style:
                                TextStyle(fontSize: 24, color: Colors.white)),
                      ),
                    ],
                  ),

                  // Time remaining.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text('00:35', style: TextStyle(fontSize: 24))
                    ],
                  ),
                ],
              ),
            ),
          );
        }
      },
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
    checkForPrivateKey(storage: storage, context: context);

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
                  if (!isValidPrivateKey(privateKey: candidate)) {
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
