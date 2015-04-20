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


void addToClipboardAsIpfsUrl(String localUrl) {
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

List<String> makeIpfsGlobs(String server) {
  return ['$server/ipfs/*', '$server/ipns/*'];
}


void _setupContextMenu(HostServerSettings settings) {
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
  props['targetUrlPatterns'] = new JsArray.from(props['targetUrlPatterns']);
  _contextMenus.callMethod('create', [props]);
}


void _setupPageStateMatcher(HostServerSettings settings) {
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


class HostServerSettings {
  Stream get changes => _changesController.stream;
  JsObject chromeStorage;
  String get host => _host;
  int get port => _port;
  String get server => 'http://$host:$port';

  final _changesController = new StreamController.broadcast();
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
        _changesController.add(server);
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

class DomainCacheItem {
  DateTime cacheTime;
  bool ipnsAvailable;

  DomainCacheItem(this.cacheTime, this.ipnsAvailable);
}

class WebRequestRedirect {
  static const _CACHE_DURATION = const Duration(minutes: 1);
  static const _ERROR_COOL_DOWN_PERIOD = const Duration(seconds: 30);

  final JsObject chromeWebRequest;
  final HostServerSettings settings;

  final _domainCache = new Map<String, DomainCacheItem>();
  bool _errorMode = false;
  var _lastErrorTime = new DateTime(0);
  List<Uri> _ipfsRequestUrls;

  WebRequestRedirect(this.chromeWebRequest, this.settings) {
    _initIpfsRequestUrls();
    _setIpfsRequestErrorListener();
    _setChromeRequestListener();
    _initSettingsListener();
    _initCacheCleaner();
  }

  void _disableErrorMode() {
    _errorMode = false;
    _initIpfsRequestUrls();
    _setChromeRequestListener();
  }

  void _enableErrorMode() {
    _errorMode = true;
    _lastErrorTime = new DateTime.now();
    _initIpfsRequestUrls();
    _setChromeRequestListener();
  }


  String _handleIpfsRequest(JsObject data, Uri ipfsUrl) {
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

    return localUrl.toString();
  }

  String _handleOtherRequest(Uri url) {
    String redirectUrl = '';

    // A note on error mode: While we could fail back to the gateway.ipfs.io
    // server, we might as well just use the original web server. While it is
    // feasible that someone could create a domain that only points into ipfs,
    // it would be reasonably expected that they'd share
    // http://gateway.ipfs.io/ipns/<domain> as
    // a url so that those outside of IPFS would have easy access.
    if (!_errorMode &&
        ((url.scheme == 'http' && url.port == 80) ||
         (url.scheme == 'https' && url.port == 443))) {
      var cacheKey = url.host;
      var ipnsUrl = 'http://${settings.host}:${settings.port}/ipns/${url.replace(scheme: '')}';
      if (_domainCache.containsKey(cacheKey) &&
          _domainCache[cacheKey].cacheTime.isAfter(new DateTime.now().subtract(_CACHE_DURATION))) {
        if (_domainCache[cacheKey].ipnsAvailable) {
          redirectUrl = ipnsUrl;
        }
      } else {
        var ipnsAvailable = _requestIpnsAvailability(url.host);
        _domainCache[cacheKey] = new DomainCacheItem(new DateTime.now(), ipnsAvailable);
        if (ipnsAvailable) {
          redirectUrl = ipnsUrl;
        }
      }
    }

    return redirectUrl;
  }

  void _initCacheCleaner() {
    new Timer.periodic(_CACHE_DURATION * 10, (_) {
      var keysToRemove = [];
      var oldestCacheTime = new DateTime.now().subtract(_CACHE_DURATION);
      _domainCache.forEach((k, v) {
      if (v.cacheTime.isBefore(oldestCacheTime)) {
          keysToRemove.add(k);
        }
      });
      keysToRemove.forEach((k) => _domainCache.remove(k));
    });
  }

  void _initIpfsRequestUrls() {
    var urls = makeIpfsGlobs('file://');
    if (_errorMode) {
      urls.addAll(makeIpfsGlobs(settings.server));
    } else {
      urls.addAll(makeIpfsGlobs('http://gateway.ipfs.io'));
    }
    _ipfsRequestUrls = urls.map((url) => Uri.parse(url)).toList(growable: false);
  }

  void _initSettingsListener() {
    settings.changes.listen((_) {
      dartifyChromeEvent(chromeWebRequest, 'onErrorOccurred')
          .callMethod('removeListener', [_onErrorAction]);
      _setIpfsRequestErrorListener();
      _errorMode = false;
    });
  }

  bool _isIpfsUrl(Uri url) {
    bool urlMatch = false;
    if (url.pathSegments.isNotEmpty &&
        (url.pathSegments.first == 'ipfs' || url.pathSegments.first == 'ipns')) {
      urlMatch = url.host == settings.host && url.port == settings.port;

      for (int i = 0; i < _ipfsRequestUrls.length && !urlMatch; ++i) {
        urlMatch = _ipfsRequestUrls[i].host == url.host &&
                    _ipfsRequestUrls[i].port == url.port;
      }
    }

    return urlMatch;
  }

  /**
   * This gets run on every single request the browser makes. It is pertinent
   * for it to be FAST!
   */
  JsObject _onBeforeRequestAction(JsObject data) {
    if (_errorMode &&
        new DateTime.now().subtract(_ERROR_COOL_DOWN_PERIOD).isAfter(_lastErrorTime)) {
      _disableErrorMode();
    }

    JsObject redirectJsObj;
    try {
      Uri url = Uri.parse(data['url']);
      String redirectUrl = '';
      if (_isIpfsUrl(url)) {
        redirectUrl = _handleIpfsRequest(data, url);
      } else {
        redirectUrl = _handleOtherRequest(url);
      }

      if (redirectUrl != '') {
        redirectJsObj = new JsObject.jsify({
          'redirectUrl': redirectUrl
        });
      }
    } on FormatException {
      // Some websites like to add invalid characters to their query strings
      // that their servers must like but the uri parser has beef with.
      // We'll just continue on with life like the request never happened.
    }

    return redirectJsObj;
  }

  void _onErrorAction(JsObject details) {
    // Chrome will give an error message, but there isn't a defined way of
    // identifying the problem. Nor is there a way to tell Chrome how to
    // resolve the problem. Luckily Chrome will automatically reattempt the
    // request. We just have to be ready for it.
    _enableErrorMode();
  }

  /**
   * File URI's sometimes have the URI fragment character '#'
   * encoded by Chrome because it wants to be "smart".
   * It's dependent on how the user inputs the URI
   * into the browser URL bar. Unfortunately it's impossible to
   * differentiate between the cases; i.e. typing:
   *         /ipfs/<hash>/app#stuff vs file:///ipfs/<hash>/app#stuff
   * Generally people don't have hashes in their filenames, so I'm
   * exchanging one idiotic idea for something that's slightly
   * less idiotic for our purposes. If someone really needs a '#' character
   * for a filename, just double encode it in the url bar.
   */
  static Uri _parseFileUrl(String fileUrl) {
    return Uri.parse(Uri.decodeComponent(fileUrl));
  }

  bool _requestIpnsAvailability(String host) {
    var req = new HttpRequest();
    req.open('GET', 'http://${settings.host}:${settings.port}/ipns/${host}', async: false);

    bool ipnsAvailable;
    req.onLoad.listen((event) {
      ipnsAvailable = (event.target as HttpRequest).status < 400;
    });

    req.send();

    return ipnsAvailable;
  }

  void _setIpfsRequestErrorListener() {
    dartifyChromeEvent(chromeWebRequest, 'onErrorOccurred')
        .callMethod('addListener', [
          _onErrorAction,
          new JsObject.jsify({'urls': makeIpfsGlobs(settings.server)})
    ]);
  }
  
  void _setChromeRequestListener() {
    var urlsToListen = ['http://*/', 'https://*/'];
    urlsToListen.addAll(makeIpfsGlobs('file://'));

    dartifyChromeEvent(chromeWebRequest, 'onBeforeRequest')
        .callMethod('removeListener', [_onBeforeRequestAction]);
    dartifyChromeEvent(chromeWebRequest, 'onBeforeRequest')
        .callMethod('addListener', [
          _onBeforeRequestAction,
          new JsObject.jsify({'urls': urlsToListen}),
          new JsObject.jsify(['blocking'])
    ]);
  }
}
