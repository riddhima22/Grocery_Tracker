import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../../data/models/scan_session_model.dart';
import '../../../data/models/scan_candidate_model.dart';
import '../../../data/repositories/scan_repository.dart';
import '../../../core/utils/app_logger.dart';

enum ScanUIState { idle, selecting, uploading, analyzing, review, success, error }

class ScanProvider extends ChangeNotifier {
  final ScanRepository _scanRepository = ScanRepository();

  final List<XFile> _selectedImages = [];
  ScanUIState _uiState = ScanUIState.idle;
  String? _errorMessage;
  
  ScanSessionModel? _currentSession;
  List<ScanCandidateModel> _candidates = [];
  
  // Selection map for confirming review candidates
  final Map<String, bool> _candidateSelection = {};
  Timer? _pollingTimer;

  List<XFile> get selectedImages => _selectedImages;
  ScanUIState get uiState => _uiState;
  String? get errorMessage => _errorMessage;
  ScanSessionModel? get currentSession => _currentSession;
  List<ScanCandidateModel> get candidates => _candidates;
  Map<String, bool> get candidateSelection => _candidateSelection;

  void addImages(List<XFile> files) {
    _selectedImages.addAll(files);
    notifyListeners();
  }

  void removeImage(int index) {
    if (index >= 0 && index < _selectedImages.length) {
      _selectedImages.removeAt(index);
      notifyListeners();
    }
  }

  void clearImages() {
    _selectedImages.clear();
    _candidates.clear();
    _candidateSelection.clear();
    _uiState = ScanUIState.idle;
    _errorMessage = null;
    _stopPolling();
    notifyListeners();
  }

  Future<void> startAnalysis() async {
    if (_selectedImages.isEmpty) return;
    
    _uiState = ScanUIState.uploading;
    _errorMessage = null;
    notifyListeners();

    try {
      // 1. Upload files to Django and start session
      _currentSession = await _scanRepository.createScanSession(_selectedImages);
      _uiState = ScanUIState.analyzing;
      notifyListeners();

      // 2. Start polling session progress status
      _startPolling();
    } catch (e) {
      _errorMessage = e.toString();
      _uiState = ScanUIState.error;
      notifyListeners();
    }
  }

  void _startPolling() {
    _stopPolling();
    
    int attempts = 0;
    const maxAttempts = 60; // Max 120 seconds (2s interval)
    
    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (_currentSession == null) {
        timer.cancel();
        return;
      }
      
      attempts++;
      if (attempts > maxAttempts) {
        timer.cancel();
        _errorMessage = "Analysis timed out. Please try again.";
        _uiState = ScanUIState.error;
        notifyListeners();
        return;
      }

      try {
        final session = await _scanRepository.getScanSession(_currentSession!.id);
        _currentSession = session;
        
        if (session.status == 'completed' || session.status == 'partial_success' || session.status == 'partial') {
          timer.cancel();
          // Load candidates
          _candidates = await _scanRepository.getCandidates(session.id);
          
          // Default all candidates to selected
          for (var c in _candidates) {
            _candidateSelection[c.id] = c.selected;
          }
          
          _uiState = ScanUIState.review;
          notifyListeners();
        } else if (session.status == 'failed') {
          timer.cancel();
          final firstError = session.images.firstWhere(
            (img) => img.errorMessage.isNotEmpty,
            orElse: () => const ScanImageModel(id: '', status: '', errorMessage: ''),
          ).errorMessage;
          _errorMessage = firstError.isNotEmpty ? firstError : "Image analysis failed. Please try a clearer picture.";
          _uiState = ScanUIState.error;
          notifyListeners();
        }
      } catch (e) {
        // Log error but keep polling until timeout
        AppLogger.error('Error polling session status', e);
      }
    });
  }

  void _stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  void toggleCandidateSelection(String id, bool selected) {
    _candidateSelection[id] = selected;
    notifyListeners();
  }

  Future<void> updateCandidate(String id, Map<String, dynamic> data) async {
    try {
      final updated = await _scanRepository.updateCandidate(id, data);
      final index = _candidates.indexWhere((c) => c.id == id);
      if (index != -1) {
        _candidates[index] = updated;
        notifyListeners();
      }
    } catch (e) {
      AppLogger.error('Failed to update candidate details', e);
    }
  }

  void removeCandidate(String id) {
    _candidates.removeWhere((c) => c.id == id);
    _candidateSelection.remove(id);
    notifyListeners();
    // Delete on server asynchronously
    _scanRepository.deleteCandidate(id).catchError((_) {});
  }

  Future<bool> confirmSelectedCandidates(BuildContext context) async {
    if (_currentSession == null) return false;

    final selectedIds = _candidates
        .where((c) => _candidateSelection[c.id] == true)
        .map((c) => c.id)
        .toList();

    if (selectedIds.isEmpty) return false;

    _uiState = ScanUIState.uploading; // loading indicator
    notifyListeners();

    try {
      final idempotencyKey = const Uuid().v4();
      await _scanRepository.confirmScan(
        _currentSession!.id,
        selectedIds,
        idempotencyKey,
      );
      _uiState = ScanUIState.success;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _uiState = ScanUIState.review; // fallback to review list with banner
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }
}
