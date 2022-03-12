import 'dart:math';
import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';

import 'package:intl/intl.dart';
import 'package:gsheets/gsheets.dart';
import 'package:flutter_countdown_timer/index.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
const Duration ONE_MINUTE = Duration(minutes: 1);

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
const NotificationDetails DETAILS =
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

const CrossAxisAlignment CROSS_START = CrossAxisAlignment.start;
const CrossAxisAlignment CROSS_END = CrossAxisAlignment.start;
const MainAxisAlignment MAIN_CENTER = MainAxisAlignment.center;
const MainAxisAlignment MAIN_BETWEEN = MainAxisAlignment.spaceBetween;

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

GSheets getGSheets({required String privateKey}) {
  String escaped = privateKey.replaceAll('\n', '\\n');
  String credentials = secrets.credentials.replaceAll('@@@@@@', escaped);
  return GSheets(credentials);
}

// Validate private key by attempting to construct ``GSheets`` instance.
bool isValidPrivateKey({required String? privateKey}) {
  if (privateKey == null) {
    return false;
  }
  try {
    final GSheets _ = getGSheets(privateKey: privateKey);
    return true;
  } on ArgumentError catch (e) {
    print('Caught error: $e');
    return false;
  }
}

List<List<Cell>> filterRows({required List<List<Cell>> rows}) {
  rows = rows.where((block) => !hasEmptyFields(block: block)).toList();
  rows = rows.where((block) => !isDone(block: block)).toList();
  return rows;
}

/// Return true if any cells are empty strings.
bool hasEmptyFields({required List<Cell> block}) {
  for (final Cell cell in block) {
    if (cell.value == '') {
      return true;
    }
  }
  return false;
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

DateTime getBlockStartTime({required List<Cell> block, required DateTime now}) {
  final String date = now.toString().split(' ')[0];
  Cell daysCell = block[DAY_WIDTH - 1];
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

/// Get the end DateTime of the block, where ``block`` is assumed to be nonempty.
DateTime getBlockEndTime({required List<Cell> block, required DateTime now}) {
  final DateTime startTime = getBlockStartTime(block: block, now: now);
  final Duration duration = Duration(minutes: int.parse(block[MINS].value));
  final DateTime endTime = startTime.add(duration);
  return endTime;
}

bool isDone({required List<Cell> block}) {
  final String doneString = block[DONE].value;
  final double doneDecimal = double.parse(doneString);
  final int done = doneDecimal.floor();
  if (done == 1) {
    return true;
  }
  return false;
}

// Calculate new pointer based on current datetime.
// We skip any block with end time prior to its deadline.
int computeNewPointer({required List<List<Cell>> rows, required DateTime now}) {
  int newPtr = 1;
  for (int i = 0; i < rows.length - 1; i++) {
    final List<Cell> block = rows[i];
    final List<Cell> nextBlock = rows[i];
    final int rowIndex = block[0].row;
    final DateTime blockEndTime = getBlockEndTime(block: block, now: now);
    final DateTime nextBlockEndTime =
        getBlockEndTime(block: nextBlock, now: now);
    final DateTime blockEndTimeWithLeeway = blockEndTime.add(LEEWAY);
    final List<DateTime> dates = [blockEndTimeWithLeeway, nextBlockEndTime];

    // Take maximum of ``dates``.
    final deadline = dates.reduce((a, b) => a.isAfter(b) ? a : b);
    if (deadline.isBefore(now)) {
      newPtr = rowIndex;
    }
  }
  return newPtr;
}

Queue<List<Cell>> getStackFromRows(
    {required List<List<Cell>> rows, required int ptr}) {
  print('Getting stack from rows...');
  final Queue<List<Cell>> stack = Queue();
  for (int i = 0; i < rows.length - 1; i++) {
    final int row = rows[i][TITLE].row;
    if (row == ptr) {
      stack.addAll(rows.sublist(i + 1, rows.length));
      return stack;
    }
  }
  print('Returning empty stack.');
  return stack;
}

FlutterLocalNotificationsPlugin getNotificationsPlugin() {
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
  const InitializationSettings initializationSettings = InitializationSettings(
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
  return flutterLocalNotificationsPlugin;
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

DateTime getTimerEnd({required DateTime end, required DateTime now}) {
  if (end.isBefore(now)) return now;
  return end;
}


Widget consoleMessage({required String text}) {
  return Scaffold(
    body: Text(text),
  );
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
  // UNINITIALIZED STATE

  String? _key;

  Queue<List<Cell>>? _stack;
  Worksheet? _worksheet;

  int? _currentBlockIndex;
  CountdownTimer? _currentBlockTimer;
  List<Cell>? _currentBlock;
  FlutterLocalNotificationsPlugin? _notifications;

  // INITIALIZED STATE

  int _numBuilds = 0;
  final _storage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    readPrivateKey();
    _notifications = getNotificationsPlugin();
    Timer.periodic(ONE_MINUTE, (Timer t) => updateWorksheet());
  }

  void _refresh() {
    setState(() {});
  }

  // AWAITABLE METHODS

  Future<void> initWorksheet({required String privateKey}) async {
    print('Initializing worksheet...');
    if (!isValidPrivateKey(privateKey: privateKey)) {
      print('Got invalid private key :(');
      return;
    }
    final GSheets gsheets = getGSheets(privateKey: privateKey);
    final ss = await gsheets.spreadsheet(secrets.ssid);
    _worksheet = ss.worksheetByTitle('Sheet1');
  }

  Future<void> updateWorksheet() async {
    print('Updating worksheet...');
    if (_key == null) return;
    if (_worksheet == null) return;
    final now = DateTime.now();

    // HTTP GET REQUEST.
    _stack = await getStack(now: now);

    // This is not always at the top of stack.
    _currentBlockIndex = getCurrentBlockIndex(now: now);
    resetBlockTimer();
  }

  Future<void> readPrivateKey() async {
    print('Reading private key...');
    final String? key = await _storage.read(key: KEY);
    if (key == null) await pushFormRoute();
    _key = await _storage.read(key: KEY);
    await initWorksheet(privateKey: _key!);
    await updateWorksheet();
    setState(() {});
  }

  Future<void> onTimerEnd() async {
    if (_currentBlock == null) return;
    if (_currentBlockIndex == null) return;
    showNotification(block: _currentBlock!);
    _currentBlockIndex = _currentBlockIndex! + 1;
    resetBlockTimer();
  }

  Future<void> showNotification({required List<Cell> block}) async {
    String body = 'All done for today :)';
    if (block.isNotEmpty) body = block[TITLE].value;
    await _notifications!.show(0, 'Diurnal', body, DETAILS, payload: 'LOAD');
  }

  Future<void> passOrFail({required double score}) async {
    if (_stack == null) return;
    if (_stack!.isEmpty) return;
    final List<Cell> concludedBlock = _stack!.removeFirst();
    setState(() {});
    final Cell doneCell = concludedBlock[DONE];
    doneCell.post(score);
  }

  // TODO: Is it still necessary to refresh from ``PrivateKeyFormRoute``?
  Future<void> pushFormRoute() async {
    final route = MaterialPageRoute(
        builder: (BuildContext context) =>
            PrivateKeyFormRoute(storage: _storage, refresh: _refresh));
    await Navigator.push(context, route);
  }

  Future<Queue<List<Cell>>> getStack({required DateTime now}) async {
    print('Getting stack...');
    // HTTP GET REQUEST.
    List<List<Cell>> rows = await getRows(now: now);
    rows = filterRows(rows: rows);
    // HTTP GET REQUEST.
    final int oldPtr = await getPointer();
    final int newPtr = computeNewPointer(rows: rows, now: now);
    if (oldPtr < newPtr) await setPointer(ptr: newPtr);
    Queue<List<Cell>> stack = getStackFromRows(rows: rows, ptr: newPtr);
    return stack;
  }

  Future<List<List<Cell>>> getRows({required DateTime now}) async {
    final int startColumn = ((now.weekday - 1) * DAY_WIDTH) + 1;
    // HTTP GET REQUEST.
    List<List<Cell>> rows = await _worksheet!.cells.allRows(
        fromRow: DAY_START_ROW,
        fromColumn: startColumn,
        length: DAY_WIDTH,
        count: DAY_HEIGHT);
    return rows;
  }

  Future<int> getPointer() async {
    // HTTP GET REQUEST.
    final List<Cell>? column = await _worksheet!.cells.column(POINTER_COLUMN,
        fromRow: POINTER_COLUMN_START_ROW, length: DAY_HEIGHT);
    for (final Cell cell in column!) {
      if (cell.value == '*') {
        return cell.row;
      }
    }
    return POINTER_COLUMN_START_ROW;
  }

  Future<void> setPointer({required int ptr}) async {
    // HTTP GET REQUEST.
    await _worksheet!.clearColumn(POINTER_COLUMN,
        fromRow: POINTER_COLUMN_START_ROW, length: DAY_HEIGHT);
    // HTTP GET REQUEST.
    Cell newPointer = await _worksheet!.cells.cell(row: ptr, column: POINTER_COLUMN);
    // HTTP GET REQUEST.
    await newPointer.post(POINTER);
  }

  // METHODS

  // TODO: Should ``now`` be passed as an argument?
  void resetBlockTimer() {
    if (_stack == null) return;
    if (_currentBlockIndex == null) return;
    if (_currentBlockIndex! >= _stack!.length) return;
    _currentBlock = _stack!.elementAt(_currentBlockIndex!);
    // BUG: Null check operator used on null value.
    if (_currentBlockTimer != null) {
      var controller = _currentBlockTimer!.controller;
      if (controller != null) controller.dispose();
    }

    final now = DateTime.now();
    final List<Cell> block = _currentBlock!;
    final DateTime blockEndTime = getBlockEndTime(block: block, now: now);
    final DateTime timerEnd = getTimerEnd(end: blockEndTime, now: now);
    final int msEndTime = timerEnd.millisecondsSinceEpoch;
    final con = CountdownTimerController(endTime: msEndTime, onEnd: onTimerEnd);
    _currentBlockTimer = CountdownTimer(controller: con);
  }

  int? getCurrentBlockIndex({required DateTime now}) {
    for (int i = 0; i < _stack!.length; i++) {
      final List<Cell> block = _stack!.elementAt(i);
      DateTime blockStartTime = getBlockStartTime(block: block, now: now);
      DateTime blockEndTime = getBlockEndTime(block: block, now: now);
      if (now.isAtSameMomentAs(blockStartTime) || now.isAfter(blockStartTime)) {
        if (now.isBefore(blockEndTime)) return i;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    _numBuilds += 1;
    final rng = Random();
    final int seed = rng.nextInt(1000);
    print('${seed}: Num builds: $_numBuilds');

    if (_stack == null) return consoleMessage(text: 'Fetching data...');
    if (_worksheet == null) return consoleMessage(text: 'Null worksheet :(');
    if (_stack!.isEmpty) return consoleMessage(text: 'All done :)');

    Widget timer = const Text('00:00');
    if (_currentBlockIndex == 0 && _currentBlockTimer != null) {
      timer = _currentBlockTimer!;
    }

    final List<Cell> dueBlock = _stack!.first;

    return getBlockWidget(block: dueBlock, timer: timer);
  }

  Widget getBlockWidget({required List<Cell> block, required Widget timer}) {
    final now = DateTime.now();
    final DateFormat formatter = DateFormat.Hm();
    final DateTime blockStartTime = getBlockStartTime(block: block, now: now);
    final DateTime blockEndTime = getBlockEndTime(block: block, now: now);

    final String blockStartStr = formatter.format(blockStartTime);
    final String blockEndStr = formatter.format(blockEndTime);
    final String blockDuration = '${int.parse(block[MINS].value)}min';
    final String blockWeight = '${int.parse(block[WEIGHT].value)}N';

    final Widget blockTitle = Text(block[TITLE].value);
    final Widget blockProps = Text('${blockDuration}  ${blockWeight}');
    final Widget builds = Text('Number of builds: ${_numBuilds}');
    final Widget blockTimes = Text('${blockStartStr} -> ${blockEndStr} UTC+0');

    final List<Widget> leftBlockWidgets = [blockTitle, blockProps, builds];

    final Widget leftBlockColumn =
        Column(crossAxisAlignment: CROSS_START, children: leftBlockWidgets);
    final Widget rightBlockColumn =
        Column(crossAxisAlignment: CROSS_END, children: <Widget>[blockTimes]);
    final List<Widget> blockColumns = [leftBlockColumn, rightBlockColumn];

    const passText = Text('PASS', style: STYLE);
    const failText = Text('FAIL', style: STYLE);
    void pass() => passOrFail(score: 1.0);
    void fail() => passOrFail(score: 0.0);
    final Widget passButton = TextButton(onPressed: pass, child: passText);
    final Widget failButton = TextButton(onPressed: fail, child: failText);
    final List<Widget> buttons = [passButton, failButton];

    // Button to delete private key from disk.
    void delete() => _storage.delete(key: KEY);
    const Text clearKey = Text('CLEAR KEY', style: STYLE);
    final Widget clearButton = TextButton(onPressed: delete, child: clearKey);

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
        Row(mainAxisAlignment: MAIN_CENTER, children: <Widget>[clearButton]),
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
