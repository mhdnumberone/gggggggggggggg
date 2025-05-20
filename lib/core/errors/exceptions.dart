// lib/core/errors/exceptions.dart

// Exception from API (Server error, e.g., 5xx)
class ServerException implements Exception {
  final String message;
  final int? statusCode;

  ServerException(this.message, {this.statusCode});

  @override
  String toString() {
    return 'ServerException: $message (Status Code: ${statusCode ?? 'N/A'})';
  }
}

// Exception for network issues (e.g., no internet, DNS failure)
class NetworkException implements Exception {
  final String message;

  NetworkException(this.message);

  @override
  String toString() => 'NetworkException: $message';
}

// Exception for data parsing issues (e.g., malformed JSON)
class ParsingException implements Exception {
  final String message;

  ParsingException(this.message);

  @override
  String toString() => 'ParsingException: $message';
}

// General Cache Exception (if you implement caching)
class CacheException implements Exception {
  final String message;
  CacheException(this.message);

  @override
  String toString() => 'CacheException: $message';
}

// Exception for Authentication issues
class AuthException implements Exception {
  final String message;
  AuthException(this.message);

  @override
  String toString() => 'AuthException: $message';
}
