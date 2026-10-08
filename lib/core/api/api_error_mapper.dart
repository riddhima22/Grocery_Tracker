import 'dart:io';
import 'package:dio/dio.dart';
import 'api_exception.dart';
import '../utils/app_logger.dart';

class ApiErrorMapper {
  static ApiException map(DioException error) {
    AppLogger.error('API Error: ${error.type} - ${error.message} - ${error.response?.data}');
    
    // 1. Explicitly check for TLS / SSL Certificate and Handshake failures
    final rawError = error.error;
    final errorStr = '${error.message} ${error.error}'.toLowerCase();
    final isCertError = rawError is HandshakeException ||
        rawError is TlsException ||
        rawError is CertificateException ||
        errorStr.contains('certificate_verify_failed') ||
        errorStr.contains('handshake error') ||
        errorStr.contains('handshakeexception') ||
        errorStr.contains('cert_authority_invalid') ||
        errorStr.contains('self signed certificate');

    if (isCertError) {
      AppLogger.error('TLS/SSL Certificate Verification Failure: ${error.message} (Raw: $rawError)');
      return CertificateVerificationException(
        'Secure connection to the server failed. Please try again later.',
        rawError?.toString() ?? error.message,
      );
    }

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return TimeoutException('Connection timed out. Please try again.');
        
      case DioExceptionType.badResponse:
        final response = error.response;
        final statusCode = response?.statusCode;
        final data = response?.data;
        
        String serverMessage = 'An unexpected error occurred.';
        Map<String, dynamic>? fields;
        
        if (data is Map) {
          // 1. Check if the error is wrapped in our custom envelope
          if (data.containsKey('error') && data['error'] is Map) {
            final errObj = data['error'];
            serverMessage = errObj['message'] ?? serverMessage;
            if (errObj['fields'] is Map) {
              fields = Map<String, dynamic>.from(errObj['fields']);
            }
          }
          // 2. Check for standard DRF detail field (e.g. SimpleJWT error or DRF detail)
          else if (data.containsKey('detail')) {
            serverMessage = data['detail'].toString();
          }
          // 3. Check for standard DRF validation errors with lists
          else if (data.containsKey('non_field_errors')) {
            final nfe = data['non_field_errors'];
            if (nfe is List && nfe.isNotEmpty) {
              serverMessage = nfe.first.toString();
            } else {
              serverMessage = nfe.toString();
            }
          } 
          // 4. Handle raw key-value field validation lists (e.g., {"email": ["Enter a valid email"]})
          else {
            final fieldErrors = <String, dynamic>{};
            data.forEach((key, val) {
              if (val is List && val.isNotEmpty) {
                fieldErrors[key.toString()] = val.first.toString();
              } else {
                fieldErrors[key.toString()] = val.toString();
              }
            });
            if (fieldErrors.isNotEmpty) {
              fields = fieldErrors;
              // Set message to the first validation error
              final firstKey = fieldErrors.keys.first;
              final firstError = fieldErrors[firstKey];
              // Capitalize first key letter for readability, e.g. "Email: This field must be unique."
              final cleanKey = firstKey.substring(0, 1).toUpperCase() + firstKey.substring(1);
              serverMessage = '$cleanKey: $firstError';
            }
          }
        } else if (data is String && data.isNotEmpty) {
          serverMessage = data;
        }
        
        switch (statusCode) {
          case 400:
            return ValidationException(serverMessage, fields: fields, statusCode: statusCode);
          case 401:
            return UnauthorizedException(serverMessage);
          case 403:
            return ForbiddenException(serverMessage);
          case 404:
            return NotFoundException(serverMessage);
          case 409:
            return ConflictException(serverMessage);
          case 413:
            return PayloadTooLargeException('The uploaded file is too large.');
          case 429:
            return RateLimitException(serverMessage);
          case 500:
          case 502:
          case 503:
          case 504:
            return ServerException('Server error. Please try again later.');
          default:
            return ApiException(serverMessage, statusCode);
        }
        
      case DioExceptionType.connectionError:
        return NetworkException('No internet connection. Check your network and try again.');
        
      case DioExceptionType.cancel:
        return ApiException('Request was cancelled.');
        
      default:
        return UnknownApiException('Something went wrong. Please try again.');
    }
  }
}
