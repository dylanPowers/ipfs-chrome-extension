library options;

import 'dart:async';
import 'dart:html';
import 'dart:js';

import 'settings.dart';

JsObject _permissions = context['chrome']['permissions'];
JsObject _runtime = context['chrome']['runtime'];

void main() async {
  var settings = new SettingsRemote(_runtime);
  var input = new ServerInput(document, settings);
}

class ServerInput {
  static const _HOST_INPUT_ID = 'host-input';
  static const _PERMS_BUTTON_ID = 'perms-button';
  static const _PORT_INPUT_ID = 'port-input';
  static const _INPUT_ERROR_CLASSNAME = 'input-error';
  static const _INPUT_WARN_CLASSNAME = 'input-warn';

  SettingsRemote settings;

  final InputElement _hostEl;
  StreamSubscription _hostOnInputHandler;
  final ButtonElement _permsButton;
  final InputElement _portEl;
  StreamSubscription _portOnInputHandler;

  ServerInput(HtmlDocument doc, this.settings) :
    _hostEl = doc.getElementById(_HOST_INPUT_ID),
    _permsButton = doc.getElementById(_PERMS_BUTTON_ID),
    _portEl = doc.getElementById(_PORT_INPUT_ID) {
    _setupInput();
  }

  void _setupInput() async {
    await settings.whenInitializationCompletes;
    _hostEl.value = settings.host;
    _portEl.value = settings.port.toString();
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
      _hostEl.style.width = '${(_hostEl.value.length + 1) * 8.5}px';
    } else {
      _hostEl.style.width = '';
    }

    var host = _hostEl.value.trim();
    // Check for common errors. No reason to get crazy.
    if (host.length > 0 && !host.contains(' ') && !host.contains(':')) {
      _hostEl.classes.remove(_INPUT_ERROR_CLASSNAME);
      _permissions.callMethod('contains', [new JsObject.jsify({
        'origins': ['http://$host/']
      }), (bool hasPermission) {
        if (hasPermission) {
          settings.submitHost(host);
          _hostEl.classes.remove(_INPUT_WARN_CLASSNAME);
        } else {
          _hostEl.classes.add(_INPUT_WARN_CLASSNAME);
        }
      }]);
    } else {
      _hostEl.classes.remove(_INPUT_WARN_CLASSNAME);
      _hostEl.classes.add(_INPUT_ERROR_CLASSNAME);
    }
  }

  void _handlePortInput(_) {
    var portNum = int.parse(_portEl.value, onError: (_) => 0);
    if (portNum > 0 && portNum <= 65535) {
      _portEl.classes.remove(_INPUT_ERROR_CLASSNAME);
      settings.submitPort(portNum);
    } else {
      _portEl.classes.add(_INPUT_ERROR_CLASSNAME);
    }
  }
}
