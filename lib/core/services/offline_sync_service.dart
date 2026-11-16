import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';
import '../utils/app_logger.dart';

class SyncOperation {
  final String id;
  final String endpoint;
  final String method;
  final Map<String, dynamic>? data;
  final int timestamp;

  SyncOperation({
    required this.id,
    required this.endpoint,
    required this.method,
    this.data,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'endpoint': endpoint,
    'method': method,
    'data': data,
    'timestamp': timestamp,
  };

  factory SyncOperation.fromJson(Map<String, dynamic> json) {
    return SyncOperation(
      id: json['id'] ?? '',
      endpoint: json['endpoint'] ?? '',
      method: json['method'] ?? 'POST',
      data: json['data'] != null
          ? Map<String, dynamic>.from(json['data'])
          : null,
      timestamp: json['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}

class OfflineSyncService {
  static final OfflineSyncService _instance = OfflineSyncService._internal();
  factory OfflineSyncService() => _instance;
  OfflineSyncService._internal();

  static const String _keyQueue = 'offline_sync_queue';
  static const String _keyCachePrefix = 'offline_cache_';
  final ApiClient _apiClient = ApiClient();
  final Connectivity _connectivity = Connectivity();
  bool _isSyncing = false;

  void initialize() {
    _connectivity.onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) {
      if (results.isNotEmpty && results.first != ConnectivityResult.none) {
        AppLogger.info(
          'Connection restored! Starting background synchronization...',
        );
        syncPendingOperations();
      }
    });
  }

  Future<bool> isConnected() async {
    final results = await _connectivity.checkConnectivity();
    return results.isNotEmpty && results.first != ConnectivityResult.none;
  }

  /// Cache response data offline
  Future<void> cacheData(String key, dynamic data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_keyCachePrefix$key', jsonEncode(data));
    } catch (e) {
      AppLogger.error('Failed to cache data offline for $key', e);
    }
  }

  /// Fetch offline cached data
  Future<dynamic> getCachedData(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_keyCachePrefix$key');
      if (raw != null) {
        return jsonDecode(raw);
      }
    } catch (e) {
      AppLogger.error('Failed to read offline cache for $key', e);
    }
    return null;
  }

  /// Queue a mutation operation to be processed later
  Future<void> enqueueOperation({
    required String endpoint,
    required String method,
    Map<String, dynamic>? data,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawQueue = prefs.getStringList(_keyQueue) ?? [];

      final operation = SyncOperation(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        endpoint: endpoint,
        method: method,
        data: data,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      rawQueue.add(jsonEncode(operation.toJson()));
      await prefs.setStringList(_keyQueue, rawQueue);
      AppLogger.info('Queued offline mutation operation: $method $endpoint');
    } catch (e) {
      AppLogger.error('Failed to enqueue offline operation', e);
    }
  }

  /// Sync all pending queued operations to backend
  Future<void> syncPendingOperations() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final rawQueue = prefs.getStringList(_keyQueue) ?? [];
      if (rawQueue.isEmpty) {
        _isSyncing = false;
        return;
      }

      AppLogger.info(
        'Synchronizing ${rawQueue.length} pending offline operations...',
      );
      List<String> failedQueue = [];

      for (var rawOp in rawQueue) {
        final op = SyncOperation.fromJson(jsonDecode(rawOp));
        bool success = false;

        try {
          if (op.method == 'POST') {
            await _apiClient.post(op.endpoint, data: op.data);
            success = true;
          } else if (op.method == 'PATCH') {
            await _apiClient.patch(op.endpoint, data: op.data);
            success = true;
          } else if (op.method == 'DELETE') {
            await _apiClient.delete(op.endpoint);
            success = true;
          }
        } catch (e) {
          AppLogger.error(
            'Failed to synchronize pending operation ${op.method} ${op.endpoint}, enqueuing again',
            e,
          );
          success = false;
        }

        if (!success) {
          failedQueue.add(rawOp);
        }
      }

      await prefs.setStringList(_keyQueue, failedQueue);
      AppLogger.info(
        'Synchronization complete. Remaining in queue: ${failedQueue.length}',
      );
    } catch (e) {
      AppLogger.error('Sync queue loop error', e);
    } finally {
      _isSyncing = false;
    }
  }
}
