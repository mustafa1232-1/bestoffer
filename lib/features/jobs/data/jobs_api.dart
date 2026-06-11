import 'package:dio/dio.dart';

import '../../../core/files/local_media_file.dart';

class JobsApi {
  final Dio dio;

  JobsApi(this.dio);

  Future<Map<String, dynamic>> listJobs({
    String? search,
    String? category,
    String? activityType,
    String? department,
    String? city,
    String? area,
    String? employmentType,
    String? workplaceType,
    String? experienceLevel,
    String? status,
    String? sort,
    double? minSalary,
    double? maxSalary,
    bool onlyOpen = true,
    int page = 1,
    int limit = 20,
  }) async {
    final response = await dio.get(
      '/api/jobs',
      queryParameters: {
        if (_valid(search)) 'search': search!.trim(),
        if (_valid(category)) 'category': category!.trim(),
        if (_valid(activityType)) 'activityType': activityType!.trim(),
        if (_valid(department)) 'department': department!.trim(),
        if (_valid(city)) 'city': city!.trim(),
        if (_valid(area)) 'area': area!.trim(),
        if (_valid(employmentType)) 'employmentType': employmentType!.trim(),
        if (_valid(workplaceType)) 'workplaceType': workplaceType!.trim(),
        if (_valid(experienceLevel)) 'experienceLevel': experienceLevel!.trim(),
        if (_valid(status)) 'status': status!.trim(),
        if (_valid(sort)) 'sort': sort!.trim(),
        ...?(minSalary == null ? null : {'minSalary': minSalary}),
        ...?(maxSalary == null ? null : {'maxSalary': maxSalary}),
        'onlyOpen': onlyOpen ? 1 : 0,
        'page': page,
        'limit': limit,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listManagedJobs({
    String? search,
    String? category,
    String? activityType,
    String? department,
    String? city,
    String? area,
    String? employmentType,
    String? workplaceType,
    String? experienceLevel,
    String? status,
    String? sort,
    double? minSalary,
    double? maxSalary,
    bool onlyOpen = false,
    int page = 1,
    int limit = 20,
  }) async {
    final response = await dio.get(
      '/api/jobs/manage/mine',
      queryParameters: {
        if (_valid(search)) 'search': search!.trim(),
        if (_valid(category)) 'category': category!.trim(),
        if (_valid(activityType)) 'activityType': activityType!.trim(),
        if (_valid(department)) 'department': department!.trim(),
        if (_valid(city)) 'city': city!.trim(),
        if (_valid(area)) 'area': area!.trim(),
        if (_valid(employmentType)) 'employmentType': employmentType!.trim(),
        if (_valid(workplaceType)) 'workplaceType': workplaceType!.trim(),
        if (_valid(experienceLevel)) 'experienceLevel': experienceLevel!.trim(),
        if (_valid(status)) 'status': status!.trim(),
        if (_valid(sort)) 'sort': sort!.trim(),
        ...?(minSalary == null ? null : {'minSalary': minSalary}),
        ...?(maxSalary == null ? null : {'maxSalary': maxSalary}),
        'onlyOpen': onlyOpen ? 1 : 0,
        'page': page,
        'limit': limit,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listAdminReadableJobs({
    String? search,
    String? category,
    String? activityType,
    String? department,
    String? city,
    String? area,
    String? employmentType,
    String? workplaceType,
    String? experienceLevel,
    String? status,
    String? sort,
    double? minSalary,
    double? maxSalary,
    bool onlyOpen = true,
    int page = 1,
    int limit = 20,
  }) async {
    final response = await dio.get(
      '/api/jobs/manage/read-only',
      queryParameters: {
        if (_valid(search)) 'search': search!.trim(),
        if (_valid(category)) 'category': category!.trim(),
        if (_valid(activityType)) 'activityType': activityType!.trim(),
        if (_valid(department)) 'department': department!.trim(),
        if (_valid(city)) 'city': city!.trim(),
        if (_valid(area)) 'area': area!.trim(),
        if (_valid(employmentType)) 'employmentType': employmentType!.trim(),
        if (_valid(workplaceType)) 'workplaceType': workplaceType!.trim(),
        if (_valid(experienceLevel)) 'experienceLevel': experienceLevel!.trim(),
        if (_valid(status)) 'status': status!.trim(),
        if (_valid(sort)) 'sort': sort!.trim(),
        ...?(minSalary == null ? null : {'minSalary': minSalary}),
        ...?(maxSalary == null ? null : {'maxSalary': maxSalary}),
        'onlyOpen': onlyOpen ? 1 : 0,
        'page': page,
        'limit': limit,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> getJobById(int jobId) async {
    final response = await dio.get('/api/jobs/$jobId');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> createJob(Map<String, dynamic> body) async {
    final response = await dio.post('/api/jobs', data: body);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> updateJob(
    int jobId,
    Map<String, dynamic> body,
  ) async {
    final response = await dio.patch('/api/jobs/$jobId', data: body);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> updateJobStatus({
    required int jobId,
    required String status,
  }) async {
    final response = await dio.patch(
      '/api/jobs/$jobId/status',
      data: {'status': status},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> deleteJob(int jobId) async {
    await dio.delete('/api/jobs/$jobId');
  }

  Future<Map<String, dynamic>> applyToJob({
    required int jobId,
    String? message,
    String? phone,
    String? email,
    String? resumeUrl,
    double? expectedSalary,
    LocalMediaFile? attachmentFile,
  }) async {
    final fields = <String, dynamic>{
      if (_valid(message)) 'message': message!.trim(),
      if (_valid(phone)) 'phone': phone!.trim(),
      if (_valid(email)) 'email': email!.trim(),
      if (_valid(resumeUrl)) 'resumeUrl': resumeUrl!.trim(),
      ...?(expectedSalary == null
          ? null
          : {'expectedSalary': expectedSalary.toString()}),
    };

    final response = attachmentFile == null
        ? await dio.post('/api/jobs/$jobId/apply', data: fields)
        : await dio.post(
            '/api/jobs/$jobId/apply',
            data: FormData.fromMap({
              ...fields,
              'attachmentFile': await attachmentFile.toMultipartFile(),
            }),
          );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listJobApplications({
    required int jobId,
    String? status,
    int page = 1,
    int limit = 30,
  }) async {
    final response = await dio.get(
      '/api/jobs/$jobId/applications',
      queryParameters: {
        if (_valid(status)) 'status': status!.trim(),
        'page': page,
        'limit': limit,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listMyApplications({
    String? status,
    int page = 1,
    int limit = 40,
  }) async {
    final response = await dio.get(
      '/api/jobs/mine/applications',
      queryParameters: {
        if (_valid(status)) 'status': status!.trim(),
        'page': page,
        'limit': limit,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listJobRecommendations({
    required int jobId,
  }) async {
    final response = await dio.get('/api/jobs/$jobId/recommendations');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listRecommendationCandidatesForJob({
    required int jobId,
    String? search,
    int limit = 40,
  }) async {
    final response = await dio.get(
      '/api/jobs/$jobId/recommendations/candidates',
      queryParameters: {
        if (_valid(search)) 'search': search!.trim(),
        'limit': limit,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> createJobRecommendation({
    required int jobId,
    int? sourceApplicationId,
    int? candidateUserId,
    String? candidateFullName,
    String? candidatePhone,
    String? candidateEmail,
    String? candidateWorkTitle,
    String? candidateWorkCompany,
    String? note,
    LocalMediaFile? attachmentFile,
  }) async {
    final fields = <String, dynamic>{
      ...?(sourceApplicationId == null
          ? null
          : {'sourceApplicationId': sourceApplicationId}),
      ...?(candidateUserId == null
          ? null
          : {'candidateUserId': candidateUserId}),
      if (_valid(candidateFullName))
        'candidateFullName': candidateFullName!.trim(),
      if (_valid(candidatePhone)) 'candidatePhone': candidatePhone!.trim(),
      if (_valid(candidateEmail)) 'candidateEmail': candidateEmail!.trim(),
      if (_valid(candidateWorkTitle))
        'candidateWorkTitle': candidateWorkTitle!.trim(),
      if (_valid(candidateWorkCompany))
        'candidateWorkCompany': candidateWorkCompany!.trim(),
      if (_valid(note)) 'note': note!.trim(),
    };

    final response = attachmentFile == null
        ? await dio.post('/api/jobs/$jobId/recommendations', data: fields)
        : await dio.post(
            '/api/jobs/$jobId/recommendations',
            data: FormData.fromMap({
              ...fields,
              'attachmentFile': await attachmentFile.toMultipartFile(),
            }),
          );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> acceptJobRecommendation({
    required int jobId,
    required int recommendationId,
    String? reason,
  }) async {
    final response = await dio.post(
      '/api/jobs/$jobId/recommendations/$recommendationId/accept',
      data: {if (_valid(reason)) 'reason': reason!.trim()},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> updateJobApplicationStatus({
    required int jobId,
    required int applicationId,
    required String status,
    String? reason,
    double? offerSalary,
    String? offerWorkHours,
    String? offerWorkDays,
    String? offerMessage,
    LocalMediaFile? offerAttachmentFile,
  }) async {
    final fields = <String, dynamic>{
      'status': status,
      if (_valid(reason)) 'reason': reason!.trim(),
      ...?(offerSalary == null
          ? null
          : {'offerSalary': offerSalary.toString()}),
      if (_valid(offerWorkHours)) 'offerWorkHours': offerWorkHours!.trim(),
      if (_valid(offerWorkDays)) 'offerWorkDays': offerWorkDays!.trim(),
      if (_valid(offerMessage)) 'offerMessage': offerMessage!.trim(),
    };
    final response = offerAttachmentFile == null
        ? await dio.patch(
            '/api/jobs/$jobId/applications/$applicationId/status',
            data: fields,
          )
        : await dio.patch(
            '/api/jobs/$jobId/applications/$applicationId/status',
            data: FormData.fromMap({
              ...fields,
              'attachmentFile': await offerAttachmentFile.toMultipartFile(),
            }),
          );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> acceptMyJobOffer({
    required int applicationId,
    LocalMediaFile? attachmentFile,
  }) async {
    final response = attachmentFile == null
        ? await dio.post('/api/jobs/applications/$applicationId/accept-offer')
        : await dio.post(
            '/api/jobs/applications/$applicationId/accept-offer',
            data: FormData.fromMap({
              'attachmentFile': await attachmentFile.toMultipartFile(),
            }),
          );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> withdrawMyApplication({
    required int applicationId,
    required String reason,
  }) async {
    final response = await dio.post(
      '/api/jobs/applications/$applicationId/withdraw',
      data: {'reason': reason.trim()},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listManagerApplications({
    String? search,
    String? status,
    String? category,
    String? activityType,
    String? department,
    int? jobId,
    int page = 1,
    int limit = 30,
  }) async {
    final response = await dio.get(
      '/api/jobs/applications/manage',
      queryParameters: {
        if (_valid(search)) 'search': search!.trim(),
        if (_valid(status)) 'status': status!.trim(),
        if (_valid(category)) 'category': category!.trim(),
        if (_valid(activityType)) 'activityType': activityType!.trim(),
        if (_valid(department)) 'department': department!.trim(),
        ...?(jobId == null ? null : {'jobId': jobId}),
        'page': page,
        'limit': limit,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listTalentPoolGroups({
    String? search,
    String? status,
    String? category,
    String? activityType,
    String? department,
    int? jobId,
  }) async {
    final response = await dio.get(
      '/api/jobs/applications/talent-pool',
      queryParameters: {
        if (_valid(search)) 'search': search!.trim(),
        if (_valid(status)) 'status': status!.trim(),
        if (_valid(category)) 'category': category!.trim(),
        if (_valid(activityType)) 'activityType': activityType!.trim(),
        if (_valid(department)) 'department': department!.trim(),
        ...?(jobId == null ? null : {'jobId': jobId}),
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listSuperAdminApplicationsMonitor({
    String? search,
    String? status,
    String? category,
    String? activityType,
    String? department,
    int? jobId,
    int page = 1,
    int limit = 60,
  }) async {
    final response = await dio.get(
      '/api/jobs/applications/monitor',
      queryParameters: {
        if (_valid(search)) 'search': search!.trim(),
        if (_valid(status)) 'status': status!.trim(),
        if (_valid(category)) 'category': category!.trim(),
        if (_valid(activityType)) 'activityType': activityType!.trim(),
        if (_valid(department)) 'department': department!.trim(),
        ...?(jobId == null ? null : {'jobId': jobId}),
        'page': page,
        'limit': limit,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> filterMeta() async {
    final response = await dio.get('/api/jobs/filters/meta');
    return Map<String, dynamic>.from(response.data as Map);
  }

  bool _valid(String? value) => value != null && value.trim().isNotEmpty;
}
