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
}

void addContextMenuAction() {
  JsObject tabsNamespace = context['chrome']['tabs'];
  tabsNamespace.callMethod('getCurrent', [(JsObject tab) {
    String url = tab['url'];
    var urlOrigin = Uri.parse(url).origin;
    var props = new JsObject.jsify({
      'contexts': ['link'],
      'title': 'Copy as IPFS URL',
      'documentUrlPatterns': ['$urlOrigin/ipfs/*', '$urlOrigin/ipns/*']
    });
    JsObject contextMenusNamespace = context['chrome']['contextMenus'];
    contextMenusNamespace.callMethod('create', [props]);
  }]);

}

void addListenerToChromeEvent(JsObject namespace, String eventName, Function callback) {
  var event = namespace[eventName];
  JsObject dartifiedEvent;
  if (event is JsObject) {
    dartifiedEvent = event;
  } else {
    // Dart2JS glitch workaround https://code.google.com/p/dart/issues/detail?id=20800
    dartifiedEvent = new JsObject.fromBrowserObject(event);
  }

  dartifiedEvent.callMethod('addListener', [callback]);
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
      addContextMenuAction
    ]
  }]);
  declarativeContentNamespace['onPageChanged'].callMethod('removeRules', [
    null, () {
    declarativeContentNamespace['onPageChanged'].callMethod('addRules', [rules]);
  }]);
}

void pageActionOnClickedAction(JsObject tab) {
  // Yes this is a zany hack.
  var tempEl = document.createElement('textarea');
  document.body.append(tempEl);
  tempEl.focus();
  tempEl.select();
  tempEl.value = tab['url'];
  document.execCommand('copy', false, null);
  tempEl.remove();
}

