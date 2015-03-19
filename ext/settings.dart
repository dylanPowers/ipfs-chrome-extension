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
 */
library settings;

import 'dart:async';
import 'dart:js';

import 'package:ipfs_gateway_redirect/chrome_help.dart';

abstract class MsgKeys {
  static const SETTING_CHANGE = 'setting-change';
  static const SETTING_SUBMIT = 'setting-submit';
  static const SETTINGS_CLIENT_INIT = 'settings-client-init';
}

typedef void SettingKVLoopFunc(String key, dynamic val);
typedef void RuntimeCallback(JsObject response);

class Settings {
  static const ERROR_UNKNOWN_KEYNAME = 'Unknown keyname';

  bool allowAll = false;
  bool allowFile = false;
  bool allowHttp = false;
  String host = 'localhost';
  int port = 8080;
  String get server => 'http://$host:$port';

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
      } else {
        throw ERROR_UNKNOWN_KEYNAME;
      }
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
  String get server => _settings.server;

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
        (JsObject settings) => _submitSettings(settings)
    ]);
  }

  void _applySetting(String settingName, dynamic value) {
    var oldVal = _settings.get(settingName);
    if (oldVal != value) {
      _settings.set(settingName, value);
      chromeStorage['local'].callMethod('set', [new JsObject.jsify({settingName: value})]);
      _sendSettingChangeMsg(settingName, value, oldVal);
    }
  }

  void _handleRuntimeMsg(JsObject msg, JsObject sender, JsFunction response) {
    if (msg.hasProperty(MsgKeys.SETTING_SUBMIT)) {
      var newSetting = msg[MsgKeys.SETTING_SUBMIT];

      // I broke Dart here. Await borked things
      _submitSetting(newSetting['name'], newSetting['value']).then((_) {
        response.apply([]);
      });
    } else if (msg.hasProperty(MsgKeys.SETTINGS_CLIENT_INIT)) {
      response.apply([new JsObject.jsify(_settings.toMap())]);
    }
  }

  bool _requestPermissions(Settings settings) async {
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

  void _submitSetting(String settingName, dynamic value) async {
    var newSettings = new Settings.copy(_settings);
    newSettings.set(settingName, value);
    if (await _requestPermissions(newSettings)) {
      _applySetting(settingName, value);
    }
  }

  void _submitSettings(JsObject settingsJs) async {
    var newSettings = new Settings.fromJSObj(settingsJs);
    if (await _requestPermissions(newSettings)) {
      Settings.jsObjForEach(settingsJs, _applySetting);
    }
  }
}


/**
 * The Remote listens for the runtime messages
 * 'setting-change'
 *
 * The Remote emits the runtime messages
 * 'setting-submit'
 * 'settings-client-init'
 */
class SettingsRemote extends ChromeSettings {
  final _initCompleter = new Completer();
  Future get whenInitializationCompletes async => _initCompleter.future;

  void submitAllowAll(bool flag) async {
    await _submitSetting('allow-all', flag);
  }

  void submitAllowFile(bool flag) async {
    await _submitSetting('allow-file', flag);
  }

  void submitAllowHttp(bool flag) async {
    await _submitSetting('allow-http', flag);
  }

  void submitHost(String host) async {
    await _submitSetting('host', host);
  }

  void submitPort(int port) async {
    await _submitSetting('port', port);
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
    }
  }

  Future _submitSetting(String settingName, dynamic value) {
    var completer = new Completer();
    _sendRuntimeMsg({
      settingName: value
    }, (_) {
      completer.complete();
    });

    return completer.future;
  }
}
