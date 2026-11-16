class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, [this.statusCode]);

  @override
  String toString() => message;
}

class NetworkException extends ApiException {
  NetworkException(super.message);
}

class CertificateVerificationException extends ApiException {
  final dynamic technicalDetails;
  CertificateVerificationException(super.message, [this.technicalDetails]);
}

class TimeoutException extends ApiException {
  TimeoutException(super.message);
}

class ValidationException extends ApiException {
  final Map<String, dynamic>? fields;
  ValidationException(String message, {this.fields, int? statusCode})
    : super(message, statusCode);
}

class UnauthorizedException extends ApiException {
  UnauthorizedException(String message) : super(message, 401);
}

class ForbiddenException extends ApiException {
  ForbiddenException(String message) : super(message, 403);
}

class NotFoundException extends ApiException {
  NotFoundException(String message) : super(message, 404);
}

class ConflictException extends ApiException {
  ConflictException(String message) : super(message, 409);
}

class PayloadTooLargeException extends ApiException {
  PayloadTooLargeException(String message) : super(message, 413);
}

class RateLimitException extends ApiException {
  RateLimitException(String message) : super(message, 429);
}

class ServerException extends ApiException {
  ServerException(String message) : super(message, 500);
}

class UnknownApiException extends ApiException {
  UnknownApiException(super.message);
}

class RequestCancelledException extends ApiException {
  RequestCancelledException([super.message = 'Request was cancelled.']);
}
