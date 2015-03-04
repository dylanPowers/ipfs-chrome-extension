library options;

import 'dart:async';
import 'dart:html';

void main() {
  var input = new ServerInput(document, "localhost", 8);
  input.hostChanges.listen((host) => print(host));
  input.portChanges.listen((port) => print(port));
}

class ServerInput {
  static const _HOST_INPUT_ID = 'host-input';
  static const _PORT_INPUT_ID = 'port-input';

  Stream<String> get hostChanges => _hostChangesController.stream;
  Stream<int> get portChanges => _portChangesController.stream;

  final _hostChangesController = new StreamController<String>();
  final InputElement _hostEl;
  StreamSubscription _hostOnInputHandler;
  final _portChangesController = new StreamController<int>();
  final InputElement _portEl;
  StreamSubscription _portOnInputHandler;

  ServerInput(HtmlDocument doc, String initialHostValue, int initialPortValue) :
    _hostEl = doc.getElementById(_HOST_INPUT_ID),
    _portEl = doc.getElementById(_PORT_INPUT_ID) {
    _hostEl.value = initialHostValue;
    _portEl.value = initialPortValue.toString();
    _setupListeners();
  }

  void _setupListeners() {
    _hostOnInputHandler = _hostEl.onInput.listen((e) {
      if (_hostEl.value.length > 9) {
        _hostEl.style.width = '${_hostEl.value.length * 8.5}px';
      } else {
        _hostEl.style.width = '';
      }
      _hostChangesController.add(_hostEl.value);
    });

    _portOnInputHandler = _portEl.onInput.listen((e) {
      var portNum = int.parse(_portEl.value, onError: (_) => 0);
      if (portNum > 0) {
        _portChangesController.add(portNum);
      }
    });
  }
}
