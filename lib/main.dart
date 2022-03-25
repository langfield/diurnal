import 'dart:math';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import 'package:intl/intl.dart';
import 'package:rxdart/subjects.dart';
import 'package:gsheets/gsheets.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:flutter_countdown_timer/index.dart';
import 'package:background_fetch/background_fetch.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_native_timezone/flutter_native_timezone.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:diurnal/SECRETS.dart' as secrets;

// ignore_for_file: constant_identifier_names
// ignore_for_file: avoid_print
// ignore_for_file: unnecessary_brace_in_string_interps

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

// CONSTANTS

// Used as the key for the google service account private key in
// ``flutter_secure_storage``'s on-device key-value store.
const String KEY = 'PRIVATE_KEY';

// Character used to denote already-filled-out blocks. The 'pointer' location
// is the location of the latest block with this character.
const String POINTER_CHAR = '*';
const int BLOCK_WIDTH = 6;
const int DAY_WIDTH = 8;
const int DAY_HEIGHT = 74;

// 1-indexed, inclusive indices.
const int DAY_START_ROW = 2;
const int POINTER_COLUMN = 50;
const int POINTER_COLUMN_START_ROW = 1;
const int DAY_END_ROW = DAY_START_ROW + DAY_HEIGHT - 1;

// 0-indexed, day-relative column indices.
const int TITLE = 0;
const int DONE = 1;
const int WEIGHT = 2;
const int ACTUAL = 3;
const int MINS = 4;
const int LATE = 5;
const int POINTER = 6;
const int TIME = 7;

final DateTime berlinWallFellDate = DateTime.utc(1989, 11, 9);

/// SharedPreferences data key.
const EVENTS_KEY = "fetch_events";

const double FONT_SIZE = 15.0;

// Time allowed to pass since block end date before we automatically mark a
// block as FAILED.
const Duration LEEWAY = Duration(minutes: 1080);
const Duration ONE_MINUTE = Duration(minutes: 1);
const Duration THIRTY_SECS = Duration(seconds: 30);

const TextStyle STYLE = TextStyle(fontSize: FONT_SIZE, color: Colors.white);
const TextStyle YELLOW = TextStyle(fontSize: FONT_SIZE, color: Colors.yellow);
const BorderRadius RADIUS = BorderRadius.all(Radius.circular(0.0));
const Color TRANSLUCENT_RED = Color.fromRGBO(255, 0, 0, 0.7);
const Color TRANSLUCENT_WHITE = Color.fromRGBO(255, 255, 255, 0.7);

// Used to style to google service account private key form.
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
const CrossAxisAlignment CROSS_END = CrossAxisAlignment.end;
const MainAxisAlignment MAIN_CENTER = MainAxisAlignment.center;
const MainAxisAlignment MAIN_BETWEEN = MainAxisAlignment.spaceBetween;

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

/// Streams are created so that app can respond to notification-related events
/// since the plugin is initialised in the `main` function.
final BehaviorSubject<ReceivedNotification> didReceiveLocalNotificationSubject =
    BehaviorSubject<ReceivedNotification>();

final BehaviorSubject<String?> selectNotificationSubject =
    BehaviorSubject<String?>();

class ReceivedNotification {
  ReceivedNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.payload,
  });

  final int id;
  final String? title;
  final String? body;
  final String? payload;
}

String? selectedNotificationPayload;

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

// FUNCTIONS

/// Initialize things and run main app, starting with the ``TopLevel`` widget.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Timezone initialization boilerplate for scheduling notifications.
  final String? timeZoneName = await FlutterNativeTimezone.getLocalTimezone();
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation(timeZoneName!));

  // Run the main app.
  runApp(const TopLevel());

  // Register to receive BackgroundFetch events after app is terminated.
  // Requires {stopOnTerminate: false, enableHeadless: true}.
  BackgroundFetch.registerHeadlessTask(backgroundFetchHeadlessTask);
}

/// This "Headless Task" is run when app is terminated. It currently does
/// nothing.
void backgroundFetchHeadlessTask(HeadlessTask task) async {
  var taskId = task.taskId;
  var timeout = task.timeout;
  if (timeout) {
    print("[BackgroundFetch] Headless task timed-out: $taskId");
    BackgroundFetch.finish(taskId);
    return;
  }

  print("[BackgroundFetch] Headless event received: $taskId");
  var timestamp = DateTime.now();
  var prefs = await SharedPreferences.getInstance();

  // Read ``fetch_events`` from SharedPreferences.
  var events = <String>[];
  var json = prefs.getString(EVENTS_KEY);
  if (json != null) {
    events = jsonDecode(json).cast<String>();
  }

  // Add new event.
  events.insert(0, "$taskId@$timestamp [Headless]");

  // Persist fetch events in SharedPreferences.
  prefs.setString(EVENTS_KEY, jsonEncode(events));

  if (taskId == 'flutter_background_fetch') {
    // TODO: THIS IS WHERE WE SHOULD PUT NOTIFICATION SCHEDULING LOGIC.
  }
  BackgroundFetch.finish(taskId);
}

/// Get a border for the google service account private key form.
OutlineInputBorder getOutlineInputBorder({required Color color}) {
  return OutlineInputBorder(
    borderRadius: RADIUS,
    borderSide: BorderSide(color: color, width: 2.0),
  );
}

/// Get global Scaffold theme.
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

/// Validate private key by attempting to construct ``GSheets`` instance.
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

/// Filter-out empty blocks and completed blocks.
List<List<Cell>> filterRows({required List<List<Cell>> rows}) {
  rows = rows.where((block) => !blockHasEmptyFields(block: block)).toList();
  rows = rows.where((block) => !isDone(block: block)).toList();
  return rows;
}

/// Return true if any block cells (so not the pointer column or the time
/// column) are empty strings.
bool blockHasEmptyFields({required List<Cell> block}) {
  for (final Cell cell in block.sublist(0, BLOCK_WIDTH)) {
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
  Cell daysCell = block[TIME];
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
    final List<Cell> nextBlock = rows[i + 1];
    final int rowIndex = block[TITLE].row;

    DateTime blockEndTime = getBlockEndTime(block: block, now: now);
    DateTime nextBlockEndTime = getBlockEndTime(block: nextBlock, now: now);
    final DateTime blockEndTimeWithLeeway = blockEndTime.add(LEEWAY);
    final List<DateTime> dates = [blockEndTimeWithLeeway, nextBlockEndTime];

    // Take maximum of end time plus leeway and next end time.
    final deadline = dates.reduce((a, b) => a.isAfter(b) ? a : b);
    if (deadline.isBefore(now)) {
      print('Moving new pointer to: ${block[TITLE].value}');
      newPtr = rowIndex;
    }
  }
  return newPtr;
}

List<List<Cell>> getStackFromRows(
    {required List<List<Cell>> rows, required int ptr}) {
  print('Getting stack from rows...');
  print('Rows size: ${rows.length}');
  print('Looking for ptr: ${ptr}');
  final List<List<Cell>> stack = [];
  for (int i = 0; i < rows.length; i++) {
    final String title = rows[i][TITLE].value;
    print('Checking block: ${title}');
    final int row = rows[i][TITLE].row;
    if (row >= ptr + 1) {
      print('Found row: ${row} >= ptr + 1: ${ptr + 1}');
      print('Populating stack starting with block: ${rows[i][TITLE].value}');
      stack.addAll(rows.sublist(i, rows.length));
      return stack;
    }
  }
  print('Returning empty stack.');
  return stack;
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
        padding: EdgeInsets.all(0.1 * min(width, height)),
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

  List<List<Cell>>? _stack;
  Worksheet? _worksheet;

  int? _currentBlockIndex;
  CountdownTimer? _currentBlockTimer;
  CountdownTimerController? _timerController;
  List<Cell>? _currentBlock;
  FlutterLocalNotificationsPlugin? _notifications;

  // INITIALIZED STATE

  int _localPtr = 0;
  int _numBuilds = 0;
  final _storage = const FlutterSecureStorage();
  List<String> _events = [];
  DateTime _lastUpdateTime = berlinWallFellDate;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _configureDidReceiveLocalNotificationSubject();
    _configureSelectNotificationSubject();
    readPrivateKey();
    _notifications = getNotificationsPlugin();
    updateWorksheet();
    initPlatformState();
    Future.delayed(const Duration(seconds: 10), () {
      Timer.periodic(THIRTY_SECS, (Timer t) => updateWorksheet());
    });
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

    // If we have already made at least one update, and the day of the month
    // has changed since the last update (i.e. the hour of midnight occurred
    // between the last update and the current time), then we reset
    // ``_localPtr`` to 0.
    if (_lastUpdateTime != berlinWallFellDate &&
        _lastUpdateTime.day != now.day) {
      _localPtr = 0;
    }
    _lastUpdateTime = now;

    // Update remote pointer.
    // HTTP GET REQUEST.
    _stack = await getStack(now: now);

    // This is not always at the top of stack.
    _currentBlockIndex = getCurrentBlockIndex(now: now);
    print('Set current block index: ${_currentBlockIndex}');
    resetBlockTimer();
    scheduleNotifications();
    setState(() {});
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
    print('HANDLING TIMER END EVENT...');
    if (_currentBlock == null) return;
    if (_currentBlockIndex == null) return;
    var msg = 'Incrementing _currentBlockIndex: ';
    var incremMsg = '${_currentBlockIndex} -> ${_currentBlockIndex! + 1}';
    print('${msg}${incremMsg}');
    _currentBlockIndex = _currentBlockIndex! + 1;
    resetBlockTimer();
    WidgetsBinding.instance?.addPostFrameCallback((_) {
      setState(() {});
    });
  }

  Future<void> scheduleNotifications() async {
    if (_currentBlock == null) {
      print('Not scheduling notifications as _currentBlock is null');
      return;
    }
    if (_currentBlockIndex == null) {
      print('Not scheduling notifications as _currentBlockIndex is null');
      return;
    }

    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails('your channel id', 'your channel name',
            channelDescription: 'your channel description',
            importance: Importance.max,
            priority: Priority.max,
            ticker: 'ticker');
    const IOSNotificationDetails iOSPlatformChannelSpecifics =
        IOSNotificationDetails();
    const MacOSNotificationDetails macOSPlatformChannelSpecifics =
        MacOSNotificationDetails();
    const NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS: iOSPlatformChannelSpecifics,
        macOS: macOSPlatformChannelSpecifics);

    await _notifications!.cancelAll();

    for (int i = _currentBlockIndex!; i < _stack!.length; i++) {
      final List<Cell> block = _stack![i];

      if (block.isEmpty) continue;
      final String title = block[TITLE].value;
      final String mins = block[MINS].value;
      final String body = '${mins}m: ${title}';

      final now = DateTime.now();
      final DateTime blockStartTime = getBlockStartTime(block: block, now: now);
      final notificationDateTime = tz.TZDateTime.from(blockStartTime, tz.local);

      if (blockStartTime.isBefore(now)) continue;

      print('Scheduling notification: ${body} at ${notificationDateTime}');
      await _notifications!.zonedSchedule(
          i, 'Diurnal', body, notificationDateTime, platformChannelSpecifics,
          androidAllowWhileIdle: true,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime);
    }
  }

  Future<void> passOrFail({required double score}) async {
    if (_stack == null) return;
    if (_stack!.isEmpty) return;
    final List<Cell> concludedBlock = _stack!.removeAt(0);
    _localPtr = max(_localPtr, concludedBlock[TITLE].row);
    print('Set local pointer to ${_localPtr}');

    // Decrement index because we popped from the stack.
    if (_currentBlockIndex != null && _currentBlockIndex! >= 1) {
      var msg = 'Decrementing _currentBlockIndex: ';
      var decremMsg = '${_currentBlockIndex} -> ${_currentBlockIndex! - 1}';
      print('${msg}${decremMsg}');
      _currentBlockIndex = _currentBlockIndex! - 1;
    }

    resetBlockTimer();
    setState(() {});
    final Cell doneCell = concludedBlock[DONE];

    // HTTP POST REQUEST.
    doneCell.post(score);
  }

  // TODO: Is it still necessary to refresh from ``PrivateKeyFormRoute``?
  Future<void> pushFormRoute() async {
    final route = MaterialPageRoute(
        builder: (BuildContext context) =>
            PrivateKeyFormRoute(storage: _storage, refresh: _refresh));
    await Navigator.push(context, route);
  }

  Future<List<List<Cell>>> getStack({required DateTime now}) async {
    print('Getting stack...');
    // HTTP GET REQUEST.
    List<List<Cell>> rows = await getRows(now: now);
    List<List<Cell>>? nonemptys =
        rows.where((block) => !blockHasEmptyFields(block: block)).toList();
    rows = filterRows(rows: rows);
    // HTTP GET REQUEST.
    final int oldPtr = await getPointer(now: now);
    int newPtr = computeNewPointer(rows: nonemptys, now: now);
    newPtr = max(oldPtr, newPtr);
    newPtr = max(newPtr, _localPtr);
    print('oldPtr: ${oldPtr}  newPtr: ${newPtr}');
    // HTTP GET REQUEST.
    if (oldPtr < newPtr) await setPointer(ptr: newPtr, now: now);
    List<List<Cell>> stack = getStackFromRows(rows: rows, ptr: newPtr);
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

  Future<int> getPointer({required DateTime now}) async {
    final int startColumn = ((now.weekday - 1) * DAY_WIDTH) + 1;
    final int pointerColumn = startColumn + POINTER;

    // HTTP GET REQUEST.
    final List<Cell>? column = await _worksheet!.cells.column(pointerColumn,
        fromRow: POINTER_COLUMN_START_ROW, length: DAY_HEIGHT);

    // Iterate bottom-up to find the last starred row.
    for (final Cell cell in column!.reversed.toList()) {
      if (cell.value == '*') {
        return cell.row;
      }
    }

    // If there are none, we return the top row.
    return POINTER_COLUMN_START_ROW;
  }

  Future<void> setPointer({required int ptr, required DateTime now}) async {
    final int startColumn = ((now.weekday - 1) * DAY_WIDTH) + 1;
    final int pointerColumn = startColumn + POINTER;

    // HTTP GET REQUEST.
    await _worksheet!.clearColumn(pointerColumn,
        fromRow: POINTER_COLUMN_START_ROW, length: DAY_HEIGHT);
    for (int i = POINTER_COLUMN_START_ROW; i <= ptr; i++) {
      // HTTP GET REQUEST.
      Cell newPointer =
          await _worksheet!.cells.cell(row: i, column: pointerColumn);
      // HTTP GET REQUEST.
      await newPointer.post(POINTER_CHAR);
    }
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    // Load persisted fetch events from SharedPreferences
    var prefs = await SharedPreferences.getInstance();
    var json = prefs.getString(EVENTS_KEY);
    if (json != null) {
      setState(() {
        _events = jsonDecode(json).cast<String>();
      });
    }

    // Configure BackgroundFetch.
    try {
      var status = await BackgroundFetch.configure(
          BackgroundFetchConfig(
            minimumFetchInterval: 15,
            stopOnTerminate: false,
            enableHeadless: true,
            requiresBatteryNotLow: false,
            requiresCharging: false,
            requiresStorageNotLow: false,
            requiresDeviceIdle: false,
            /*
        forceAlarmManager: false,
        startOnBoot: true,
        requiredNetworkType: NetworkType.NONE,

         */
          ),
          _onBackgroundFetch,
          _onBackgroundFetchTimeout);
      print('[BackgroundFetch] configure success: $status');
      setState(() {});
    } on Exception catch (e) {
      print("[BackgroundFetch] configure ERROR: $e");
    }

    // If the widget was removed from the tree while the asynchronous platform
    // message was in flight, we want to discard the reply rather than calling
    // setState to update our non-existent appearance.
    if (!mounted) return;
  }

  void _onBackgroundFetch(String taskId) async {
    var prefs = await SharedPreferences.getInstance();
    var timestamp = DateTime.now();
    // This is the fetch-event callback.
    print("[BackgroundFetch] Event received: $taskId");
    setState(() {
      _events.insert(0, "$taskId@${timestamp.toString()}");
    });
    // Persist fetch events in SharedPreferences
    prefs.setString(EVENTS_KEY, jsonEncode(_events));

    if (taskId == "flutter_background_fetch") {
      // TODO: PUT NOTIFICATION SCHEDULNG LOGIC HERE.
      await updateWorksheet();
    }
    // IMPORTANT:  You must signal completion of your fetch task or the OS can punish your app
    // for taking too long in the background.
    BackgroundFetch.finish(taskId);
  }

  /// This event fires shortly before your task is about to timeout.  You must
  /// finish any outstanding work and call BackgroundFetch.finish(taskId).
  void _onBackgroundFetchTimeout(String taskId) {
    print("[BackgroundFetch] TIMEOUT: $taskId");
    BackgroundFetch.finish(taskId);
  }

  // METHODS

  // TODO: Should ``now`` be passed as an argument?
  void resetBlockTimer() {
    if (_stack == null) {
      print('Returning early from resetBlockTimer() because _stack is null.');
      return;
    }
    if (_currentBlockIndex == null) {
      print(
          'Returning early from resetBlockTimer() because _currentBlockIndex is null.');
      return;
    }
    print('Current block index: ${_currentBlockIndex}');
    if (_currentBlockIndex! >= _stack!.length) return;
    _currentBlock = _stack![_currentBlockIndex!];

    final now = DateTime.now();
    final List<Cell> block = _currentBlock!;
    final DateTime blockEndTime = getBlockEndTime(block: block, now: now);
    final DateTime timerEnd = getTimerEnd(end: blockEndTime, now: now);
    final int msEndTime = timerEnd.millisecondsSinceEpoch;

    print('SETTING TIMER FOR BLOCK: ${block[TITLE].value}');
    if (_timerController == null) {
      print('NEW TIMER INSTANTIATED TO: ${timerEnd.toLocal()}');
      _timerController =
          CountdownTimerController(endTime: msEndTime, onEnd: onTimerEnd);
      _currentBlockTimer = CountdownTimer(controller: _timerController);
    } else {
      print('Timer endTime updated to: ${timerEnd.toLocal()}');
      _timerController!.endTime = msEndTime;
    }
  }

  int? getCurrentBlockIndex({required DateTime now}) {
    for (int i = 0; i < _stack!.length; i++) {
      final List<Cell> block = _stack![i];
      DateTime blockEndTime = getBlockEndTime(block: block, now: now);
      if (now.isBefore(blockEndTime)) return i;
    }
    print(
        'WARNING: Couldn\'t find current block in stack of size ${_stack!.length}. Is the day over?');
    return null;
  }

  FlutterLocalNotificationsPlugin getNotificationsPlugin() {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('app_icon');

    /// Note: permissions aren't requested here just to demonstrate that can be
    /// done later
    final IOSInitializationSettings initializationSettingsIOS =
        IOSInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
            onDidReceiveLocalNotification: (
              int id,
              String? title,
              String? body,
              String? payload,
            ) async {
              didReceiveLocalNotificationSubject.add(
                ReceivedNotification(
                  id: id,
                  title: title,
                  body: body,
                  payload: payload,
                ),
              );
            });

    const MacOSInitializationSettings initializationSettingsMacOS =
        MacOSInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    final LinuxInitializationSettings initializationSettingsLinux =
        LinuxInitializationSettings(
      defaultActionName: 'Open notification',
      defaultIcon: AssetsLinuxIcon('icons/app_icon.png'),
    );

    final InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
      macOS: initializationSettingsMacOS,
      linux: initializationSettingsLinux,
    );

    flutterLocalNotificationsPlugin.initialize(initializationSettings,
        onSelectNotification: (String? payload) async {
      if (payload != null) {
        debugPrint('notification payload: $payload');
      }
      selectedNotificationPayload = payload;
      selectNotificationSubject.add(payload);
    });

    return flutterLocalNotificationsPlugin;
  }

  void _requestPermissions() {
    flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
    flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
  }

  void _configureDidReceiveLocalNotificationSubject() {
    didReceiveLocalNotificationSubject.stream
        .listen((ReceivedNotification receivedNotification) async {
      await showDialog(
        context: context,
        builder: (BuildContext context) => CupertinoAlertDialog(
          title: receivedNotification.title != null
              ? Text(receivedNotification.title!)
              : null,
          content: receivedNotification.body != null
              ? Text(receivedNotification.body!)
              : null,
          actions: <Widget>[
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () async {
                Navigator.of(context, rootNavigator: true).pop();
                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) => const Diurnal(),
                  ),
                );
              },
              child: const Text('Ok'),
            )
          ],
        ),
      );
    });
  }

  void _configureSelectNotificationSubject() {
    selectNotificationSubject.stream.listen((String? payload) async {
      await Navigator.pushNamed(context, '/secondPage');
    });
  }

  @override
  void dispose() {
    didReceiveLocalNotificationSubject.close();
    selectNotificationSubject.close();
    super.dispose();
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

    Widget dueTimer = const Text('00:00:00', style: YELLOW);
    Widget currentTimer = const Text('00:00:00');

    if (_currentBlockTimer != null) {
      currentTimer = _currentBlockTimer!;
      if (_currentBlockIndex == 0) {
        dueTimer = _currentBlockTimer!;
      } else {
        print('_currentBlockIndex: ${_currentBlockIndex}');
        print('_currentBlockTimer: ${_currentBlockTimer}');
        print('Using zeroed-out timer :(');
      }
    } else {
      print('WARNING: _currentBlockTimer is null!');
    }

    final List<Cell> block = _stack!.first;

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
    final Widget builds = Text('Builds: ${_numBuilds}', style: YELLOW);
    final Widget blockTimes = Text('${blockStartStr} -> ${blockEndStr}');

    final int hourOffset = now.timeZoneOffset.inHours;
    String offset = '${hourOffset}';
    if (hourOffset >= 0) offset = '+${offset}';
    final Widget timezone = Text('${now.timeZoneName}');
    final Widget gmtOffset = Text('GMT${offset}');
    final List<Widget> blockTimeWidgets = [blockTimes, gmtOffset, timezone];

    final List<Widget> leftBlockWidgets = [blockTitle, blockProps, builds];

    final Widget leftBlockColumn =
        Column(crossAxisAlignment: CROSS_START, children: leftBlockWidgets);
    final Widget rightBlockColumn =
        Column(crossAxisAlignment: CROSS_END, children: blockTimeWidgets);

    final expandedLeft = Expanded(child: leftBlockColumn);
    final List<Widget> blockColumns = [expandedLeft, rightBlockColumn];

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
        Row(mainAxisAlignment: MAIN_CENTER, children: <Widget>[dueTimer]),
        Visibility(child: currentTimer, visible: false, maintainState: true),
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
    var paddedForm =
        Padding(padding: const EdgeInsets.only(top: 100.0), child: expForm);
    var formColumn = Column(children: <Widget>[paddedForm, expSubmitButton]);

    return Scaffold(body: formColumn);
  }
}
