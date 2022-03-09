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
const double FONT_SIZE = 30.0;

const TextStyle STYLE = TextStyle(fontSize: FONT_SIZE);
const BorderRadius RADIUS = BorderRadius.all(Radius.circular(0.0));
const Color TRANSLUCENT_RED = Color.fromRGBO(255, 0, 0, 0.7);
const Color TRANSLUCENT_WHITE = Color.fromRGBO(255, 255, 255, 0.7);

final FORM_FIELD_DECORATION = InputDecoration(
  errorBorder: getOutlineInputBorder(color: TRANSLUCENT_RED),
  focusedErrorBorder: getOutlineInputBorder(color: Colors.red),
  focusedBorder: getOutlineInputBorder(color: Colors.white),
  enabledBorder: getOutlineInputBorder(color: TRANSLUCENT_WHITE),
  errorStyle: STYLE,
  helperStyle: STYLE,
  helperText: " ",
  hintText: 'Service account private key',
  hintStyle: TextStyle(color: TRANSLUCENT_WHITE),
  floatingLabelBehavior: FloatingLabelBehavior.never,
);

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

// FUNCTIONS

// Run the main app.
void main() {
  runApp(const TopLevel());
}

OutlineInputBorder getOutlineInputBorder({required Color color}) {
  return OutlineInputBorder(
    borderRadius: RADIUS,
    borderSide: BorderSide(color: color, width: 2.0),
  );
}

ThemeData getTheme({required BuildContext context}) {
  return new ThemeData(
      scaffoldBackgroundColor: Colors.black,
      textTheme: Theme.of(context).textTheme.apply(
            fontFamily: 'ATT',
            bodyColor: Colors.white,
            displayColor: Colors.white,
            fontSizeFactor: 0,
            fontSizeDelta: FONT_SIZE,
          ));
}

Widget printConsoleText({required String text}) {
  return Scaffold(
    body: Text(text),
  );
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

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

// AWAITABLES

Future<String> getPrivateKey({required FlutterSecureStorage storage}) async {
  String? privateKey = await storage.read(key: KEY);
  if (privateKey == null) {
    print('Couldn\'t find private key in storage.');
    return '';
  }
  return privateKey;
}

Future<GSheets?> getGSheets({required FlutterSecureStorage storage}) async {
  String? privateKey = await storage.read(key: KEY);
  if (!isValidPrivateKey(privateKey: privateKey)) return null;
  String credentials = getCredentialsFromPrivateKey(privateKey: privateKey!);
  final gsheets = GSheets(credentials);
  await Future.delayed(Duration(seconds: 1));
  return gsheets;
}

/// Return empty list if there are no blocks with future end times.
Future<List<Cell>?> getFirstIncompleteBlockWithEndTimeInFuture(
    {required GSheets gsheets, required DateTime now}) async {
  var logger = Logger(printer: PrettyPrinter(methodCount: 0));

  // Get Sheet1.
  final ss = await gsheets.spreadsheet(SECRETS.ssid);
  Worksheet? sheet = ss.worksheetByTitle('Sheet1');
  if (sheet == null) {
    print('Sheet1 not found :(');
    return null;
  }
  print('Got Sheet1!');

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
  print('No nonempty incomplete blocks with valid end times, congratulations!');
  return [];
}

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

// AWAITABLE HANDLERS

void handleCandidateKey(
    {required BuildContext context,
    required FlutterSecureStorage storage,
    required String candidateKey}) {
  if (candidateKey == '') {
    print('Private key not found, sending user to form route.');
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) => PrivateKeyFormRoute(storage: storage)),
    );
    return;
  }
  print('Got private key in handler.');
}

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

// ROUTES

class TopLevel extends StatefulWidget {
  const TopLevel({Key? key}) : super(key: key);

  @override
  State<TopLevel> createState() => TopLevelState();
}

class TopLevelState extends State<TopLevel> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: PaddingLayer(),
      theme: getTheme(context: context),
    );
  }
}

class PaddingLayer extends StatefulWidget {
  const PaddingLayer({Key? key}) : super(key: key);

  @override
  State<PaddingLayer> createState() => PaddingLayerState();
}

class PaddingLayerState extends State<PaddingLayer> {
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;
    return Scaffold(
      body: Padding(
        padding: EdgeInsets.all(0.1 * min(width, height)),
        child: Diurnal(),
      ),
    );
  }
}

class Diurnal extends StatefulWidget {
  const Diurnal({Key? key}) : super(key: key);

  @override
  State<Diurnal> createState() => DiurnalState();
}

class DiurnalState extends State<Diurnal> {
  GSheets? gsheets;
  List<Cell>? lastBlock;

  int numBuilds = 0;
  final storage = new FlutterSecureStorage();
  String privateKey = '';
  DateTime lastBlockFetchTime = DateTime.utc(1944, 6, 6);

  @override
  Widget build(BuildContext context) {
    print('Building Diurnal widget...');
    var now = DateTime.now();
    numBuilds += 1;
    print('Num builds: $numBuilds');

    if (privateKey == '') {
      print('Getting private key from secure storage...');
      getPrivateKey(storage: storage).then((String candidateKey) {
        handleCandidateKey(
            context: context, storage: storage, candidateKey: candidateKey);
        setState(() {
          this.privateKey = candidateKey;
        });
      });
      return printConsoleText(text: 'Waiting for private key...');
    }

    if (this.gsheets == null) {
      print('Instantiating gsheets object...');
      getGSheets(storage: storage).then((GSheets? gsheets) {
        setState(() {
          this.gsheets = gsheets;
        });
      });
      return printConsoleText(text: 'Waiting for gsheets object...');
    }

    print('Getting current block...');
    if (this.lastBlockFetchTime.add(Duration(minutes: 1)).isAfter(now)) {
      print('Using cached block.');
    } else {
      print('Fetching current block from Google...');
      getFirstIncompleteBlockWithEndTimeInFuture(
        gsheets: gsheets!,
        now: now,
      ).then((List<Cell>? block) {
        this.lastBlockFetchTime = now;
        if (block != null && lastBlock != block) {
          setState(() {
            print('Updating last block state.');
            this.lastBlock = block;
          });
        }
      });
    }
    if (lastBlock == null) {
      return printConsoleText(text: 'Waiting for block...');
    }

    final List<Cell> block = lastBlock!;
    if (block.length == 0) {
      return printConsoleText(text: 'All done for today :)');
    }
    final DateFormat formatter = DateFormat.Hm();
    final DateTime blockStartTime = getDateFromBlockRow(row: block, now: now);
    final DateTime blockEndTime = getBlockEndTime(row: block, now: now);
    final String blockStartStr = formatter.format(blockStartTime);
    final String blockEndStr = formatter.format(blockEndTime);
    final String blockDuration = '${int.parse(block[MINS].value)}min';
    final String blockWeight = '${int.parse(block[WEIGHT].value)}N';

    // Main column containing several centered rows (block, buttons, timer).
    return Column(
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
                Text(block[TITLE].value),
                // Block duration and weight.
                Text('${blockDuration}  ${blockWeight}'),
                // Debug number of builds.
                Text('Number of builds: $numBuilds'),
              ],
            ),
            // Start and end time.
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[Text('$blockStartStr -> $blockEndStr UTC+0')],
            ),
          ],
        ),

        // Pass/fail buttons.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            TextButton(
              onPressed: () => null,
              child: const Text('PASS'),
            ),
            TextButton(onPressed: null, child: const Text('FAIL')),
          ],
        ),

        // Time remaining.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[Text('00:35')],
        ),
      ],
    );
  }
}

class PrivateKeyFormRoute extends StatefulWidget {
  const PrivateKeyFormRoute({Key? key, required this.storage})
      : super(key: key);
  final FlutterSecureStorage storage;

  @override
  PrivateKeyFormRouteState createState() {
    return PrivateKeyFormRouteState();
  }
}

class PrivateKeyFormRouteState extends State<PrivateKeyFormRoute> {
  final _formKey = GlobalKey<FormState>();
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    print('Building private key form route.');
    return Scaffold(
        body: Column(children: <Widget>[
      Form(
        key: _formKey,
        child: TextFormField(
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
          maxLines: 20,
          decoration: FORM_FIELD_DECORATION,
        ),
      ),
      TextButton(
        onPressed: () async {
          final privateKey = controller.text;
          if (_formKey.currentState!.validate()) {
            await widget.storage.write(key: KEY, value: privateKey);
            Navigator.pop(context);
          } else {
            print('Failed to validate input: $privateKey');
          }
        },
        child: const Text('Submit'),
      )
    ]));
  }
}
