library ipfs_interceptor;

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
  addListenerToChromeEvent(_runtime, 'onInstalled', onInstalledAction);

  // A page action is the little icon that appears in the URL bar.
  addListenerToChromeEvent(_pageAction, 'onClicked', pageActionOnClickedAction);

  addContextMenu();
  new WebRequestRedirect(_webRequest, _runtime);
}


void addContextMenu() {
  var urlMatch = ["http://localhost:*/ipfs/*", "http://localhost:*/ipns/*"];
  var props = new JsObject.jsify({
    'contexts': ['link'],

    // This should match the default_title under page_action in the manifest
    'title': 'Copy as IPFS link',

    'documentUrlPatterns': urlMatch,
    'targetUrlPatterns': urlMatch,
    'onclick': (JsObject info, JsObject tab) {
      addToClipboardAsIpfsUrl(info['linkUrl']);
    }
  });
  _contextMenus.callMethod('create', [props]);
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


void onInstalledAction(JsObject details) {
  var pageStateMatcherArg = new JsObject.jsify({
    'pageUrl': {
      // Chrome has globbing available everywhere but here
      'originAndPathMatches': '^http://localhost(:[[:digit:]]+)?\\/(ipfs|ipns)\\/.+',
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


void pageActionOnClickedAction(JsObject tab) {
  addToClipboardAsIpfsUrl(tab['url']);
}

class WebRequestRedirect {
  String _host = 'localhost';
  int _port = 8080;

  WebRequestRedirect(JsObject chromeWebRequest, JsObject chromeRuntime) {
    dartifyChromeEvent(chromeWebRequest, 'onBeforeRequest').callMethod('addListener', [
      _onBeforeRequestAction,
      new JsObject.jsify({
        'urls': ['http://gateway.ipfs.io/ipfs/*', 'http://gateway.ipfs.io/ipns/*']
      }),
      new JsObject.jsify(['blocking'])
    ]);

    addListenerToChromeEvent(chromeRuntime, 'onMessage', _handleRuntimeMsg);
  }

  void _handleRuntimeMsg(JsObject msg, JsObject sender, JsFunction response) {
    if (msg['host'] != null) {
      _host = msg['host'] as String;
    } else if (msg['port'] != null) {
      _port = msg['port'] as int;
    } else if (msg['options'] != null && msg['options'] == 'hostServer') {
      response.apply([new JsObject.jsify({
        'host': _host,
        'port': _port
      })]);
    }

    print('$_host:$_port');
  }

  JsObject _onBeforeRequestAction(JsObject data) {
    var ipfsUrl = data['url'];
    var localhostUrl = Uri.parse(ipfsUrl).replace(host: _host, port: _port);
    var response = {
      'redirectUrl': localhostUrl.toString()
    };
    return new JsObject.jsify(response);
  }
}
