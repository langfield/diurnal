import 'dart:math';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_dartio/google_sign_in_dartio.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    bool isDesktop = Theme.of(context).platform == TargetPlatform.linux;

    // Try dartio sign in.
    if (isDesktop) {
      GoogleSignInDart.register(clientId: '');
    }

    return MaterialApp(
      home: const MyHomePage(),
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

  final _googleSignIn = GoogleSignIn(
    scopes: <String>[sheets.SheetsApi.spreadsheetsScope],
  );

  Future<void> _handleGetSheet() async {
    var client = await _googleSignIn.authenticatedClient();
    print('The client: $client');
    var httpClient = client!;
  }

  GoogleSignInAccount? _currentUser;

  // Initialize the state of the app.
  @override
  void initState() {
    super.initState();

    _googleSignIn.onCurrentUserChanged.listen((GoogleSignInAccount? account) {
      setState(() {
        _currentUser = account;
      });
      if (_currentUser != null) {
        _handleGetSheet();
      }
    });
    _googleSignIn.signIn();
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
                  onPressed: _handleGetSheet,
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
