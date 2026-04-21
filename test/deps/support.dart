import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// ---------------------------------------------------------------------------
// Test helpers

/// A client that responds to pub.dev API requests for [package] with a
/// discontinued response, optionally naming [replacedBy].
http.Client discontinuedClient(String package, String? replacedBy) {
  return MockClient((request) async {
    if (request.url.path.endsWith('/packages/$package')) {
      return http.Response(
        jsonEncode({
          'isDiscontinued': true,
          if (replacedBy != null) 'replacedBy': replacedBy,
          'latest': {'version': '1.0.0'},
        }),
        200,
      );
    }
    return http.Response('not found', 404);
  });
}

/// A client that responds to pub.dev API requests for [package] with
/// [latestVersion] as the current latest (not discontinued).
http.Client latestVersionClient(String package, String latestVersion) {
  return MockClient((request) async {
    if (request.url.path.endsWith('/packages/$package')) {
      return http.Response(
        jsonEncode({
          'isDiscontinued': false,
          'latest': {'version': latestVersion},
        }),
        200,
      );
    }
    return http.Response('not found', 404);
  });
}

/// A client that should never be called — fails the test if it is.
http.Client noNetworkClient() {
  return MockClient((request) async {
    throw StateError('Unexpected HTTP request: ${request.url}');
  });
}
