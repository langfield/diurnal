import 'dart:async';

const oneMinute = Duration(minutes: 1);

class DiurnalState extends State<Diurnal> {
  String? _key;

  Queue? _stack;
  Worksheet? _worksheet;

  int? _currentBlockIndex;
  Timer? _currentBlockTimer;
  List<Cell>? _currentBlock;

  @override
  void initState() {
    super.initState();
    readPrivateKey();
    Timer.periodic(oneMinute, (Timer t) => updateWorksheet());
  }

  // AWAITABLES

  Future<void> initWorksheet({required String key}) async {
    credentials = getCredentialsFromPrivateKey(key: key);
    gsheets = GSheets(credentials);
    _worksheet = gsheets.worksheet('Sheet1');
  }

  Future<void> updateWorksheet() async {
    if (_key == null) return;
    if (_worksheet == null) return;
    final List<List<Cell>> rows = await _worksheet.cells.allRows();
    _stack = getStackFromRows(rows);

    // This is not always at the top of stack.
    _currentBlockIndex = getCurrentBlockIndex();
    resetBlockTimer();
  }

  Future<void> readPrivateKey() async {
    final String? key = await storage.read(key: KEY);
    if (key == null) await Navigator.push(context, route);
    _key = await storage.read(key: KEY);
    await initWorksheet(key: _key!);
    await updateWorksheet();
    setState(() {});
  }

  Future<void> onTimerEnd() async {
    showNotification(_currentBlock);
    if (_currentBlockIndex == null) return;
    _currentBlockIndex += 1;
    resetBlockTimer();
  }

  Future<void> passOrFail({required double doneProportion}) async {
    if (_stack == null) return;
    if (_stack.length >= 1) _stack.pop();
    setState(() {});
  }

  // CALLABLES

  void resetBlockTimer() {
    if (_stack == null) return;
    if (_currentBlockIndex == null) return;
    if (_currentBlockIndex >= _stack.length) return;
    _currentBlock = _stack[_currentBlockIndex];
    if (_currentBlockTimer != null) _currentBlockTimer.dispose();
    final dur = Duration(_currentBlock[MINS]);
    _currentBlockTimer = Timer(duration: dur, onEnd: onTimerEnd));
  }

  @override
  Widget build(BuildContext context) {
    if (_stack == null) return consoleMessage('Fetching data...');
    if (_stack.length == 0) return consoleMessage('All done :)');
    final List<Cell> dueBlock = _stack[0];
    Widget timer = Text('00:00');
    if (_currentBlockIndex == 0 && _currentBlockTimer != null)
      timer = _currentBlockTimer;
    return timer;
  }
}
