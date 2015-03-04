library options;

import 'dart:async';
import 'dart:html';
import 'dart:js';

JsObject _runtime = context['chrome']['runtime'];

void main() {
  _runtime.callMethod('sendMessage', [null, new JsObject.jsify({
      'options': 'hostServer'
    }), null, _onOptionsResponse
  ]);
}

void _onOptionsResponse(JsObject response) {
  var input = new ServerInput(document, response['host'] as String, response['port'] as int);
  input.hostChanges.listen((host) {
    _runtime.callMethod('sendMessage', [null, new JsObject.jsify({
      'host': host
    })]);
  });
  input.portChanges.listen((port) {
    _runtime.callMethod('sendMessage', [null, new JsObject.jsify({
      'port': port
    })]);
  });
}

class ServerInput {
  static const _HOST_INPUT_ID = 'host-input';
  static const _PORT_INPUT_ID = 'port-input';
  static const _INPUT_ERROR_CLASSNAME = 'input-error';

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
    _hostOnInputHandler = _hostEl.onInput.listen(_handleHostInput);
    _portOnInputHandler = _portEl.onInput.listen(_handlePortInput);
    _handleHostInput('');
    _handlePortInput('');
  }

  void _handleHostInput(_) {
    if (_hostEl.value.length > 9) {
      _hostEl.style.width = '${_hostEl.value.length * 8.5}px';
    } else {
      _hostEl.style.width = '';
    }

    var host = _hostEl.value.trim();
    // Check for common errors. No reason to get crazy.
    if (host.length > 0 && !host.contains(' ') && !host.contains(':')) {
      _hostEl.classes.remove(_INPUT_ERROR_CLASSNAME);
      _hostChangesController.add(host);
    } else {
      _hostEl.classes.add(_INPUT_ERROR_CLASSNAME);
    }
  }

  void _handlePortInput(_) {
    var portNum = int.parse(_portEl.value, onError: (_) => 0);
    if (portNum > 0 && portNum <= 65535) {
      _portEl.classes.remove(_INPUT_ERROR_CLASSNAME);
      _portChangesController.add(portNum);
    } else {
      _portEl.classes.add(_INPUT_ERROR_CLASSNAME);
    }
  }
}
