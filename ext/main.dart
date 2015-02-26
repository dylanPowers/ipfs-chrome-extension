library ipfs_interceptor;

import 'dart:html';
import 'dart:js';

void main() {
  var onBeforeRequest = context['chrome']['webRequest']['onBeforeRequest'];
  onBeforeRequest.callMethod('addListener', [
    onBeforeRequestCallback,
    new JsObject.jsify({
      'urls': ['*://gateway.ipfs.io/ipfs/*', '*://gateway.ipfs.io/ipns/*']
    }),
    new JsObject.jsify(['blocking'])
  ]);

  // Dart2JS glitch workaround https://code.google.com/p/dart/issues/detail?id=20800
  var tabsOnUpdated = context['chrome']['tabs']['onUpdated'];
  JsObject dartTabsOnUpdatedEvent;
  if (tabsOnUpdated is JsObject) {
    dartTabsOnUpdatedEvent = tabsOnUpdated;
  } else {
    dartTabsOnUpdatedEvent = new JsObject.fromBrowserObject(tabsOnUpdated);
  }

  dartTabsOnUpdatedEvent.callMethod('addListener', [
    tabsOnUpdatedCallback
  ]);
}

JsObject onBeforeRequestCallback(JsObject data) {
  var urlString = data['url'];
  var url = Uri.parse(urlString);
  url = new Uri.http('localhost:8080', url.path);
  print('$urlString => $url');
  var response = {
    'redirectUrl': url.toString()
  };
  return new JsObject.jsify(response);
}

void tabsOnUpdatedCallback(int tabId, JsObject changeInfo, JsObject tab) {
  var status = changeInfo['status'];
  var url = changeInfo['url'];
  print('''
  tab change:
    id: $tabId
    url: $url
    status: $status
  ''');

  if (status == 'complete') {
    context['chrome']['tabs'].callMethod('executeScript', [
        tabId, new JsObject.jsify({
          'code': '''
            window.history.replaceState({}, null, "http://gateway.ipfs.io/yummies");
            system.log('hi! world!');
          '''
        }), null
    ]);
  }
}