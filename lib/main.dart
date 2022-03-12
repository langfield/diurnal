import 'dart:math';
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:intl/intl.dart';
import 'package:gsheets/gsheets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_countdown_timer/flutter_countdown_timer.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:diurnal/SECRETS.dart' as secrets;

// ignore_for_file: constant_identifier_names
// ignore_for_file: avoid_print
// ignore_for_file: unnecessary_brace_in_string_interps

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

// CONSTANTS

const String KEY = 'PRIVATE_KEY';
const String POINTER = '*';
const int DAY_WIDTH = 7;
const int DAY_HEIGHT = 74;
const int DAY_START_ROW = 2;
const int POINTER_COLUMN = 50;
const int POINTER_COLUMN_START_ROW = 1;
const int TITLE = 0;
const int DONE = 1;
const int WEIGHT = 2;
const int ACTUAL = 3;
const int MINS = 4;
const int LATE = 5;
const int TIME = 6;
const double FONT_SIZE = 15.0;
const Duration LEEWAY = Duration(minutes: 3);

const TextStyle STYLE = TextStyle(fontSize: FONT_SIZE, color: Colors.white);
const BorderRadius RADIUS = BorderRadius.all(Radius.circular(0.0));
const Color TRANSLUCENT_RED = Color.fromRGBO(255, 0, 0, 0.7);
const Color TRANSLUCENT_WHITE = Color.fromRGBO(255, 255, 255, 0.7);

const AndroidNotificationDetails ANDROID_DETAILS = AndroidNotificationDetails(
    'your channel id', 'your channel name',
    channelDescription: 'your channel description',
    importance: Importance.max,
    priority: Priority.high,
    ticker: 'ticker');
const NotificationDetails NOTIFICATION_DETAILS =
    NotificationDetails(android: ANDROID_DETAILS);

final formFieldDecoration = InputDecoration(
  errorBorder: getOutlineInputBorder(color: TRANSLUCENT_RED),
  focusedErrorBorder: getOutlineInputBorder(color: Colors.red),
  focusedBorder: getOutlineInputBorder(color: Colors.white),
  enabledBorder: getOutlineInputBorder(color: TRANSLUCENT_WHITE),
  errorStyle: STYLE,
  helperStyle: STYLE,
  helperText: " ",
  hintText: 'Service account private key',
  hintStyle: const TextStyle(color: TRANSLUCENT_WHITE),
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
  return ThemeData(
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
  return secrets.credentials.replaceAll('@@@@@@', escaped);
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

String? validatePrivateKey(String? candidate) {
  if (candidate == null || candidate.isEmpty) {
    return 'Empty private key';
  }
  if (!isValidPrivateKey(privateKey: candidate)) {
    return 'Bad private key';
  }
  return null;
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
  await Future.delayed(const Duration(seconds: 1));
  return gsheets;
}

Future<Worksheet> getWorksheet({required GSheets gsheets}) async {
  final ss = await gsheets.spreadsheet(secrets.ssid);
  Worksheet? sheet = ss.worksheetByTitle('Sheet1');
  if (sheet == null) throw Exception('Sheet1 not found :(');
  return sheet;
}

Future<int> getPointer({required GSheets gsheets}) async {
  Worksheet sheet = await getWorksheet(gsheets: gsheets);
  final List<Cell>? column = await sheet.cells.column(POINTER_COLUMN,
      fromRow: POINTER_COLUMN_START_ROW, length: DAY_HEIGHT);
  final List<String>? columnValues = await sheet.values.column(POINTER_COLUMN,
      fromRow: POINTER_COLUMN_START_ROW, length: DAY_HEIGHT);
  final int index = columnValues!.indexOf(POINTER);
  if (index == -1) return 0;
  final Cell pointerCell = column![index];
  return pointerCell.row;
}

Future<bool> setPointer(
    {required GSheets gsheets, required int rowIndex}) async {
  Worksheet sheet = await getWorksheet(gsheets: gsheets);
  await sheet.clearColumn(POINTER_COLUMN,
      fromRow: POINTER_COLUMN_START_ROW, length: DAY_HEIGHT);
  Cell newPointer =
      await sheet.cells.cell(row: rowIndex, column: POINTER_COLUMN);
  return await newPointer.post(POINTER);
}

/// Return empty list if there are no blocks with future end times.
Future<List<Cell>> getCurrentBlock(
    {required GSheets gsheets, required DateTime now}) async {
  print('    Fetching worksheet...');
  Worksheet sheet = await getWorksheet(gsheets: gsheets);

  // Get rows for current day of the week.
  print('    Fetching row matrix...');
  final int startColumn = ((now.weekday - 1) * DAY_WIDTH) + 1;
  List<List<Cell>> rows = await sheet.cells.allRows(
      fromRow: DAY_START_ROW,
      fromColumn: startColumn,
      length: DAY_WIDTH,
      count: DAY_HEIGHT);

  // Filter out blocks with empty cells and blocks that are done.
  print('    Filtering rows...');
  rows = rows.where((row) => !hasEmptyFields(row: row)).toList();
  rows = rows.where((row) => !isDone(row: row)).toList();

  print('    Getting pointer...');
  final int pointerIndex = await getPointer(gsheets: gsheets);

  // Set pointer. We skip any block with end time prior to its deadline.
  int newPointerIndex = 1;
  for (int i = 0; i < rows.length - 1; i++) {
    final List<Cell> row = rows[i];
    final List<Cell> nextRow = rows[i];
    final int rowIndex = row[0].row;
    final DateTime blockEndTime = getBlockEndTime(row: row, now: now);
    final DateTime nextBlockEndTime = getBlockEndTime(row: nextRow, now: now);
    final DateTime blockEndTimeWithLeeway = blockEndTime.add(LEEWAY);
    final List<DateTime> dates = [blockEndTimeWithLeeway, nextBlockEndTime];

    // Take maximum of ``dates``.
    final deadline = dates.reduce((a, b) => a.isAfter(b) ? a : b);
    if (deadline.isBefore(now)) {
      newPointerIndex = rowIndex;
    }
  }

  // Increment pointer to new index.
  print('    Incrementing row pointer: ${pointerIndex} -> ${newPointerIndex}');
  if (pointerIndex < newPointerIndex) {
    await setPointer(gsheets: gsheets, rowIndex: newPointerIndex);
  }

  // Iterate over blocks and return next block to display.
  for (List<Cell> row in rows) {
    final DateTime blockEndTime = getBlockEndTime(row: row, now: now);
    final int rowIndex = row[0].row;
    if (blockEndTime.isAfter(now) && pointerIndex < rowIndex) {
      final List<Cell> currentBlock = [...row];
      print('    Found current block!');
      return currentBlock;
    }
  }

  // Otherwise, return empty list.
  print('    No more incomplete blocks, congratulations!');
  return [];
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
      home: const PaddingLayer(),
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
        padding: EdgeInsets.all(0.05 * min(width, height)),
        child: const Diurnal(),
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
  GSheets? _gsheets;
  List<Cell>? _lastBlock;
  FlutterLocalNotificationsPlugin? _flutterLocalNotificationsPlugin;

  int _numBuilds = 0;
  bool _forceFetch = false;
  bool _gsheetsInitLock = false;
  bool _getCurrentBlockLock = false;
  final _storage = const FlutterSecureStorage();
  DateTime _lastBlockFetchTime = DateTime.utc(1944, 6, 6);

  @override
  void initState() {
    super.initState();

    print('initState:Getting private key from secure storage...');
    getPrivateKey(storage: _storage).then((String candidateKey) {
      handleCandidateKey(
          context: context, storage: _storage, candidateKey: candidateKey);
    });

    // Initialise the plugin. Note ``app_icon`` needs to be a added as a
    // drawable resource to the Android head project.
    FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('app_icon');
    const IOSInitializationSettings initializationSettingsIOS =
        IOSInitializationSettings();
    const MacOSInitializationSettings initializationSettingsMacOS =
        MacOSInitializationSettings();
    const LinuxInitializationSettings initializationSettingsLinux =
        LinuxInitializationSettings(defaultActionName: 'linux_notif');
    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
      macOS: initializationSettingsMacOS,
      linux: initializationSettingsLinux,
    );
    flutterLocalNotificationsPlugin.initialize(initializationSettings,
        onSelectNotification: (String? payload) async {
      if (payload != null) {
        print('notification payload: $payload');
      }
    });
    _flutterLocalNotificationsPlugin = flutterLocalNotificationsPlugin;
  }

  void handleCandidateKey(
      {required BuildContext context,
      required FlutterSecureStorage storage,
      required String candidateKey}) {
    if (candidateKey == '') {
      print('    Private key not found, sending user to form route.');
      final route = MaterialPageRoute(
          builder: (BuildContext context) =>
              PrivateKeyFormRoute(storage: storage, refresh: _refresh));
      Navigator.push(context, route);
      return;
    }
    setState(() {});
  }

  Future<void> showNotification({required GSheets gsheets}) async {
    String body = 'All done for today :)';
    if (block.isNotEmpty) {
      body = block[TITLE].value;
    }
    await _flutterLocalNotificationsPlugin!.show(
        0, 'Diurnal', body, NOTIFICATION_DETAILS,
        payload: 'PAYLOAD');
    setState(() {});
  }

  void _refresh() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Get a seed for this build for debugging.
    final rng = Random();
    final int seed = rng.nextInt(1000);

    print('Rebuilding "Diurnal:${seed}"...');
    final now = DateTime.now();
    _numBuilds += 1;
    print('${seed}: Num builds: $_numBuilds');

    if (_gsheets == null) {
      if (!_gsheetsInitLock) {
        _gsheetsInitLock = true;
        print('${seed}: Instantiating gsheets object...');
        getGSheets(storage: _storage).then((GSheets? gsheets) {
          _gsheetsInitLock = false;
          if (gsheets != null) {
            setState(() {
              _gsheets = gsheets;
            });
          }
        });
      } else {
        print('${seed}: Gsheets object already being initialized.');
      }
      return printConsoleText(text: 'Waiting for gsheets object...');
    }

    if (_getCurrentBlockLock) {
      print('${seed}: Already fetching current block...');
      return printConsoleText(text: 'Waiting for block...');
    }
    const oneMin = Duration(minutes: 1);
    final bool tooSoon = _lastBlockFetchTime.add(oneMin).isAfter(now);
    if (tooSoon && !_forceFetch) {
      print('${seed}: Got cached block.');
    } else {
      _getCurrentBlockLock = true;
      print('${seed}: Fetching current block from Google...');
      getCurrentBlock(
        gsheets: _gsheets!,
        now: now,
      ).then((List<Cell> block) {
        _getCurrentBlockLock = false;
        _lastBlockFetchTime = now;
        if (_lastBlock != block) {
          setState(() {
            print('${seed}: Updating last block state.');
            _lastBlock = block;
          });
        }
      });
      _forceFetch = false;
    }
    if (_lastBlock == null) {
      return printConsoleText(text: 'Waiting for block...');
    }

    final List<Cell> block = _lastBlock!;
    if (block.isEmpty) {
      return printConsoleText(text: 'All done for today :)');
    }

    const CrossAxisAlignment CROSS_START = CrossAxisAlignment.start;
    const CrossAxisAlignment CROSS_END = CrossAxisAlignment.start;
    const MainAxisAlignment MAIN_CENTER = MainAxisAlignment.center;
    const MainAxisAlignment MAIN_BETWEEN = MainAxisAlignment.spaceBetween;

    DateTime getTimerEnd({required DateTime end, required DateTime now}) {
      if (end.isBefore(now)) {
        return now;
      }
      return end;
    }

    final DateFormat formatter = DateFormat.Hm();
    final DateTime blockStartTime = getDateFromBlockRow(row: block, now: now);
    final DateTime blockEndTime = getBlockEndTime(row: block, now: now);
    final DateTime timerEnd = getTimerEnd(end: blockEndTime, now: now);
    final int msEndTime = timerEnd.millisecondsSinceEpoch;
    final String blockStartStr = formatter.format(blockStartTime);
    final String blockEndStr = formatter.format(blockEndTime);
    final String blockDuration = '${int.parse(block[MINS].value)}min';
    final String blockWeight = '${int.parse(block[WEIGHT].value)}N';
    final Widget blockTitle = Text(block[TITLE].value);
    final Widget blockProps = Text('${blockDuration}  ${blockWeight}');
    final Widget builds = Text('Number of builds: $_numBuilds');
    final Widget blockTimes = Text('$blockStartStr -> $blockEndStr UTC+0');
    final List<Widget> leftBlockWidgets = [blockTitle, blockProps, builds];
    Duration timeLeft = timerEnd.difference(now);

    print('${seed}: TIMER SECONDS LEFT: ${timeLeft.inSeconds}');
    Widget timer = Text('00:00:00');
    if (timeLeft.inSeconds > 0) {
      final now = DateTime.now();
      List<Cell> block = getCurrentBlock(gsheets: gsheets, now: now);
      void onEnd () => showNotification(gsheets: _gsheets!);
      timer = CountdownTimer(endTime: msEndTime, onEnd: onEnd);
    }

    final Widget leftBlockColumn =
        Column(crossAxisAlignment: CROSS_START, children: leftBlockWidgets);
    final Widget rightBlockColumn =
        Column(crossAxisAlignment: CROSS_END, children: <Widget>[blockTimes]);
    final List<Widget> blockColumns = [leftBlockColumn, rightBlockColumn];

    Cell doneCell = block[DONE];

    void doneHandler({required Cell doneCell, required double doneProportion}) {
      var doneFuture = doneCell.post(doneProportion);
      var pointerFuture =
          setPointer(gsheets: _gsheets!, rowIndex: doneCell.row);
      List<Future<bool>> futures = [doneFuture, pointerFuture];
      Future.wait(futures).then((_) {
        setState(() {
          _forceFetch = true;
        });
      });
      return;
    }

    const pass = Text('PASS', style: STYLE);
    const fail = Text('FAIL', style: STYLE);
    final Widget passButton = TextButton(
        onPressed: () => doneHandler(doneCell: doneCell, doneProportion: 1.0),
        child: pass);
    final Widget failButton = TextButton(
        onPressed: () => doneHandler(doneCell: doneCell, doneProportion: 0.0),
        child: fail);
    final List<Widget> buttons = [passButton, failButton];

    final Widget clearKeyButton = TextButton(
        onPressed: () {
          _storage.delete(key: KEY);
          print('Deleted private key!');
        },
        child: const Text('CLEAR KEY', style: STYLE));

    // Main column containing centered rows (block, buttons, timer).
    return Column(
      mainAxisAlignment: MAIN_CENTER,
      children: <Widget>[
        Row(
            mainAxisAlignment: MAIN_BETWEEN,
            crossAxisAlignment: CROSS_START,
            children: blockColumns),
        Row(mainAxisAlignment: MAIN_CENTER, children: buttons),
        Row(mainAxisAlignment: MAIN_CENTER, children: <Widget>[timer]),
        Row(mainAxisAlignment: MAIN_CENTER, children: <Widget>[clearKeyButton]),
      ],
    );
  }
}

class PrivateKeyFormRoute extends StatefulWidget {
  const PrivateKeyFormRoute(
      {Key? key, required this.storage, required this.refresh})
      : super(key: key);
  final FlutterSecureStorage storage;
  final VoidCallback refresh;

  @override
  PrivateKeyFormRouteState createState() {
    return PrivateKeyFormRouteState();
  }
}

class PrivateKeyFormRouteState extends State<PrivateKeyFormRoute> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    print('Building private key form route.');

    void submitKey() async {
      final privateKey = _controller.text;
      if (_formKey.currentState!.validate()) {
        await widget.storage.write(key: KEY, value: privateKey);
        widget.refresh();
        Navigator.pop(context);
      } else {
        print('Failed to validate input: $privateKey');
      }
    }

    var textFormField = TextFormField(
      validator: validatePrivateKey,
      controller: _controller,
      maxLines: 20,
      decoration: formFieldDecoration,
    );

    const submit = Text('Submit');
    var form = Form(key: _formKey, child: textFormField);
    var expForm = Expanded(child: form);
    var submitButton = TextButton(onPressed: submitKey, child: submit);
    var expSubmitButton = Expanded(child: submitButton);
    var formColumn = Column(children: <Widget>[expForm, expSubmitButton]);

    return Scaffold(body: formColumn);
  }
}
