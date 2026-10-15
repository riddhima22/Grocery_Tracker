import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../../data/models/scan_session_model.dart';
import '../../../data/models/scan_candidate_model.dart';
import '../../../data/models/grocery_model.dart';
import '../../../data/repositories/scan_repository.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/services/unit_classification_service.dart';
import '../../kitchen/providers/kitchen_provider.dart';

enum ScanUIState {
  idle,
  selecting,
  uploading,
  analyzing,
  review,
  success,
  error,
}

class ScanProvider extends ChangeNotifier {
  final ScanRepository _scanRepository = ScanRepository();

  final List<XFile> _selectedImages = [];
  ScanUIState _uiState = ScanUIState.idle;
  String? _errorMessage;
  String _scanStageMessage = 'Uploading image...';
  double _scanProgress = 0.2;

  ScanSessionModel? _currentSession;
  List<ScanCandidateModel> _candidates = [];
  List<GroceryModel> _confirmedGroceries = [];

  // Selection map for confirming review candidates
  final Map<String, bool> _candidateSelection = {};
  Timer? _pollingTimer;

  List<XFile> get selectedImages => _selectedImages;
  ScanUIState get uiState => _uiState;
  String? get errorMessage => _errorMessage;
  String get scanStageMessage => _scanStageMessage;
  double get scanProgress => _scanProgress;
  ScanSessionModel? get currentSession => _currentSession;
  List<ScanCandidateModel> get candidates => _candidates;
  List<GroceryModel> get confirmedGroceries => _confirmedGroceries;
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
    _stopPolling();
    _selectedImages.clear();
    _candidates.clear();
    _candidateSelection.clear();
    _currentSession = null;
    _errorMessage = null;
    _scanStageMessage = 'Uploading image...';
    _scanProgress = 0.0;
    _uiState = ScanUIState.idle;
    notifyListeners();
  }

  /// Resets scan provider state completely (e.g. on auth changes)
  void resetState() => clearImages();

  /// Clears any stale error state so opening the scan view starts in idle mode
  void resetIfError() {
    if (_uiState == ScanUIState.error) {
      clearImages();
    }
  }

  Future<void> startAnalysis() async {
    if (_selectedImages.isEmpty) return;

    _stopPolling();
    _uiState = ScanUIState.uploading;
    _errorMessage = null;
    _scanStageMessage = 'Uploading image...';
    _scanProgress = 0.25;
    notifyListeners();

    try {
      // 1. Upload files to backend and create session
      _currentSession = await _scanRepository.createScanSession(
        _selectedImages,
      );
      _uiState = ScanUIState.analyzing;
      _scanStageMessage = 'Analyzing image...';
      _scanProgress = 0.50;
      notifyListeners();

      // 2. Start polling session progress status
      _startPolling();
    } catch (e, stack) {
      AppLogger.error('Failed to start scan analysis', e, stack);
      _errorMessage = e.toString();
      _uiState = ScanUIState.error;
      notifyListeners();
    }
  }

  void _startPolling() {
    _stopPolling();

    int attempts = 0;
    const maxAttempts = 45; // Max 90 seconds (2s interval)

    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (_currentSession == null) {
        timer.cancel();
        return;
      }

      attempts++;

      // Update progressive UI messages based on elapsed time
      if (attempts == 3) {
        _scanStageMessage = 'Identifying items...';
        _scanProgress = 0.70;
        notifyListeners();
      } else if (attempts == 7) {
        _scanStageMessage = 'Almost done...';
        _scanProgress = 0.88;
        notifyListeners();
      }

      if (attempts > maxAttempts) {
        timer.cancel();
        _errorMessage =
            "Analysis is taking longer than expected. Please try again.";
        _uiState = ScanUIState.error;
        notifyListeners();
        return;
      }

      try {
        final session = await _scanRepository.getScanSession(
          _currentSession!.id,
        );
        _currentSession = session;

        if (session.status == 'completed' ||
            session.status == 'partial_success' ||
            session.status == 'partial') {
          timer.cancel();
          _scanProgress = 1.0;

          // Load detected candidates
          _candidates = await _scanRepository.getCandidates(session.id);
          AppLogger.info(
            'Scan completed for session ${session.id}: found ${_candidates.length} item(s)',
          );

          // Default all candidates to selected
          for (var c in _candidates) {
            _candidateSelection[c.id] = c.selected;
          }

          _uiState = ScanUIState.review;
          notifyListeners();
        } else if (session.status == 'failed') {
          timer.cancel();
          final firstError = session.images
              .firstWhere(
                (img) => img.errorMessage.isNotEmpty,
                orElse: () =>
                    const ScanImageModel(id: '', status: '', errorMessage: ''),
              )
              .errorMessage;

          _errorMessage = firstError.isNotEmpty
              ? firstError
              : "Analysis could not identify grocery items. Please try a clearer picture.";
          _uiState = ScanUIState.error;
          notifyListeners();
        }
      } catch (e) {
        // Log error but keep polling until max attempts
        AppLogger.warning('Polling session status attempt $attempts error: $e');
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
    final index = _candidates.indexWhere((c) => c.id == id);
    if (index != -1) {
      final old = _candidates[index];
      DateTime? newExpiry = old.expiryDate;
      if (data.containsKey('expiry_date')) {
        final exp = data['expiry_date'];
        if (exp is DateTime) {
          newExpiry = exp;
        } else if (exp is String) {
          newExpiry = DateTime.tryParse(exp);
        } else if (exp == null) {
          newExpiry = null;
        }
      }

      double? newQty = old.quantity;
      if (data.containsKey('quantity')) {
        newQty =
            double.tryParse(data['quantity']?.toString() ?? '') ?? old.quantity;
      }

      _candidates[index] = old.copyWith(
        name: data['name']?.toString(),
        brand: data['brand']?.toString(),
        category: data['category']?.toString(),
        description: data['description']?.toString(),
        storageZone: data['storage_zone']?.toString(),
        quantity: newQty,
        unit: data['unit']?.toString(),
        unitCategory: data['unit_category']?.toString(),
        packageType: data['package_type']?.toString(),
        netContentValue: double.tryParse(
          data['net_content_value']?.toString() ?? '',
        ),
        netContentUnit: data['net_content_unit']?.toString(),
        unitConfidence: data['unit_confidence']?.toString(),
        isUncertain: data['is_uncertain'] == true,
        expiryDate: newExpiry,
      );
      // Immediately notify UI for instant 0ms responsiveness
      notifyListeners();
    }

    try {
      final updated = await _scanRepository.updateCandidate(id, data);
      final idx = _candidates.indexWhere((c) => c.id == id);
      if (idx != -1) {
        _candidates[idx] = updated;
        notifyListeners();
      }
    } catch (e) {
      AppLogger.error('Failed to update candidate details', e);
    }
  }

  void updateCandidateQuantity(String id, double newQty) {
    updateCandidate(id, {'quantity': newQty});
  }

  void updateCandidateUnit(String id, String newUnit) {
    final index = _candidates.indexWhere((c) => c.id == id);
    if (index == -1) return;
    final old = _candidates[index];
    final convertedQty =
        UnitClassificationService.convertQuantity(
          old.quantity,
          old.unit,
          newUnit,
        ) ??
        old.quantity;
    final cat =
        UnitClassificationService.unitCategories[newUnit] ?? old.unitCategory;
    updateCandidate(id, {
      'unit': newUnit,
      'quantity': convertedQty,
      'unit_category': cat,
      'unit_confidence': 'High',
      'is_uncertain': false,
    });
  }

  void removeCandidate(String id) {
    _candidates.removeWhere((c) => c.id == id);
    _candidateSelection.remove(id);
    notifyListeners();
    // Delete on server asynchronously
    _scanRepository.deleteCandidate(id).catchError((_) {});
  }

  Future<bool> confirmSelectedCandidates(BuildContext context) async {
    if (_candidates.isEmpty) return false;

    final sessionId = _currentSession?.id ?? _candidates.first.scanSession;
    if (sessionId.isEmpty) return false;

    // Resolve selected IDs (any item not explicitly false is considered selected)
    List<String> selectedIds = _candidates
        .where((c) => (_candidateSelection[c.id] ?? true) == true)
        .map((c) => c.id)
        .toList();

    // Fallback: If no candidate was checked, select all available candidates
    if (selectedIds.isEmpty) {
      selectedIds = _candidates.map((c) => c.id).toList();
    }

    _uiState = ScanUIState.uploading;
    _scanStageMessage = 'Saving items to your kitchen...';
    _scanProgress = 0.85;
    _errorMessage = null;
    notifyListeners();

    try {
      final idempotencyKey = const Uuid().v4();
      final confirmed = await _scanRepository.confirmScan(
        sessionId,
        selectedIds,
        idempotencyKey,
      );

      _confirmedGroceries = confirmed;
      _uiState = ScanUIState.success;
      notifyListeners();

      // Immediately inject confirmed items into KitchenProvider and force refresh
      if (context.mounted) {
        final kitchen = context.read<KitchenProvider>();
        if (confirmed.isNotEmpty) {
          kitchen.addConfirmedGroceries(confirmed);
        }
        await kitchen.fetchKitchenItems(forceRefresh: true);
      }
      return true;
    } catch (e, stack) {
      AppLogger.error('Failed to confirm scan candidates', e, stack);
      _errorMessage = 'Failed to save items to kitchen: ${e.toString()}';
      _uiState = ScanUIState.review;
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
