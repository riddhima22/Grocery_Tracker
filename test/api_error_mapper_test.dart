import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:grocery_track/core/api/api_error_mapper.dart';
import 'package:grocery_track/core/api/api_exception.dart';

void main() {
  group('ApiErrorMapper TLS & Certificate Verification Tests', () {
    test('maps HandshakeException to CertificateVerificationException', () {
      final dioException = DioException(
        requestOptions: RequestOptions(path: '/groceries/'),
        error: const HandshakeException('Handshake error in client: CERTIFICATE_VERIFY_FAILED: self signed certificate in certificate chain'),
        type: DioExceptionType.connectionError,
        message: 'Handshake error in client',
      );

      final mapped = ApiErrorMapper.map(dioException);

      expect(mapped, isA<CertificateVerificationException>());
      expect(mapped.message, 'Secure connection to the server failed. Please try again later.');
    });

    test('maps string certificate verification failure to CertificateVerificationException', () {
      final dioException = DioException(
        requestOptions: RequestOptions(path: '/groceries/123/consume/'),
        type: DioExceptionType.unknown,
        message: 'CERTIFICATE_VERIFY_FAILED: self signed certificate in certificate chain',
      );

      final mapped = ApiErrorMapper.map(dioException);

      expect(mapped, isA<CertificateVerificationException>());
      expect(mapped.message, 'Secure connection to the server failed. Please try again later.');
    });

    test('maps timeout to TimeoutException', () {
      final dioException = DioException(
        requestOptions: RequestOptions(path: '/groceries/'),
        type: DioExceptionType.connectionTimeout,
      );

      final mapped = ApiErrorMapper.map(dioException);

      expect(mapped, isA<TimeoutException>());
      expect(mapped.message, 'Connection timed out. Please try again.');
    });

    test('maps normal connection error to NetworkException', () {
      final dioException = DioException(
        requestOptions: RequestOptions(path: '/groceries/'),
        error: const SocketException('Failed host lookup: google.com'),
        type: DioExceptionType.connectionError,
      );

      final mapped = ApiErrorMapper.map(dioException);

      expect(mapped, isA<NetworkException>());
    });
  });
}
