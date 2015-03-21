library ipfs_interceptor;

import 'dart:js';

import 'package:ipfs_gateway_redirect/chrome_help.dart';
import 'package:ipfs_gateway_redirect/settings.dart';
import 'package:observe/observe.dart';

// There is a Dart library for Chrome Apps and Extensions but it's pretty
// broken so we're best off just accessing the JS API directly.
JsObject _contextMenus = context['chrome']['contextMenus'];
JsObject _declarativeContent = context['chrome']['declarativeContent'];
JsObject _pageAction = context['chrome']['pageAction'];
JsObject _permissions = context['chrome']['permissions'];
JsObject _runtime = context['chrome']['runtime'];
JsObject _storage = context['chrome']['storage'];
JsObject _webRequest = context['chrome']['webRequest'];


void main() {
  var settings = new SettingsCore(_permissions, _runtime, _storage);

  addListenerToChromeEvent(_runtime, 'onInstalled', (_) {
    _setupPageStateMatcher(settings);
  });

  // A page action is the little icon that appears in the URL bar.
  addListenerToChromeEvent(_pageAction, 'onClicked', _pageActionOnClickedAction);

  _setupContextMenu(settings);
  new WebRequestRedirect(_webRequest, settings);

  settings.serverChanges.listen((List<PropertyChangeRecord> changes) {
    _setupContextMenu(settings);
    _setupPageStateMatcher(settings);
  });
}


void addToClipboardAsIpfsUrl(String localUrl) {
  var ipfsUrl = Uri.parse(localUrl).replace(host: 'gateway.ipfs.io', port: 80);
  addToClipboard(ipfsUrl.toString());
}

List<String> makeIpfsGlobs(String server) {
  return ['$server/ipfs/*', '$server/ipns/*'];
}


void _setupContextMenu(ChromeSettings settings) {
  _contextMenus.callMethod('removeAll');

  var urlMatch = makeIpfsGlobs(settings.server);
  var props = new JsObject.jsify({
    'contexts': ['frame', 'link', 'image', 'video', 'audio'],
    'title': _runtime.callMethod('getManifest')['page_action']['default_title'],

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


void _setupPageStateMatcher(ChromeSettings settings) {
  var pageStateMatcherArg = new JsObject.jsify({
    'pageUrl': {
      // Chrome has globbing available everywhere but here
      // Also note that for ports 80 and 443 the port numbers won't be present
      'originAndPathMatches': r'^http://' + settings.host + r'(:' + settings.port.toString() + r')?/(ipfs|ipns)/.+',
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


class WebRequestRedirect {
  static const _ERROR_COOL_DOWN_PERIOD = const Duration(seconds: 30);

  final JsObject chromeWebRequest;
  final ChromeSettings settings;

  bool _errorMode = false;
  var _lastErrorTime = new DateTime(0);
  List<String> get _requestUrls {
    var urls = makeIpfsGlobs('file://');
    if (_errorMode) {
      urls.addAll(makeIpfsGlobs(settings.server));
    } else {
      urls.addAll(makeIpfsGlobs('http://gateway.ipfs.io'));
    }

    return urls;
  }

  WebRequestRedirect(this.chromeWebRequest, this.settings) {
    _setErrorListener();
    _setRequestListener();

    settings.serverChanges.listen((_) {
      dartifyChromeEvent(chromeWebRequest, 'onErrorOccurred')
          .callMethod('removeListener', [_onErrorAction]);
      _setErrorListener();
      _errorMode = false;
    });
  }

  void _onErrorAction(JsObject details) {
    // Chrome will give an error message, but there isn't a defined way of
    // identifying the problem. Nor is there a way to tell Chrome how to
    // resolve the problem. Luckily Chrome will automatically reattempt the
    // request. We just have to be ready for it.
    _errorMode = true;
    _lastErrorTime = new DateTime.now();
    _setRequestListener();
  }

  JsObject _onBeforeRequestAction(JsObject data) {
    if (_errorMode &&
        new DateTime.now().difference(_lastErrorTime) > _ERROR_COOL_DOWN_PERIOD) {
      _errorMode = false;
      _setRequestListener();
    }

    var ipfsUrl = Uri.parse(data['url']);
    if (ipfsUrl.scheme == 'file') {
      ipfsUrl = _parseFileUrl(data['url']);
    }

    // Chrome doesn't like file based apps much. Always use the HTTP API.
    Uri localUrl;
    if (!_errorMode) {
      localUrl = ipfsUrl.replace(scheme: 'http',
                                 host: settings.host,
                                 port: settings.port);
    } else {
      localUrl = ipfsUrl.replace(scheme: 'http', host: 'gateway.ipfs.io', port: 80);
    }

    return new JsObject.jsify({
      'redirectUrl': localUrl.toString()
    });
  }

  /**
   * File URI's sometimes have the URI fragment character '#'
   * encoded by Chrome because it wants to be "smart" when in reality it's
   * being idiotic. It's dependent on how the user inputs the URI
   * into the browser URL bar. Unfortunately it's impossible to
   * differentiate between the cases; i.e. typing:
   *         /ipfs/<hash>/app#stuff vs file:///ipfs/<hash>/app#stuff
   * Generally people don't have hashes in their filenames, so I'm
   * exchanging one completely idiotic idea for something that's slightly
   * less idiotic.
   */
  static Uri _parseFileUrl(String fileUrl) {
    return Uri.parse(Uri.decodeComponent(fileUrl));
  }

  void _setErrorListener() {
    dartifyChromeEvent(chromeWebRequest, 'onErrorOccurred')
        .callMethod('addListener', [
          _onErrorAction,
          new JsObject.jsify({'urls': makeIpfsGlobs(settings.server)})
    ]);
  }
  
  void _setRequestListener() {
    dartifyChromeEvent(chromeWebRequest, 'onBeforeRequest')
        .callMethod('removeListener', [_onBeforeRequestAction]);
    dartifyChromeEvent(chromeWebRequest, 'onBeforeRequest')
        .callMethod('addListener', [
          _onBeforeRequestAction,
          new JsObject.jsify({'urls': _requestUrls}),
          new JsObject.jsify(['blocking'])
    ]);
  }
}
