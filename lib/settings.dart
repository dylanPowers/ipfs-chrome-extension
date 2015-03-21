/**
 * Runtime messages:
 *
 * 'setting-submit': {
 *    'name': String
 *    'location': 'LOCAL' or 'CLOUD'
 *    'value': dynamic
 * }
 *
 * 'settings-client-init': void
 *
 * 'setting-change': {
 *    'name': String
 *    'old-value': dynamic
 *    'value': dynamic
 * }
 *
 * This entire file of code has no tests when it really should. Some of the
 * code has gotten a bit complex.
 */
library settings;

import 'dart:async';
import 'dart:js';

import 'package:ipfs_gateway_redirect/chrome_help.dart';
import 'package:observe/observe.dart';
import 'package:observe/mirrors_used.dart';

abstract class MsgKeys {
  static const SETTING_CHANGE = 'setting-change';
  static const SETTING_SUBMIT = 'setting-submit';
  static const SETTING_SUBMIT_RESULT = 'setting-submit-result';
  static const SETTINGS_CLIENT_INIT = 'settings-client-init';
}

typedef void SettingKVLoopFunc(String key, dynamic val);
typedef void RuntimeCallback(JsObject response);

class Settings extends ChangeNotifier {
  static const ERROR_UNKNOWN_KEYNAME = 'Unknown keyname';

  /*
    Couldn't get the observe transformer to work on these, so I had to manually
    create the @reflectable behavior :(
   */

  bool _allowAll = false;
  @reflectable get allowAll => _allowAll;
  @reflectable set allowAll(val) {
    _allowAll = notifyPropertyChange(#allowAll, _allowAll, val);
  }

  bool _allowFile = false;
  @reflectable get allowFile => _allowFile;
  @reflectable set allowFile(val) {
    _allowFile = notifyPropertyChange(#allowFile, _allowFile, val);
  }

  bool _allowHttp = false;
  @reflectable get allowHttp => _allowHttp;
  @reflectable set allowHttp(val) {
    _allowHttp = notifyPropertyChange(#allowHttp, _allowHttp, val);
  }

  String _host = 'localhost';
  @reflectable get host => _host;
  @reflectable set host(val) {
    _host = notifyPropertyChange(#host, _host, val);
  }

  int _port = 8080;
  @reflectable get port => _port;
  @reflectable set port(val) {
    _port = notifyPropertyChange(#port, _port, val);
  }

  Stream<List<PropertyChangeRecord>> get changes => super.changes;

  Settings();

  Settings.copy(Settings settings) {
    allowAll = settings.allowAll;
    allowFile = settings.allowFile;
    allowHttp = settings.allowHttp;
    host = settings.host;
    port = settings.port;
  }

  Settings.fromJSObj(JsObject settings) {
    jsObjForEach(settings, set);
  }

  bool operator ==(Settings other) {
    return allowAll == other.allowAll &&
           allowFile == other.allowFile &&
           allowHttp == other.allowHttp &&
           host == other.host &&
           port == other.port;
  }

  dynamic get(String name) {
    if (name == 'allow-all') {
      return allowAll;
    } else if (name == 'allow-file') {
      return allowFile;
    } else if (name == 'allow-http') {
      return allowHttp;
    } else if (name == 'host') {
      return host;
    } else if (name == 'port') {
      return port;
    }

    throw ERROR_UNKNOWN_KEYNAME;
  }

  static void jsObjForEach(JsObject settings, SettingKVLoopFunc action) {
    action('allow-all', settings['allow-all']);
    action('allow-file', settings['allow-file']);
    action('allow-http', settings['allow-http']);
    action('host', settings['host']);
    action('port', settings['port']);
  }

  void set(String name, dynamic value) {
    if (value != null) {
      if (name == 'allow-all') {
        allowAll = value as bool;
      } else if (name == 'allow-file') {
        allowFile = value as bool;
      } else if (name == 'allow-http') {
        allowHttp = value as bool;
      } else if (name == 'host') {
        host = value as String;
      } else if (name == 'port') {
        port = value as int;
      }
    } else {
      throw ERROR_UNKNOWN_KEYNAME;
    }
  }

  Map toMap() {
    return {
      'allow-all': allowAll,
      'allow-file': allowFile,
      'allow-http': allowHttp,
      'host': host,
      'port': port
    };
  }
}


abstract class ChromeSettings {
  Settings _settings = new Settings();
  bool get allowAll => _settings.allowAll;
  bool get allowFile => _settings.allowFile;
  bool get allowHttp => _settings.allowHttp;
  String get host => _settings.host;
  int get port => _settings.port;
  String get server => 'http://$host:$port';
  get changes => _settings.changes;
  get serverChanges => _settings.changes.transform(new StreamTransformer.fromHandlers(handleData:
    (List<PropertyChangeRecord> records, EventSink<List<PropertyChangeRecord>> sink) {
      var transformedRecords = [];
      records.forEach((record) {
        if (record.name == #port || record.name == #host) {
          transformedRecords.add(record);
        }
      });
      if (transformedRecords.length > 0) {
        sink.add(transformedRecords);
      }
  }));

  final JsObject chromeRuntime;
  ChromeSettings(this.chromeRuntime) {
    addListenerToChromeEvent(chromeRuntime, 'onMessage', _handleRuntimeMsg);
  }

  void _handleRuntimeMsg(JsObject msg, JsObject sender, JsFunction response);
  void _sendRuntimeMsg(Map msg, RuntimeCallback callback) {
    chromeRuntime.callMethod('sendMessage', [
          null,
          new JsObject.jsify(msg),
          null,
          callback
        ]);
  }
}


/**
 * The Core listens for the runtime messages
 * 'setting-submit'
 * 'settings-client-init'
 *
 * The Core emits the runtime messages
 * 'setting-change'
 * 'setting-submit-result'
 */
class SettingsCore extends ChromeSettings {
  JsObject chromePermissions;
  JsObject chromeStorage;

  SettingsCore(this.chromePermissions,
               JsObject chromeRuntime,
               this.chromeStorage) : super(chromeRuntime) {

    chromeStorage['local'].callMethod('get', [
        new JsObject.jsify([
            'allow-all', 'allow-file', 'allow-http', 'host', 'port'
        ]),
        (JsObject settings) {
          _submitSettings(settings).then((result) {
            if (!result) {
              // Commit as is on failure
              chromeStorage['local'].callMethod('set', [new JsObject.jsify(_settings.toMap())]);
            }
          });
        }
    ]);
  }

  void _applySetting(String settingName, dynamic value) {
    var oldVal = _settings.get(settingName);
    _settings.set(settingName, value);
    chromeStorage['local'].callMethod('set', [new JsObject.jsify({settingName: value})]);
    _sendSettingChangeMsg(settingName, value, oldVal);
  }

  void _handleRuntimeMsg(JsObject msg, JsObject sender, JsFunction response) {
    if (msg.hasProperty(MsgKeys.SETTING_SUBMIT)) {
      var newSetting = msg[MsgKeys.SETTING_SUBMIT];

      // Chrome extensions are retarded. No asynchronous callbacks allowed
      // causing await to bork things
      _submitSetting(newSetting['name'], newSetting['value']).then((success) {
        _sendRuntimeMsg({ MsgKeys.SETTING_SUBMIT_RESULT: success }, (_) {});
      });
    } else if (msg.hasProperty(MsgKeys.SETTINGS_CLIENT_INIT)) {
      response.apply([new JsObject.jsify(_settings.toMap())]);
    }
  }

  List<String> _requestedOrigins(Settings settings) {
    var origins = ['http://${settings.host}/*'];
    if (settings.allowAll) {
      origins = ['<all_urls>'];
    } else {
      if (settings.allowFile) {
        origins.addAll(['file:///ipfs/*', 'file:///ipns/*']);
      }

      if (settings.allowHttp) {
        origins.add('http://*/*');
      }
    }

    return origins;
  }

  bool _requestPermissions(Settings settings) async {
    var origins = _requestedOrigins(settings);
    var completer = new Completer<bool>();
    chromePermissions.callMethod('request', [
        new JsObject.jsify({ 'origins': origins }),
        completer.complete
    ]);
    return completer.future;
  }

  void _sendSettingChangeMsg(String name, dynamic newValue, dynamic oldValue) {
    _sendRuntimeMsg({
      MsgKeys.SETTING_CHANGE: {
        'name': name,
        'value': newValue,
        'old-value': oldValue
      }
    }, (_){});
  }

  bool _submitSetting(String settingName, dynamic value) async {
    var newSettings = new Settings.copy(_settings);
    newSettings.set(settingName, value);
    if (newSettings != _settings && await _requestPermissions(newSettings)) {
      _applySetting(settingName, value);
      return true;
    }

    return false;
  }

  bool _submitSettings(JsObject settingsJs) async {
    Settings newSettings;
    try {
      newSettings = new Settings.fromJSObj(settingsJs);
    } catch (e) {
      return false;
    }

    _requestPermissions(newSettings);
    var origins = _requestedOrigins(newSettings);
    var permsVerifyTask = new Completer<bool>();
    chromePermissions.callMethod('contains', [new JsObject.jsify({
      'origins': origins
    }), (bool hasPermission) {
      if (hasPermission) {
        Settings.jsObjForEach(settingsJs, _applySetting);
      }
      permsVerifyTask.complete(hasPermission);
    }]);

    return await permsVerifyTask.future;
  }
}


/**
 * The Remote listens for the runtime messages
 * 'setting-change'
 * 'setting-submit-result'
 *
 * The Remote emits the runtime messages
 * 'setting-submit'
 * 'settings-client-init'
 */
class SettingsRemote extends ChromeSettings {
  final _initCompleter = new Completer();
  Future get whenInitializationCompletes async => _initCompleter.future;

  var _submissionCompleter = new Completer()..complete();
  Future _taskChain;

  bool submitAllowAll(bool flag) async {
    return _submitSetting('allow-all', flag);
  }

  bool submitAllowFile(bool flag) async {
    return _submitSetting('allow-file', flag);
  }

  bool submitAllowHttp(bool flag) async {
    return _submitSetting('allow-http', flag);
  }

  bool submitHost(String host) async {
    return _submitSetting('host', host);
  }

  bool submitPort(int port) async {
    return _submitSetting('port', port);
  }

  SettingsRemote(JsObject chromeRuntime) : super(chromeRuntime) {
    _sendRuntimeMsg({ MsgKeys.SETTINGS_CLIENT_INIT: '' }, (JsObject settings) {
      _settings = new Settings.fromJSObj(settings);
      _initCompleter.complete();
    });
  }

  void _handleRuntimeMsg(JsObject msg, JsObject sender, JsFunction response) {
    if (msg.hasProperty(MsgKeys.SETTING_CHANGE)) {
      var setting = msg[MsgKeys.SETTING_CHANGE];
      _settings.set(setting['name'], setting['value']);
    } else if (msg.hasProperty(MsgKeys.SETTING_SUBMIT_RESULT)) {
      _submissionCompleter.complete(msg[MsgKeys.SETTING_SUBMIT_RESULT]);
    }
  }

  bool _submitSetting(String settingName, dynamic value) async {
    _taskChain = _submitSettingRecursiveHelper(settingName, value);
    return await _taskChain;
  }

  // Mmmm recursion...been awhile my friend. Should probably write some
  // tests for this.
  Future<bool> _submitSettingRecursiveHelper(String settingName, dynamic value) {
    if (_submissionCompleter.isCompleted) {
      _submissionCompleter = new Completer();
      _sendRuntimeMsg({
        MsgKeys.SETTING_SUBMIT: {
          'name': settingName,
          'value': value
        }
      }, (_) {});

      return _submissionCompleter.future;
    } else {
      return _taskChain.then((_) {
        return _submitSettingRecursiveHelper(settingName, value);
      });
    }
  }
}
