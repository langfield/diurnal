import 'dart:math';
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:intl/intl.dart';
import 'package:gsheets/gsheets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_countdown_timer/flutter_countdown_timer.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:diurnal/SECRETS.dart' as secrets;

const oneMinute = Duration(minutes: 1);

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

// FUNCTIONS

// Run the main app.
void main() {
  runApp(const TopLevel());
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

String getGSheets({required String privateKey}) {
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
    final String _ = getGSheets(privateKey: privateKey);
    return true;
  } on ArgumentError catch (e) {
    print('Caught error: $e');
    return false;
  }
}

List<List<Cell>> filterRows({required List<List<Cell>> rows) {
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
    final DateTime nextBlockEndTime = getBlockEndTime(block: nextBlock, now: now);
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

Queue<List<Cell>> getStackFromRows({required List<List<Cell>> rows, required int ptr}) {
  for (final int i = 0; i < rows.length - 1; i++) {
    final int row = rows[i][TITLE].row;
    if (row == ptr) return Queue().addAll(rows[i + 1:rows.length]);
  }
  return Queue();
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
  return flutterLocalNotificationsPlugin;
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
  Timer? _currentBlockTimer;
  List<Cell>? _currentBlock;
  FlutterLocalNotificationsPlugin? _notifications;

  // INITIALIZED STATE

  bool _invalidPrivateKey = false;
  final _storage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    readPrivateKey();
    _notifications = getNotificationsPlugin();
    Timer.periodic(oneMinute, (Timer t) => updateWorksheet());
  }

  void _refresh() {
    setState(() {});
  }

  // AWAITABLE METHODS

  Future<void> initWorksheet({required String key}) async {
    if (!isValidPrivateKey(privateKey: privateKey)) {
      _invalidPrivateKey = true;
      return null;
    }
    final gsheets = getGSheets(privateKey: privateKey);
    final ss = await gsheets.spreadsheet(secrets.ssid);
    _worksheet = ss.worksheetByTitle('Sheet1');
  }

  Future<void> updateWorksheet() async {
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
    final String? key = await _storage.read(key: KEY);
    if (key == null) await pushFormRoute();
    _key = await _storage.read(key: KEY);
    await initWorksheet(key: _key!);
    await updateWorksheet();
    setState(() {});
  }

  Future<void> onTimerEnd() async {
    if (_currentBlock == null) return;
    if (_currentBlockIndex == null) return;
    showNotification(block: _currentBlock);
    _currentBlockIndex += 1;
    resetBlockTimer();
  }

  Future<void> showNotification({required List<Cell> block}) async {
    String body = 'All done for today :)';
    if (block.isNotEmpty) body = block[TITLE].value;
    await _notifications!.show(0, 'Diurnal', body, DETAILS, payload: 'LOAD');
  }


  Future<void> passOrFail({required double doneProportion}) async {
    if (_stack == null) return;
    if (_stack.length >= 1) _stack.pop();
    setState(() {});
  }

  // TODO: Is it still necessary to refresh from ``PrivateKeyFormRoute``?
  Future<void> pushFormRoute() async {
    final route = MaterialPageRoute(
        builder: (BuildContext context) =>
            PrivateKeyFormRoute(storage: _storage, refresh: _refresh));
    await Navigator.push(context, route);
  }

  Future<Queue<List<Cell>>> getStack({required DateTime now}) async {
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
    List<List<Cell>> rows = await _worksheet.cells.allRows(
        fromRow: DAY_START_ROW,
        fromColumn: startColumn,
        length: DAY_WIDTH,
        count: DAY_HEIGHT);
    return rows;
  }

  Future<int> getPointer() async {
    // HTTP GET REQUEST.
    final List<Cell>? column = await _worksheet.cells.column(POINTER_COLUMN,
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
    await _worksheet.clearColumn(POINTER_COLUMN,
        fromRow: POINTER_COLUMN_START_ROW, length: DAY_HEIGHT);
    // HTTP GET REQUEST.
    Cell newPointer =
        await sheet.cells.cell(row: ptr, column: POINTER_COLUMN);
    // HTTP GET REQUEST.
    await newPointer.post(POINTER);
  }

  // METHODS

  void resetBlockTimer() {
    if (_stack == null) return;
    if (_currentBlockIndex == null) return;
    if (_currentBlockIndex >= _stack.length) return;
    _currentBlock = _stack[_currentBlockIndex];
    if (_currentBlockTimer != null) _currentBlockTimer.dispose();
    final duration = Duration(_currentBlock[MINS]);
    _currentBlockTimer = Timer(duration: duration, onEnd: onTimerEnd));
  }

  int? getCurrentBlockIndex({required DateTime now}) {
    for (final int i = 0; i < _stack.length; i++) {
      final Cell block = _stack[i];
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
    if (_stack == null) return consoleMessage('Fetching data...');
    if (_worksheet == null) return consoleMessage('Null worksheet :(');
    if (_stack.length == 0) return consoleMessage('All done :)');
    final List<Cell> dueBlock = _stack[0];
    Widget timer = Text('00:00');
    if (_currentBlockIndex == 0 && _currentBlockTimer != null)
      timer = _currentBlockTimer;
    return timer;
  }
}
