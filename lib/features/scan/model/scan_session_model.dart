class ScanImageModel {
  final String id;
  final String status;
  final String errorMessage;

  const ScanImageModel({
    required this.id,
    required this.status,
    required this.errorMessage,
  });

  factory ScanImageModel.fromJson(Map<String, dynamic> json) {
    return ScanImageModel(
      id: json['id'] ?? '',
      status: json['status'] ?? 'pending',
      errorMessage: json['error_message'] ?? '',
    );
  }
}

class ScanSessionModel {
  final String id;
  final String status;
  final int imageCount;
  final int successfulImageCount;
  final int failedImageCount;
  final int candidateCount;
  final String? idempotencyKey;
  final DateTime? completedAt;
  final List<ScanImageModel> images;

  const ScanSessionModel({
    required this.id,
    required this.status,
    required this.imageCount,
    required this.successfulImageCount,
    required this.failedImageCount,
    required this.candidateCount,
    this.idempotencyKey,
    this.completedAt,
    required this.images,
  });

  factory ScanSessionModel.fromJson(Map<String, dynamic> json) {
    return ScanSessionModel(
      id: json['id'] ?? '',
      status: json['status'] ?? 'pending',
      imageCount: json['image_count'] ?? 0,
      successfulImageCount: json['successful_image_count'] ?? 0,
      failedImageCount: json['failed_image_count'] ?? 0,
      candidateCount: json['candidate_count'] ?? 0,
      idempotencyKey: json['idempotency_key'],
      completedAt: json['completed_at'] != null ? DateTime.tryParse(json['completed_at']) : null,
      images: (json['images'] as List?)?.map((i) => ScanImageModel.fromJson(i)).toList() ?? const [],
    );
  }
}
