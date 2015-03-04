library ipfs_interceptor;

import 'dart:async';
import 'dart:html';
import 'dart:js';

// There is a Dart library for Chrome Apps and Extensions but it's pretty
// broken so we're best off just accessing the JS API directly.
JsObject _contextMenus = context['chrome']['contextMenus'];
JsObject _declarativeContent = context['chrome']['declarativeContent'];
JsObject _pageAction = context['chrome']['pageAction'];
JsObject _runtime = context['chrome']['runtime'];
JsObject _webRequest = context['chrome']['webRequest'];


void main() {
  var settings = new HostServerSettings(_runtime, context['chrome']['storage']);

  addListenerToChromeEvent(_runtime, 'onInstalled', (_) {
    _setupPageStateMatcher(settings);
  });

  // A page action is the little icon that appears in the URL bar.
  addListenerToChromeEvent(_pageAction, 'onClicked', _pageActionOnClickedAction);

  _setupContextMenu(settings);
  new WebRequestRedirect(_webRequest, settings);

  settings.changes.listen((_) {
    _setupContextMenu(settings);
    _setupPageStateMatcher(settings);
  });
}


void addListenerToChromeEvent(JsObject namespace, String eventName, Function callback) {
  var dartifiedEvent = dartifyChromeEvent(namespace, eventName);
  dartifiedEvent.callMethod('addListener', [callback]);
}


void addToClipboard(String text) {
  // Yes this is a zany hack.
  var tempEl = document.createElement('textarea');
  document.body.append(tempEl);
  tempEl.value = text;
  tempEl.focus();
  tempEl.select();
  document.execCommand('copy', false, null);
  tempEl.remove();
}


String addToClipboardAsIpfsUrl(String localUrl) {
  var ipfsUrl = Uri.parse(localUrl).replace(host: 'gateway.ipfs.io', port: 80);
  addToClipboard(ipfsUrl.toString());
}


/**
 * This function exists purely because of a bug in the dart2js compiler. It
 * must be used to properly access a Chrome Event object. Without it, vague
 * meaningless errors when running as Javascript will crop up.
 * https://code.google.com/p/dart/issues/detail?id=20800
 */
JsObject dartifyChromeEvent(JsObject namespace, String eventName) {
  var event = namespace[eventName];
  JsObject dartifiedEvent;
  if (event is JsObject) {
    dartifiedEvent = event;
  } else {
    // Dart2JS glitch workaround https://code.google.com/p/dart/issues/detail?id=20800
    dartifiedEvent = new JsObject.fromBrowserObject(event);
  }

  return dartifiedEvent;
}


void _setupContextMenu(HostServerSettings settings) {
  _contextMenus.callMethod('removeAll');

  var server = 'http://${settings.host}:${settings.port}';
  var urlMatch = ['$server/ipfs/*', '$server/ipns/*'];
  var props = new JsObject.jsify({
    'contexts': ['frame', 'link', 'image', 'video', 'audio'],

    // This should match the default_title under page_action in the manifest
    'title': 'Copy as IPFS link',

    'documentUrlPatterns': urlMatch,
    'targetUrlPatterns': urlMatch,
    'onclick': (JsObject info, JsObject tab) {
      // Fuck this...4 different names for the same thing? Why????
      var possibleKeys = ['linkUrl', 'srcUrl', 'pageUrl', 'frameUrl'];
      bool keyFound;
      for (num i = 0; i < possibleKeys.length && !keyFound; ++i) {
        if (info.hasProperty(possibleKeys[i])) {
          addToClipboardAsIpfsUrl(info[possibleKeys[i]]);
          keyFound = true;
        }
      }
    }
  });

  // A hack to get around the most weirdest and obscure bug ever seen when
  // compiling to JS. Apparently an Array isn't always an Array in JS? Or
  // maybe the Chrome API parses the object in such a way that the property
  // can't be accessed?
  // https://twitter.com/dylankpowers/status/573037501171933187
  props['targetUrlPatterns'] = new JsArray.from(props['targetUrlPatterns']);
  _contextMenus.callMethod('create', [props]);
}


void _setupPageStateMatcher(HostServerSettings settings) {
  var pageStateMatcherArg = new JsObject.jsify({
    'pageUrl': {
      // Chrome has globbing available everywhere but here
      // Also note that for ports 80 and 443 the port numbers won't be present
      'originAndPathMatches': '^http://${settings.host}(:${settings.port})?\\/(ipfs|ipns)\\/.+',
      'schemes': ['http']
  }});
  var rules = new JsObject.jsify([{
    'conditions': [
      new JsObject(_declarativeContent['PageStateMatcher'], [pageStateMatcherArg])
    ],
    'actions': [
      new JsObject(_declarativeContent['ShowPageAction']),
    ]
  }]);
  dartifyChromeEvent(_declarativeContent,
                     'onPageChanged').callMethod('removeRules', [null, () {
      dartifyChromeEvent(_declarativeContent,
                         'onPageChanged').callMethod('addRules', [rules]);
  }]);
}


void _pageActionOnClickedAction(JsObject tab) {
  addToClipboardAsIpfsUrl(tab['url']);
}


class HostServerSettings {
  Stream get changes => _changesController.stream;
  JsObject chromeStorage;
  String get host => _host;
  int get port => _port;

  final _changesController = new StreamController();
  String _host = 'localhost';
  int _port = 8080;

  HostServerSettings(JsObject chromeRuntime, this.chromeStorage) {
    addListenerToChromeEvent(chromeRuntime, 'onMessage', _handleRuntimeMsg);

    chromeStorage['local'].callMethod('get', [new JsObject.jsify(['host', 'port']),
                                             (JsObject settings) {
      bool valChanged = false;
      if (settings['host'] != null) {
        _host = settings['host'] as String;
        valChanged = true;
      }

      if (settings['port'] != null) {
        _port = settings['port'] as int;
        valChanged = true;
      }

      if (valChanged) {
        _changesController.add('$_host:$_port');
      }
    }]);
  }

  void _handleRuntimeMsg(JsObject msg, JsObject sender, JsFunction response) {
    if (msg['host'] != null) {
      _host = msg['host'] as String;
      chromeStorage['local'].callMethod('set', [new JsObject.jsify({'host': _host})]);
      _changesController.add(_host);
    } else if (msg['port'] != null) {
      _port = msg['port'] as int;
      chromeStorage['local'].callMethod('set', [new JsObject.jsify({'port': _port})]);
      _changesController.add(_port);
    } else if (msg['options'] != null && msg['options'] == 'hostServer') {
      response.apply([new JsObject.jsify({
        'host': _host,
        'port': _port
      })]);
    }
  }
}


class WebRequestRedirect {
  final HostServerSettings settings;

  WebRequestRedirect(JsObject chromeWebRequest, this.settings) {
    dartifyChromeEvent(chromeWebRequest, 'onBeforeRequest').callMethod('addListener', [
      _onBeforeRequestAction,
      new JsObject.jsify({
        'urls': ['http://gateway.ipfs.io/ipfs/*', 'http://gateway.ipfs.io/ipns/*']
      }),
      new JsObject.jsify(['blocking'])
    ]);
  }


  JsObject _onBeforeRequestAction(JsObject data) {
    var ipfsUrl = data['url'];
    var localhostUrl = Uri.parse(ipfsUrl).replace(host: settings.host, port: settings.port);
    var response = {
      'redirectUrl': localhostUrl.toString()
    };
    return new JsObject.jsify(response);
  }
}
