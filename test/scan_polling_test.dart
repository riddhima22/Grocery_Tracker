import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:grocery_track/features/scan/model/scan_session_model.dart';
import 'package:grocery_track/features/scan/model/scan_candidate_model.dart';
import 'package:grocery_track/features/scan/providers/scan_provider.dart';
import 'package:grocery_track/features/scan/repository/scan_repository.dart';

class MockScanRepository extends ScanRepository {
  int pollCount = 0;
  final String targetFinalStatus;
  final String failureErrorMessage;

  MockScanRepository({
    this.targetFinalStatus = 'completed',
    this.failureErrorMessage = '',
  });

  @override
  Future<ScanSessionModel> createScanSession(List<XFile> images) async {
    return const ScanSessionModel(
      id: 'session-async-123',
      status: 'processing',
      imageCount: 1,
      successfulImageCount: 0,
      failedImageCount: 0,
      candidateCount: 0,
      images: [],
    );
  }

  @override
  Future<ScanSessionModel> getScanSession(String id) async {
    pollCount++;
    if (pollCount >= 2) {
      return ScanSessionModel(
        id: id,
        status: targetFinalStatus,
        imageCount: 1,
        successfulImageCount: targetFinalStatus == 'completed' ? 1 : 0,
        failedImageCount: targetFinalStatus == 'failed' ? 1 : 0,
        candidateCount: targetFinalStatus == 'completed' ? 1 : 0,
        errorMessage: failureErrorMessage,
        images: targetFinalStatus == 'failed'
            ? [
                ScanImageModel(
                  id: 'img-1',
                  status: 'failed',
                  errorMessage: failureErrorMessage,
                )
              ]
            : [],
      );
    }
    return ScanSessionModel(
      id: id,
      status: 'processing',
      imageCount: 1,
      successfulImageCount: 0,
      failedImageCount: 0,
      candidateCount: 0,
      images: [],
    );
  }

  @override
  Future<List<ScanCandidateModel>> getCandidates(String sessionId) async {
    return [
      const ScanCandidateModel(
        id: 'cand-1',
        scanSession: 'session-async-123',
        name: 'Whole Milk',
        brand: 'DairyBest',
        description: 'Fresh cow milk',
        category: 'Dairy',
        quantity: 1.0,
        unit: 'bottle',
        storageZone: 'fridge',
        confidence: 'High',
        validationWarnings: [],
        selected: true,
      ),
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ScanProvider Polling & 202 Flow Tests', () {
    test('transitions from uploading to analyzing and review upon polling completion', () async {
      final mockRepo = MockScanRepository(targetFinalStatus: 'completed');
      final provider = ScanProvider(scanRepository: mockRepo);

      final dummyFile = XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'groceries.jpg');
      provider.addImages([dummyFile]);

      expect(provider.uiState, ScanUIState.idle);
      expect(provider.selectedImages.length, 1);

      // Start analysis (creates 202 processing session)
      await provider.startAnalysis();
      expect(provider.uiState, ScanUIState.analyzing);
      expect(provider.currentSession?.status, 'processing');

      // Wait for timer ticks (2 ticks needed for targetFinalStatus)
      await Future.delayed(const Duration(milliseconds: 4500));

      expect(provider.uiState, ScanUIState.review);
      expect(provider.candidates.length, 1);
      expect(provider.candidates.first.name, 'Whole Milk');
      expect(provider.candidateSelection['cand-1'], true);

      provider.clearImages();
    });

    test('transitions to error state with clear message when scan session fails', () async {
      final mockRepo = MockScanRepository(
        targetFinalStatus: 'failed',
        failureErrorMessage: 'Image resolution too low or corrupted.',
      );
      final provider = ScanProvider(scanRepository: mockRepo);

      final dummyFile = XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'groceries.jpg');
      provider.addImages([dummyFile]);

      await provider.startAnalysis();
      expect(provider.uiState, ScanUIState.analyzing);

      // Wait for timer ticks
      await Future.delayed(const Duration(milliseconds: 4500));

      expect(provider.uiState, ScanUIState.error);
      expect(provider.errorMessage, contains('Image resolution too low or corrupted.'));

      provider.clearImages();
    });
  });
}
