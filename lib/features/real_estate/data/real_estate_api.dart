import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/files/local_image_file.dart';
import '../../auth/state/auth_controller.dart';
import '../models/real_estate_models.dart';

final realEstateApiProvider = Provider<RealEstateApi>((ref) {
  return RealEstateApi(ref.read(dioClientProvider).dio);
});

class RealEstateApi {
  final Dio dio;

  RealEstateApi(this.dio);

  Future<List<Map<String, dynamic>>> listListings(
    RealEstateListingQuery query, {
    int limit = 24,
    int offset = 0,
  }) async {
    final response = await dio.get(
      '/api/real-estate/listings',
      queryParameters: query.toJson(limit: limit, offset: offset),
    );
    final raw = response.data;
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> getListing(int listingId) async {
    final response = await dio.get('/api/real-estate/listings/$listingId');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<Map<String, dynamic>>> listSimilarListings(
    int listingId, {
    int limit = 6,
  }) async {
    final response = await dio.get(
      '/api/real-estate/listings/$listingId/similar',
      queryParameters: {'limit': limit},
    );
    final raw = response.data;
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> listSavedListings({
    int limit = 40,
    int offset = 0,
  }) async {
    final response = await dio.get(
      '/api/real-estate/saved',
      queryParameters: {'limit': limit, 'offset': offset},
    );
    final raw = response.data;
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  Future<bool> saveListing(int listingId) async {
    final response = await dio.post('/api/real-estate/listings/$listingId/save');
    final raw = response.data;
    if (raw is! Map) return true;
    return raw['saved'] != false;
  }

  Future<bool> unsaveListing(int listingId) async {
    final response = await dio.delete(
      '/api/real-estate/listings/$listingId/save',
    );
    final raw = response.data;
    if (raw is! Map) return false;
    return raw['saved'] == true;
  }

  Future<Map<String, dynamic>> workspace() async {
    final response = await dio.get('/api/real-estate/workspace');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> createListing(
    Map<String, dynamic> body, {
    List<LocalImageFile> imageFiles = const [],
  }) async {
    final map = <String, dynamic>{};
    body.forEach((key, value) {
      if (value == null) return;
      map[key] = value;
    });
    if (imageFiles.isNotEmpty) {
      final files = <MultipartFile>[];
      for (final file in imageFiles) {
        files.add(await file.toMultipartFile());
      }
      map['imageFiles'] = files;
    }
    final response = await dio.post(
      '/api/real-estate/listings',
      data: FormData.fromMap(map),
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> updateListing(
    int listingId,
    Map<String, dynamic> body, {
    List<LocalImageFile> imageFiles = const [],
  }) async {
    final map = <String, dynamic>{};
    body.forEach((key, value) {
      if (value == null) return;
      map[key] = value;
    });
    if (imageFiles.isNotEmpty) {
      final files = <MultipartFile>[];
      for (final file in imageFiles) {
        files.add(await file.toMultipartFile());
      }
      map['imageFiles'] = files;
    }
    final response = await dio.patch(
      '/api/real-estate/listings/$listingId',
      data: FormData.fromMap(map),
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> markStatus(
    int listingId, {
    required String nextStatus,
    String? note,
  }) async {
    await dio.post(
      '/api/real-estate/listings/$listingId/mark-status',
      data: {
        'nextStatus': nextStatus,
        if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
      },
    );
  }

  Future<List<Map<String, dynamic>>> listPendingAdminListings({
    int limit = 30,
    int offset = 0,
  }) async {
    final response = await dio.get(
      '/api/admin/real-estate/listings/pending',
      queryParameters: {'limit': limit, 'offset': offset},
    );
    final raw = response.data;
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  Future<void> approveListing(int listingId, {String? reviewNote}) async {
    await dio.patch(
      '/api/admin/real-estate/listings/$listingId/approve',
      data: {
        if ((reviewNote ?? '').trim().isNotEmpty) 'reviewNote': reviewNote!.trim(),
      },
    );
  }

  Future<void> rejectListing(int listingId, {String? reviewNote}) async {
    await dio.patch(
      '/api/admin/real-estate/listings/$listingId/reject',
      data: {
        if ((reviewNote ?? '').trim().isNotEmpty) 'reviewNote': reviewNote!.trim(),
      },
    );
  }
}
