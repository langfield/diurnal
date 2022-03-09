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

Widget handleFutureBuilderSnapshot(
    {required BuildContext context,
    required AsyncSnapshot<String> snapshot,
    required FlutterSecureStorage storage}) {
  if (snapshot.hasError) {
    return Text('Error: ${snapshot.error}');
  } else if (!snapshot.hasData) {
    return Text('Awaiting.');
  } else {
    final privateKey = snapshot.data;
    if (privateKey == '') {
      print('Private key not found, sending user to form route.');
      Future.microtask(() => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => PrivateKeyFormRoute(storage: storage)),
          ));
    }

    return Text('Built diurnal!');
  }
}

Widget printConsoleText({required BuildContext context, required String text}) {
  return MaterialApp(
    theme: getTheme(context: context),
    home: Scaffold(
      body: Text(text),
    ),
  );
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
  return gsheets;
}

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

// AWAITABLE HANDLERS

Widget handleCandidateKey(
    {required DiurnalState diurnal,
    required BuildContext context,
    required FlutterSecureStorage storage,
    required String candidateKey}) {
  if (candidateKey == '') {
    print('Private key not found, sending user to form route.');
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) => PrivateKeyFormRoute(storage: storage)),
    );
    return printConsoleText(context: context, text: 'Pushed to navigator.');
  } else {
    print('Got private key in handler.');
    return printConsoleText(context: context, text: 'Got private key.');
  }
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
      home: Diurnal(),
      theme: getTheme(context: context),
    );
  }
}

class Diurnal extends StatefulWidget {
  const Diurnal({Key? key}) : super(key: key);

  @override
  State<Diurnal> createState() => DiurnalState();
}

class DiurnalState extends State<Diurnal> {
  final storage = new FlutterSecureStorage();
  int numBuilds = 0;
  String privateKey = '';
  GSheets? gsheets;

  @override
  Widget build(BuildContext context) {
    print('Building Diurnal widget.');
    var now = DateTime.now();
    numBuilds += 1;
    print('Num builds: $numBuilds');

    print('Attempting to get private key from secure storage...');
    if (privateKey == '') {
      getPrivateKey(storage: storage).then((candidateKey) {
        handleCandidateKey(
            diurnal: this,
            context: context,
            storage: storage,
            candidateKey: candidateKey);
        privateKey = candidateKey;
        setState(() {});
      });
      return printConsoleText(context: context, text: 'Waiting for private key...');
    }

    if (this.gsheets == null) {
      print('Attempting to construct gsheets object.');
      getGSheets(storage: storage).then((GSheets? gsheets) {
        this.gsheets = gsheets;
        setState(() {});
      });
      if (this.gsheets == null) {
        return printConsoleText(
            context: context, text: 'Failed to get gsheets object.');
      }
    }
    return printConsoleText(
        context: context, text: 'Found existing private key and constructed gsheets object.');
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
