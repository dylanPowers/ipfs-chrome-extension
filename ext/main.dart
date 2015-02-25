library ipfs_interceptor;

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