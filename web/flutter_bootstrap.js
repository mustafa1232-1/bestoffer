{{flutter_js}}
{{flutter_build_config}}

// Bump this query whenever the web release changes so installed PWAs cannot
// keep executing an older main.dart.js from the browser cache.
_flutter.loader.load({
  entrypointUrl: 'main.dart.js?v=1.0.15+61-web-20261018-mimo2',
});
