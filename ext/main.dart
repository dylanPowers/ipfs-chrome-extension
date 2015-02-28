library ipfs_interceptor;

import 'dart:async';
import 'dart:html';
import 'dart:js';

void main() {
  JsObject runtimeNamespace = context['chrome']['runtime'];
  addListenerToChromeEvent(runtimeNamespace, 'onInstalled', onInstalledAction);

  var onBeforeRequest = context['chrome']['webRequest']['onBeforeRequest'];
  onBeforeRequest.callMethod('addListener', [
    webRequestOnBeforeRequestAction,
    new JsObject.jsify({
      'urls': ['http://gateway.ipfs.io/ipfs/*', 'http://gateway.ipfs.io/ipns/*']
    }),
    new JsObject.jsify(['blocking'])
  ]);

  JsObject pageActionNamespace = context['chrome']['pageAction'];
  addListenerToChromeEvent(pageActionNamespace, 'onClicked', pageActionOnClickedAction);

  JsObject contextMenusNamespace = context['chrome']['contextMenus'];
  addListenerToChromeEvent(contextMenusNamespace, 'onClicked', (JsObject info, JsObject tab) {
    print('MenuId: ${info['menuItemId']}); url: ${info['linkUrl']}');
  });

  addContextMenu();
}

void addContextMenu() {
  var urlMatch = ["http://localhost:*/ipfs/*", "http://localhost:*/ipns/*"];
  var props = new JsObject.jsify({
    'contexts': ['link'],
    'title': 'Copy as IPFS URL',
    'documentUrlPatterns': urlMatch,
    'targetUrlPatterns': urlMatch,
    'onclick': (JsObject info, JsObject tab) {
      addToClipboardAsIpfsUrl(info['linkUrl']);
    }
  });
  JsObject contextMenusNamespace = context['chrome']['contextMenus'];
  contextMenusNamespace.callMethod('create', [props]);
}

void addListenerToChromeEvent(JsObject namespace, String eventName, Function callback) {
  var dartifiedEvent = dartifyChromeEvent(namespace, eventName);
  dartifiedEvent.callMethod('addListener', [callback]);
}

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

JsObject webRequestOnBeforeRequestAction(JsObject data) {
  var urlString = data['url'];
  var url = Uri.parse(urlString);
  url = new Uri.http('localhost:8080', url.path);
  print('$urlString => $url');
  var response = {
    'redirectUrl': url.toString()
  };
  return new JsObject.jsify(response);
}

void onInstalledAction(JsObject details) {
  JsObject declarativeContentNamespace = context['chrome']['declarativeContent'];
  var rules = new JsObject.jsify([{
    'conditions': [
      new JsObject(declarativeContentNamespace['PageStateMatcher'], [{
        'pageUrl': {
          'originAndPathMatches': '^localhost(:[[:digit:]]+)?\/(ipfs|ipns)\/.+',
          'schemes': ['http']
      }}])
    ],
    'actions': [
      new JsObject(declarativeContentNamespace['ShowPageAction']),
    ]
  }]);
  dartifyChromeEvent(declarativeContentNamespace, 'onPageChanged').callMethod('removeRules', [
    null, () {
    dartifyChromeEvent(declarativeContentNamespace, 'onPageChanged').callMethod('addRules', [rules]);
  }]);
}

void pageActionOnClickedAction(JsObject tab) {
  addToClipboardAsIpfsUrl(tab['url']);
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
  var ipfsUrl = new Uri.http('gateway.ipfs.io', Uri.parse(localUrl).path);
  addToClipboard(ipfsUrl.toString());
}