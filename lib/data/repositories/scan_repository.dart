import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../models/scan_session_model.dart';
import '../models/scan_candidate_model.dart';
import '../models/grocery_model.dart';

class ScanRepository {
  final ApiClient _apiClient = ApiClient();

  Future<ScanSessionModel> createScanSession(List<XFile> images) async {
    final List<MultipartFile> multipartFiles = [];
    for (var image in images) {
      final bytes = await image.readAsBytes();
      multipartFiles.add(
        MultipartFile.fromBytes(
          bytes,
          filename: image.name,
        ),
      );
    }

    final formData = FormData.fromMap({
      'images': multipartFiles,
    });

    final response = await _apiClient.post(
      ApiEndpoints.scanSessions,
      data: formData,
      options: Options(contentType: 'multipart/form-data'),
    );

    return ScanSessionModel.fromJson(response.data['data']);
  }

  Future<ScanSessionModel> getScanSession(String id) async {
    final response = await _apiClient.get(ApiEndpoints.scanDetail(id));
    return ScanSessionModel.fromJson(response.data['data']);
  }

  Future<List<ScanCandidateModel>> getCandidates(String sessionId) async {
    final response = await _apiClient.get(ApiEndpoints.scanCandidates(sessionId));
    final list = response.data['data'] as List?;
    return list?.map((c) => ScanCandidateModel.fromJson(c)).toList() ?? const [];
  }

  Future<ScanCandidateModel> updateCandidate(String candidateId, Map<String, dynamic> data) async {
    final response = await _apiClient.patch(
      '${ApiEndpoints.scans}candidates/$candidateId/',
      data: data,
    );
    return ScanCandidateModel.fromJson(response.data['data']);
  }

  Future<void> deleteCandidate(String candidateId) async {
    await _apiClient.delete('${ApiEndpoints.scans}candidates/$candidateId/');
  }

  Future<List<GroceryModel>> confirmScan(String sessionId, List<String> candidateIds, String idempotencyKey) async {
    final response = await _apiClient.post(
      ApiEndpoints.confirmScan(sessionId),
      data: {
        'candidate_ids': candidateIds,
        'idempotency_key': idempotencyKey,
      },
    );
    final list = response.data['data'] as List?;
    return list?.map((i) => GroceryModel.fromJson(i)).toList() ?? const [];
  }
}
