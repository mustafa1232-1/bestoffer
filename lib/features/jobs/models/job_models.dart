import '../../../core/utils/parsers.dart';

class JobPostModel {
  final int id;
  final String title;
  final String companyName;
  final String? companyLogoUrl;
  final String category;
  final String activityType;
  final String department;
  final String city;
  final String? area;
  final String workplaceType;
  final String employmentType;
  final String experienceLevel;
  final String? educationLevel;
  final double? salaryMin;
  final double? salaryMax;
  final String salaryCurrency;
  final String salaryPeriod;
  final bool salaryIsNegotiable;
  final int vacancies;
  final String description;
  final String? requirements;
  final String? responsibilities;
  final String? benefits;
  final List<String> skills;
  final String? contactPhone;
  final String? contactEmail;
  final String? applyUrl;
  final String status;
  final bool isFeatured;
  final DateTime? publishedAt;
  final DateTime? expiresAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int? merchantId;
  final String? merchantName;
  final String? merchantImageUrl;
  final bool hasApplied;
  final int applicationsCount;
  final bool canManage;

  const JobPostModel({
    required this.id,
    required this.title,
    required this.companyName,
    required this.companyLogoUrl,
    required this.category,
    required this.activityType,
    required this.department,
    required this.city,
    required this.area,
    required this.workplaceType,
    required this.employmentType,
    required this.experienceLevel,
    required this.educationLevel,
    required this.salaryMin,
    required this.salaryMax,
    required this.salaryCurrency,
    required this.salaryPeriod,
    required this.salaryIsNegotiable,
    required this.vacancies,
    required this.description,
    required this.requirements,
    required this.responsibilities,
    required this.benefits,
    required this.skills,
    required this.contactPhone,
    required this.contactEmail,
    required this.applyUrl,
    required this.status,
    required this.isFeatured,
    required this.publishedAt,
    required this.expiresAt,
    required this.createdAt,
    required this.updatedAt,
    required this.merchantId,
    required this.merchantName,
    required this.merchantImageUrl,
    required this.hasApplied,
    required this.applicationsCount,
    required this.canManage,
  });

  bool get isOpen {
    if (status != 'active') return false;
    final deadline = expiresAt;
    if (deadline == null) return true;
    return !deadline.isBefore(DateTime.now());
  }

  factory JobPostModel.fromJson(Map<String, dynamic> j) {
    final rawSkills = j['skills'];
    final skills = rawSkills is List
        ? rawSkills
              .map((e) => parseString(e))
              .where((item) => item.trim().isNotEmpty)
              .toList(growable: false)
        : const <String>[];

    return JobPostModel(
      id: parseInt(j['id']),
      title: parseString(j['title']),
      companyName: parseString(j['companyName'] ?? j['company_name']),
      companyLogoUrl: parseNullableString(
        j['companyLogoUrl'] ?? j['company_logo_url'],
      ),
      category: parseString(j['category']),
      activityType: parseString(
        j['activityType'] ?? j['activity_type'],
        fallback: 'general_business',
      ),
      department: parseString(j['department'], fallback: 'operations'),
      city: parseString(j['city']),
      area: parseNullableString(j['area']),
      workplaceType: parseString(
        j['workplaceType'] ?? j['workplace_type'],
        fallback: 'on_site',
      ),
      employmentType: parseString(
        j['employmentType'] ?? j['employment_type'],
        fallback: 'full_time',
      ),
      experienceLevel: parseString(
        j['experienceLevel'] ?? j['experience_level'],
        fallback: 'mid',
      ),
      educationLevel: parseNullableString(
        j['educationLevel'] ?? j['education_level'],
      ),
      salaryMin: j['salaryMin'] == null && j['salary_min'] == null
          ? null
          : parseDouble(j['salaryMin'] ?? j['salary_min']),
      salaryMax: j['salaryMax'] == null && j['salary_max'] == null
          ? null
          : parseDouble(j['salaryMax'] ?? j['salary_max']),
      salaryCurrency: parseString(
        j['salaryCurrency'] ?? j['salary_currency'],
        fallback: 'IQD',
      ),
      salaryPeriod: parseString(
        j['salaryPeriod'] ?? j['salary_period'],
        fallback: 'monthly',
      ),
      salaryIsNegotiable: parseBool(
        j['salaryIsNegotiable'] ?? j['salary_is_negotiable'],
        fallback: true,
      ),
      vacancies: parseInt(j['vacancies'], fallback: 1),
      description: parseString(j['description']),
      requirements: parseNullableString(j['requirements']),
      responsibilities: parseNullableString(j['responsibilities']),
      benefits: parseNullableString(j['benefits']),
      skills: skills,
      contactPhone: parseNullableString(
        j['contactPhone'] ?? j['contact_phone'],
      ),
      contactEmail: parseNullableString(
        j['contactEmail'] ?? j['contact_email'],
      ),
      applyUrl: parseNullableString(j['applyUrl'] ?? j['apply_url']),
      status: parseString(j['status'], fallback: 'active'),
      isFeatured: parseBool(
        j['isFeatured'] ?? j['is_featured'],
        fallback: false,
      ),
      publishedAt: parseNullableDateTime(j['publishedAt'] ?? j['published_at']),
      expiresAt: parseNullableDateTime(j['expiresAt'] ?? j['expires_at']),
      createdAt: parseNullableDateTime(j['createdAt'] ?? j['created_at']),
      updatedAt: parseNullableDateTime(j['updatedAt'] ?? j['updated_at']),
      merchantId: (j['merchantId'] ?? j['merchant_id']) == null
          ? null
          : parseInt(j['merchantId'] ?? j['merchant_id']),
      merchantName: parseNullableString(
        j['merchantName'] ?? j['merchant_name'],
      ),
      merchantImageUrl: parseNullableString(
        j['merchantImageUrl'] ?? j['merchant_image_url'],
      ),
      hasApplied: parseBool(j['hasApplied'] ?? j['has_applied']),
      applicationsCount: parseInt(
        j['applicationsCount'] ?? j['applications_count'],
      ),
      canManage: parseBool(j['canManage'] ?? j['can_manage']),
    );
  }

  JobPostModel copyWith({
    bool? hasApplied,
    String? status,
    int? applicationsCount,
  }) {
    return JobPostModel(
      id: id,
      title: title,
      companyName: companyName,
      companyLogoUrl: companyLogoUrl,
      category: category,
      activityType: activityType,
      department: department,
      city: city,
      area: area,
      workplaceType: workplaceType,
      employmentType: employmentType,
      experienceLevel: experienceLevel,
      educationLevel: educationLevel,
      salaryMin: salaryMin,
      salaryMax: salaryMax,
      salaryCurrency: salaryCurrency,
      salaryPeriod: salaryPeriod,
      salaryIsNegotiable: salaryIsNegotiable,
      vacancies: vacancies,
      description: description,
      requirements: requirements,
      responsibilities: responsibilities,
      benefits: benefits,
      skills: skills,
      contactPhone: contactPhone,
      contactEmail: contactEmail,
      applyUrl: applyUrl,
      status: status ?? this.status,
      isFeatured: isFeatured,
      publishedAt: publishedAt,
      expiresAt: expiresAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
      merchantId: merchantId,
      merchantName: merchantName,
      merchantImageUrl: merchantImageUrl,
      hasApplied: hasApplied ?? this.hasApplied,
      applicationsCount: applicationsCount ?? this.applicationsCount,
      canManage: canManage,
    );
  }
}

class JobFilterMetaModel {
  final List<String> categories;
  final List<String> cities;
  final List<String> areas;
  final List<String> activityTypes;
  final Map<String, List<String>> departmentsByActivity;
  final List<String> employmentTypes;
  final List<String> workplaceTypes;
  final List<String> experienceLevels;
  final List<String> salaryPeriods;
  final List<String> sortOptions;

  const JobFilterMetaModel({
    required this.categories,
    required this.cities,
    required this.areas,
    required this.activityTypes,
    required this.departmentsByActivity,
    required this.employmentTypes,
    required this.workplaceTypes,
    required this.experienceLevels,
    required this.salaryPeriods,
    required this.sortOptions,
  });

  factory JobFilterMetaModel.fromJson(Map<String, dynamic> j) {
    List<String> readList(dynamic value) {
      if (value is! List) return const <String>[];
      return value
          .map((e) => parseString(e))
          .where((item) => item.trim().isNotEmpty)
          .toList(growable: false);
    }

    final departmentsByActivity = <String, List<String>>{};
    final rawDepartments = j['departmentsByActivity'];
    if (rawDepartments is Map) {
      rawDepartments.forEach((key, value) {
        final activity = parseString(key);
        if (activity.trim().isEmpty) return;
        departmentsByActivity[activity] = readList(value);
      });
    }

    return JobFilterMetaModel(
      categories: readList(j['categories']),
      cities: readList(j['cities']),
      areas: readList(j['areas']),
      activityTypes: readList(j['activityTypes']),
      departmentsByActivity: departmentsByActivity,
      employmentTypes: readList(j['employmentTypes']),
      workplaceTypes: readList(j['workplaceTypes']),
      experienceLevels: readList(j['experienceLevels']),
      salaryPeriods: readList(j['salaryPeriods']),
      sortOptions: readList(j['sortOptions']),
    );
  }
}

class JobApplicationModel {
  final int id;
  final int jobId;
  final int applicantUserId;
  final String? fullName;
  final String? profileFullName;
  final String? phone;
  final String? submittedPhone;
  final String? profilePhone;
  final String? applicantEmail;
  final String? message;
  final String? resumeUrl;
  final String? attachmentUrl;
  final String? attachmentMime;
  final String? attachmentName;
  final double? expectedSalary;
  final double? offerSalary;
  final String? offerWorkHours;
  final String? offerWorkDays;
  final String? offerMessage;
  final String? offerAttachmentUrl;
  final String? offerAttachmentMime;
  final String? offerAttachmentName;
  final int? offerSentByUserId;
  final DateTime? offerSentAt;
  final DateTime? offerAcceptedAt;
  final String? offerAcceptanceAttachmentUrl;
  final String? offerAcceptanceAttachmentMime;
  final String? offerAcceptanceAttachmentName;
  final String status;
  final String? statusReason;
  final int? statusChangedByUserId;
  final DateTime? statusChangedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? applicantBlock;
  final String? applicantBuildingNumber;
  final String? applicantApartment;
  final String? applicantImageUrl;
  final String? jobTitle;
  final String? jobCompanyName;
  final String? jobActivityType;
  final String? jobDepartment;
  final String? jobCategory;
  final int? jobCreatedByUserId;
  final int? jobMerchantId;
  final String? jobMerchantName;
  final String? jobMerchantType;
  final bool canChangeStatus;
  final bool canAcceptOffer;
  final List<JobApplicationStatusHistoryModel> statusHistory;

  const JobApplicationModel({
    required this.id,
    required this.jobId,
    required this.applicantUserId,
    required this.fullName,
    required this.profileFullName,
    required this.phone,
    required this.submittedPhone,
    required this.profilePhone,
    required this.applicantEmail,
    required this.message,
    required this.resumeUrl,
    required this.attachmentUrl,
    required this.attachmentMime,
    required this.attachmentName,
    required this.expectedSalary,
    required this.offerSalary,
    required this.offerWorkHours,
    required this.offerWorkDays,
    required this.offerMessage,
    required this.offerAttachmentUrl,
    required this.offerAttachmentMime,
    required this.offerAttachmentName,
    required this.offerSentByUserId,
    required this.offerSentAt,
    required this.offerAcceptedAt,
    required this.offerAcceptanceAttachmentUrl,
    required this.offerAcceptanceAttachmentMime,
    required this.offerAcceptanceAttachmentName,
    required this.status,
    required this.statusReason,
    required this.statusChangedByUserId,
    required this.statusChangedAt,
    required this.createdAt,
    required this.updatedAt,
    required this.applicantBlock,
    required this.applicantBuildingNumber,
    required this.applicantApartment,
    required this.applicantImageUrl,
    required this.jobTitle,
    required this.jobCompanyName,
    required this.jobActivityType,
    required this.jobDepartment,
    required this.jobCategory,
    required this.jobCreatedByUserId,
    required this.jobMerchantId,
    required this.jobMerchantName,
    required this.jobMerchantType,
    required this.canChangeStatus,
    required this.canAcceptOffer,
    required this.statusHistory,
  });

  factory JobApplicationModel.fromJson(Map<String, dynamic> j) {
    final rawStatusHistory = List<dynamic>.from(
      j['statusHistory'] ?? j['status_history'] ?? const [],
    );
    return JobApplicationModel(
      id: parseInt(j['id']),
      jobId: parseInt(j['jobId'] ?? j['job_id']),
      applicantUserId: parseInt(j['applicantUserId'] ?? j['applicant_user_id']),
      fullName: parseNullableString(j['fullName'] ?? j['full_name']),
      profileFullName: parseNullableString(
        j['profileFullName'] ?? j['applicant_profile_full_name'],
      ),
      phone: parseNullableString(j['phone']),
      submittedPhone: parseNullableString(j['submittedPhone'] ?? j['phone']),
      profilePhone: parseNullableString(
        j['profilePhone'] ?? j['applicant_profile_phone'],
      ),
      applicantEmail: parseNullableString(
        j['applicantEmail'] ?? j['applicant_email'],
      ),
      message: parseNullableString(j['message']),
      resumeUrl: parseNullableString(j['resumeUrl'] ?? j['resume_url']),
      attachmentUrl: parseNullableString(
        j['attachmentUrl'] ?? j['attachment_url'],
      ),
      attachmentMime: parseNullableString(
        j['attachmentMime'] ?? j['attachment_mime'],
      ),
      attachmentName: parseNullableString(
        j['attachmentName'] ?? j['attachment_name'],
      ),
      expectedSalary:
          j['expectedSalary'] == null && j['expected_salary'] == null
          ? null
          : parseDouble(j['expectedSalary'] ?? j['expected_salary']),
      offerSalary: j['offerSalary'] == null && j['offer_salary'] == null
          ? null
          : parseDouble(j['offerSalary'] ?? j['offer_salary']),
      offerWorkHours: parseNullableString(
        j['offerWorkHours'] ?? j['offer_work_hours'],
      ),
      offerWorkDays: parseNullableString(
        j['offerWorkDays'] ?? j['offer_work_days'],
      ),
      offerMessage: parseNullableString(
        j['offerMessage'] ?? j['offer_message'],
      ),
      offerAttachmentUrl: parseNullableString(
        j['offerAttachmentUrl'] ?? j['offer_attachment_url'],
      ),
      offerAttachmentMime: parseNullableString(
        j['offerAttachmentMime'] ?? j['offer_attachment_mime'],
      ),
      offerAttachmentName: parseNullableString(
        j['offerAttachmentName'] ?? j['offer_attachment_name'],
      ),
      offerSentByUserId:
          (j['offerSentByUserId'] ?? j['offer_sent_by_user_id']) == null
          ? null
          : parseInt(j['offerSentByUserId'] ?? j['offer_sent_by_user_id']),
      offerSentAt: parseNullableDateTime(
        j['offerSentAt'] ?? j['offer_sent_at'],
      ),
      offerAcceptedAt: parseNullableDateTime(
        j['offerAcceptedAt'] ?? j['offer_accepted_at'],
      ),
      offerAcceptanceAttachmentUrl: parseNullableString(
        j['offerAcceptanceAttachmentUrl'] ??
            j['offer_acceptance_attachment_url'],
      ),
      offerAcceptanceAttachmentMime: parseNullableString(
        j['offerAcceptanceAttachmentMime'] ??
            j['offer_acceptance_attachment_mime'],
      ),
      offerAcceptanceAttachmentName: parseNullableString(
        j['offerAcceptanceAttachmentName'] ??
            j['offer_acceptance_attachment_name'],
      ),
      status: parseString(j['status'], fallback: 'submitted'),
      statusReason: parseNullableString(
        j['statusReason'] ?? j['status_reason'],
      ),
      statusChangedByUserId:
          j['statusChangedByUserId'] == null &&
              j['status_changed_by_user_id'] == null
          ? null
          : parseInt(
              j['statusChangedByUserId'] ?? j['status_changed_by_user_id'],
            ),
      statusChangedAt: parseNullableDateTime(
        j['statusChangedAt'] ?? j['status_changed_at'],
      ),
      createdAt: parseNullableDateTime(j['createdAt'] ?? j['created_at']),
      updatedAt: parseNullableDateTime(j['updatedAt'] ?? j['updated_at']),
      applicantBlock: parseNullableString(
        j['applicantBlock'] ?? j['applicant_block'],
      ),
      applicantBuildingNumber: parseNullableString(
        j['applicantBuildingNumber'] ?? j['applicant_building_number'],
      ),
      applicantApartment: parseNullableString(
        j['applicantApartment'] ?? j['applicant_apartment'],
      ),
      applicantImageUrl: parseNullableString(
        j['applicantImageUrl'] ?? j['applicant_image_url'],
      ),
      jobTitle: parseNullableString(j['jobTitle'] ?? j['job_title']),
      jobCompanyName: parseNullableString(
        j['jobCompanyName'] ?? j['job_company_name'],
      ),
      jobActivityType: parseNullableString(
        j['jobActivityType'] ?? j['job_activity_type'],
      ),
      jobDepartment: parseNullableString(
        j['jobDepartment'] ?? j['job_department'],
      ),
      jobCategory: parseNullableString(j['jobCategory'] ?? j['job_category']),
      jobCreatedByUserId:
          (j['jobCreatedByUserId'] ?? j['job_created_by_user_id']) == null
          ? null
          : parseInt(j['jobCreatedByUserId'] ?? j['job_created_by_user_id']),
      jobMerchantId: (j['jobMerchantId'] ?? j['job_merchant_id']) == null
          ? null
          : parseInt(j['jobMerchantId'] ?? j['job_merchant_id']),
      jobMerchantName: parseNullableString(
        j['jobMerchantName'] ?? j['job_merchant_name'],
      ),
      jobMerchantType: parseNullableString(
        j['jobMerchantType'] ?? j['job_merchant_type'],
      ),
      canChangeStatus: parseBool(
        j['canChangeStatus'] ?? j['can_change_status'],
        fallback: false,
      ),
      canAcceptOffer: parseBool(
        j['canAcceptOffer'] ?? j['can_accept_offer'],
        fallback: false,
      ),
      statusHistory: rawStatusHistory
          .whereType<Map>()
          .map(
            (entry) => JobApplicationStatusHistoryModel.fromJson(
              Map<String, dynamic>.from(entry),
            ),
          )
          .toList(growable: false),
    );
  }

  JobApplicationModel copyWith({
    String? status,
    String? statusReason,
    int? statusChangedByUserId,
    DateTime? statusChangedAt,
    bool clearStatusReason = false,
    bool clearStatusChangedByUserId = false,
    bool clearStatusChangedAt = false,
  }) {
    return JobApplicationModel(
      id: id,
      jobId: jobId,
      applicantUserId: applicantUserId,
      fullName: fullName,
      profileFullName: profileFullName,
      phone: phone,
      submittedPhone: submittedPhone,
      profilePhone: profilePhone,
      applicantEmail: applicantEmail,
      message: message,
      resumeUrl: resumeUrl,
      attachmentUrl: attachmentUrl,
      attachmentMime: attachmentMime,
      attachmentName: attachmentName,
      expectedSalary: expectedSalary,
      offerSalary: offerSalary,
      offerWorkHours: offerWorkHours,
      offerWorkDays: offerWorkDays,
      offerMessage: offerMessage,
      offerAttachmentUrl: offerAttachmentUrl,
      offerAttachmentMime: offerAttachmentMime,
      offerAttachmentName: offerAttachmentName,
      offerSentByUserId: offerSentByUserId,
      offerSentAt: offerSentAt,
      offerAcceptedAt: offerAcceptedAt,
      offerAcceptanceAttachmentUrl: offerAcceptanceAttachmentUrl,
      offerAcceptanceAttachmentMime: offerAcceptanceAttachmentMime,
      offerAcceptanceAttachmentName: offerAcceptanceAttachmentName,
      status: status ?? this.status,
      statusReason: clearStatusReason
          ? null
          : (statusReason ?? this.statusReason),
      statusChangedByUserId: clearStatusChangedByUserId
          ? null
          : (statusChangedByUserId ?? this.statusChangedByUserId),
      statusChangedAt: clearStatusChangedAt
          ? null
          : (statusChangedAt ?? this.statusChangedAt),
      createdAt: createdAt,
      updatedAt: updatedAt,
      applicantBlock: applicantBlock,
      applicantBuildingNumber: applicantBuildingNumber,
      applicantApartment: applicantApartment,
      applicantImageUrl: applicantImageUrl,
      jobTitle: jobTitle,
      jobCompanyName: jobCompanyName,
      jobActivityType: jobActivityType,
      jobDepartment: jobDepartment,
      jobCategory: jobCategory,
      jobCreatedByUserId: jobCreatedByUserId,
      jobMerchantId: jobMerchantId,
      jobMerchantName: jobMerchantName,
      jobMerchantType: jobMerchantType,
      canChangeStatus: canChangeStatus,
      canAcceptOffer: canAcceptOffer,
      statusHistory: statusHistory,
    );
  }
}

class JobApplicationStatusHistoryModel {
  final int id;
  final int applicationId;
  final int jobId;
  final String? previousStatus;
  final String nextStatus;
  final String? reason;
  final int? changedByUserId;
  final String? changedByName;
  final String? changedByRole;
  final DateTime? changedAt;

  const JobApplicationStatusHistoryModel({
    required this.id,
    required this.applicationId,
    required this.jobId,
    required this.previousStatus,
    required this.nextStatus,
    required this.reason,
    required this.changedByUserId,
    required this.changedByName,
    required this.changedByRole,
    required this.changedAt,
  });

  factory JobApplicationStatusHistoryModel.fromJson(Map<String, dynamic> j) {
    return JobApplicationStatusHistoryModel(
      id: parseInt(j['id']),
      applicationId: parseInt(j['applicationId'] ?? j['application_id']),
      jobId: parseInt(j['jobId'] ?? j['job_id']),
      previousStatus: parseNullableString(
        j['previousStatus'] ?? j['previous_status'],
      ),
      nextStatus: parseString(j['nextStatus'] ?? j['next_status']),
      reason: parseNullableString(j['reason']),
      changedByUserId: (j['changedByUserId'] ?? j['changed_by_user_id']) == null
          ? null
          : parseInt(j['changedByUserId'] ?? j['changed_by_user_id']),
      changedByName: parseNullableString(
        j['changedByName'] ?? j['changed_by_name'],
      ),
      changedByRole: parseNullableString(
        j['changedByRole'] ?? j['changed_by_role'],
      ),
      changedAt: parseNullableDateTime(j['changedAt'] ?? j['changed_at']),
    );
  }
}

class JobTalentPoolGroupModel {
  final String activityType;
  final String department;
  final int totalApplications;
  final int uniqueApplicants;
  final int submittedCount;
  final int shortlistedCount;
  final int rejectedCount;
  final int hiredCount;
  final int withdrawnCount;
  final int dismissedAfterHireCount;
  final int archivedCount;
  final DateTime? lastApplicationAt;

  const JobTalentPoolGroupModel({
    required this.activityType,
    required this.department,
    required this.totalApplications,
    required this.uniqueApplicants,
    required this.submittedCount,
    required this.shortlistedCount,
    required this.rejectedCount,
    required this.hiredCount,
    required this.withdrawnCount,
    required this.dismissedAfterHireCount,
    required this.archivedCount,
    required this.lastApplicationAt,
  });

  factory JobTalentPoolGroupModel.fromJson(Map<String, dynamic> j) {
    return JobTalentPoolGroupModel(
      activityType: parseString(
        j['activityType'] ?? j['activity_type'],
        fallback: 'general_business',
      ),
      department: parseString(j['department'], fallback: 'operations'),
      totalApplications: parseInt(
        j['totalApplications'] ?? j['total_applications'],
      ),
      uniqueApplicants: parseInt(
        j['uniqueApplicants'] ?? j['unique_applicants'],
      ),
      submittedCount: parseInt(j['submittedCount'] ?? j['submitted_count']),
      shortlistedCount: parseInt(
        j['shortlistedCount'] ?? j['shortlisted_count'],
      ),
      rejectedCount: parseInt(j['rejectedCount'] ?? j['rejected_count']),
      hiredCount: parseInt(j['hiredCount'] ?? j['hired_count']),
      withdrawnCount: parseInt(j['withdrawnCount'] ?? j['withdrawn_count']),
      dismissedAfterHireCount: parseInt(
        j['dismissedAfterHireCount'] ?? j['dismissed_after_hire_count'],
      ),
      archivedCount: parseInt(j['archivedCount'] ?? j['archived_count']),
      lastApplicationAt: parseNullableDateTime(
        j['lastApplicationAt'] ?? j['last_application_at'],
      ),
    );
  }
}

class JobRecommendationModel {
  final int id;
  final int jobId;
  final int? sourceApplicationId;
  final int? candidateUserId;
  final String candidateFullName;
  final String? candidatePhone;
  final String? candidateEmail;
  final String? candidateImageUrl;
  final String? candidateWorkTitle;
  final String? candidateWorkCompany;
  final String? note;
  final String? attachmentUrl;
  final String? attachmentMime;
  final String? attachmentName;
  final JobRecommendationLinkedApplication? linkedApplication;
  final bool canAcceptToShortlist;
  final JobRecommendationSourceApplication? sourceApplication;
  final DateTime? createdAt;
  final int recommendedByUserId;
  final String recommendedByRole;
  final String? recommendedByName;
  final String? sourceJobTitle;
  final String? sourceCompanyName;

  const JobRecommendationModel({
    required this.id,
    required this.jobId,
    required this.sourceApplicationId,
    required this.candidateUserId,
    required this.candidateFullName,
    required this.candidatePhone,
    required this.candidateEmail,
    required this.candidateImageUrl,
    required this.candidateWorkTitle,
    required this.candidateWorkCompany,
    required this.note,
    required this.attachmentUrl,
    required this.attachmentMime,
    required this.attachmentName,
    required this.linkedApplication,
    required this.canAcceptToShortlist,
    required this.sourceApplication,
    required this.createdAt,
    required this.recommendedByUserId,
    required this.recommendedByRole,
    required this.recommendedByName,
    required this.sourceJobTitle,
    required this.sourceCompanyName,
  });

  factory JobRecommendationModel.fromJson(Map<String, dynamic> j) {
    final recommender = Map<String, dynamic>.from(
      j['recommender'] as Map? ?? const <String, dynamic>{},
    );
    final sourceJob = Map<String, dynamic>.from(
      j['sourceJob'] as Map? ?? const <String, dynamic>{},
    );
    return JobRecommendationModel(
      id: parseInt(j['id']),
      jobId: parseInt(j['jobId'] ?? j['job_id']),
      sourceApplicationId:
          (j['sourceApplicationId'] ?? j['source_application_id']) == null
          ? null
          : parseInt(j['sourceApplicationId'] ?? j['source_application_id']),
      candidateUserId: (j['candidateUserId'] ?? j['candidate_user_id']) == null
          ? null
          : parseInt(j['candidateUserId'] ?? j['candidate_user_id']),
      candidateFullName: parseString(
        j['candidateFullName'] ?? j['candidate_full_name'],
      ),
      candidatePhone: parseNullableString(
        j['candidatePhone'] ?? j['candidate_phone'],
      ),
      candidateEmail: parseNullableString(
        j['candidateEmail'] ?? j['candidate_email'],
      ),
      candidateImageUrl: parseNullableString(
        j['candidateImageUrl'] ?? j['candidate_image_url'],
      ),
      candidateWorkTitle: parseNullableString(
        j['candidateWorkTitle'] ?? j['candidate_work_title'],
      ),
      candidateWorkCompany: parseNullableString(
        j['candidateWorkCompany'] ?? j['candidate_work_company'],
      ),
      note: parseNullableString(j['note'] ?? j['recommendation_note']),
      attachmentUrl: parseNullableString(
        j['attachmentUrl'] ?? j['attachment_url'],
      ),
      attachmentMime: parseNullableString(
        j['attachmentMime'] ?? j['attachment_mime'],
      ),
      attachmentName: parseNullableString(
        j['attachmentName'] ?? j['attachment_name'],
      ),
      linkedApplication:
          j['linkedApplication'] is Map ||
              j['linked_application'] is Map ||
              j['linkedApplicationId'] != null ||
              j['linked_application_id'] != null
          ? JobRecommendationLinkedApplication.fromJson(
              Map<String, dynamic>.from(
                j['linkedApplication'] ??
                    j['linked_application'] ??
                    <String, dynamic>{
                      'id':
                          j['linkedApplicationId'] ??
                          j['linked_application_id'],
                      'status':
                          j['linkedApplicationStatus'] ??
                          j['linked_application_status'],
                      'createdAt':
                          j['linkedApplicationCreatedAt'] ??
                          j['linked_application_created_at'],
                      'statusChangedAt':
                          j['linkedApplicationStatusChangedAt'] ??
                          j['linked_application_status_changed_at'],
                    },
              ),
            )
          : null,
      canAcceptToShortlist: parseBool(
        j['canAcceptToShortlist'] ?? j['can_accept_to_shortlist'],
        fallback: false,
      ),
      sourceApplication:
          j['sourceApplication'] is Map ||
              j['source_application'] is Map ||
              j['sourceApplicationId'] != null ||
              j['source_application_id'] != null
          ? JobRecommendationSourceApplication.fromJson(
              Map<String, dynamic>.from(
                j['sourceApplication'] ??
                    j['source_application'] ??
                    <String, dynamic>{
                      'id':
                          j['sourceApplicationId'] ??
                          j['source_application_id'],
                      'status':
                          j['sourceApplicationStatus'] ??
                          j['source_application_status'],
                      'createdAt':
                          j['sourceApplicationCreatedAt'] ??
                          j['source_application_created_at'],
                      'message':
                          j['sourceApplicationMessage'] ??
                          j['source_application_message'],
                      'resumeUrl':
                          j['sourceResumeUrl'] ?? j['source_resume_url'],
                      'attachmentUrl':
                          j['sourceAttachmentUrl'] ??
                          j['source_attachment_url'],
                      'attachmentMime':
                          j['sourceAttachmentMime'] ??
                          j['source_attachment_mime'],
                      'attachmentName':
                          j['sourceAttachmentName'] ??
                          j['source_attachment_name'],
                      'expectedSalary':
                          j['sourceExpectedSalary'] ??
                          j['source_expected_salary'],
                      'candidateFullName':
                          j['sourceCandidateFullName'] ??
                          j['source_candidate_full_name'],
                      'candidatePhone':
                          j['sourceCandidatePhone'] ??
                          j['source_candidate_phone'],
                      'candidateEmail':
                          j['sourceCandidateEmail'] ??
                          j['source_candidate_email'],
                      'candidateImageUrl':
                          j['sourceCandidateImageUrl'] ??
                          j['source_candidate_image_url'],
                    },
              ),
            )
          : null,
      createdAt: parseNullableDateTime(j['createdAt'] ?? j['created_at']),
      recommendedByUserId: parseInt(
        recommender['userId'] ??
            recommender['recommendedByUserId'] ??
            j['recommendedByUserId'] ??
            j['recommended_by_user_id'],
      ),
      recommendedByRole: parseString(
        recommender['role'] ??
            j['recommendedByRole'] ??
            j['recommended_by_role'],
        fallback: 'admin',
      ),
      recommendedByName: parseNullableString(
        recommender['fullName'] ??
            j['recommendedByName'] ??
            j['recommender_full_name'],
      ),
      sourceJobTitle: parseNullableString(
        sourceJob['title'] ?? j['sourceJobTitle'] ?? j['source_job_title'],
      ),
      sourceCompanyName: parseNullableString(
        sourceJob['companyName'] ??
            j['sourceCompanyName'] ??
            j['source_job_company_name'],
      ),
    );
  }
}

class JobRecommendationLinkedApplication {
  final int id;
  final String? status;
  final DateTime? createdAt;
  final DateTime? statusChangedAt;

  const JobRecommendationLinkedApplication({
    required this.id,
    required this.status,
    required this.createdAt,
    required this.statusChangedAt,
  });

  factory JobRecommendationLinkedApplication.fromJson(Map<String, dynamic> j) {
    return JobRecommendationLinkedApplication(
      id: parseInt(j['id']),
      status: parseNullableString(j['status']),
      createdAt: parseNullableDateTime(j['createdAt'] ?? j['created_at']),
      statusChangedAt: parseNullableDateTime(
        j['statusChangedAt'] ?? j['status_changed_at'],
      ),
    );
  }
}

class JobRecommendationSourceApplication {
  final int id;
  final String? status;
  final DateTime? createdAt;
  final String? message;
  final String? resumeUrl;
  final String? attachmentUrl;
  final String? attachmentMime;
  final String? attachmentName;
  final double? expectedSalary;
  final String? candidateFullName;
  final String? candidatePhone;
  final String? candidateEmail;
  final String? candidateImageUrl;

  const JobRecommendationSourceApplication({
    required this.id,
    required this.status,
    required this.createdAt,
    required this.message,
    required this.resumeUrl,
    required this.attachmentUrl,
    required this.attachmentMime,
    required this.attachmentName,
    required this.expectedSalary,
    required this.candidateFullName,
    required this.candidatePhone,
    required this.candidateEmail,
    required this.candidateImageUrl,
  });

  factory JobRecommendationSourceApplication.fromJson(Map<String, dynamic> j) {
    return JobRecommendationSourceApplication(
      id: parseInt(j['id']),
      status: parseNullableString(j['status']),
      createdAt: parseNullableDateTime(j['createdAt'] ?? j['created_at']),
      message: parseNullableString(j['message']),
      resumeUrl: parseNullableString(j['resumeUrl'] ?? j['resume_url']),
      attachmentUrl: parseNullableString(
        j['attachmentUrl'] ?? j['attachment_url'],
      ),
      attachmentMime: parseNullableString(
        j['attachmentMime'] ?? j['attachment_mime'],
      ),
      attachmentName: parseNullableString(
        j['attachmentName'] ?? j['attachment_name'],
      ),
      expectedSalary:
          j['expectedSalary'] == null && j['expected_salary'] == null
          ? null
          : parseDouble(j['expectedSalary'] ?? j['expected_salary']),
      candidateFullName: parseNullableString(
        j['candidateFullName'] ?? j['candidate_full_name'],
      ),
      candidatePhone: parseNullableString(
        j['candidatePhone'] ?? j['candidate_phone'],
      ),
      candidateEmail: parseNullableString(
        j['candidateEmail'] ?? j['candidate_email'],
      ),
      candidateImageUrl: parseNullableString(
        j['candidateImageUrl'] ?? j['candidate_image_url'],
      ),
    );
  }
}

class JobRecommendationCandidateModel {
  final int sourceApplicationId;
  final int sourceJobId;
  final String? sourceJobTitle;
  final String? sourceCompanyName;
  final String sourceStatus;
  final DateTime? sourceCreatedAt;
  final int candidateUserId;
  final String candidateFullName;
  final String? candidatePhone;
  final String? candidateEmail;
  final String? candidateImageUrl;
  final String? candidateWorkTitle;
  final String? candidateWorkCompany;
  final int applicationsCount;

  const JobRecommendationCandidateModel({
    required this.sourceApplicationId,
    required this.sourceJobId,
    required this.sourceJobTitle,
    required this.sourceCompanyName,
    required this.sourceStatus,
    required this.sourceCreatedAt,
    required this.candidateUserId,
    required this.candidateFullName,
    required this.candidatePhone,
    required this.candidateEmail,
    required this.candidateImageUrl,
    required this.candidateWorkTitle,
    required this.candidateWorkCompany,
    required this.applicationsCount,
  });

  factory JobRecommendationCandidateModel.fromJson(Map<String, dynamic> j) {
    return JobRecommendationCandidateModel(
      sourceApplicationId: parseInt(
        j['sourceApplicationId'] ?? j['source_application_id'],
      ),
      sourceJobId: parseInt(j['sourceJobId'] ?? j['source_job_id']),
      sourceJobTitle: parseNullableString(
        j['sourceJobTitle'] ?? j['source_job_title'],
      ),
      sourceCompanyName: parseNullableString(
        j['sourceCompanyName'] ?? j['source_company_name'],
      ),
      sourceStatus: parseString(j['sourceStatus'] ?? j['source_status']),
      sourceCreatedAt: parseNullableDateTime(
        j['sourceCreatedAt'] ?? j['source_created_at'],
      ),
      candidateUserId: parseInt(j['candidateUserId'] ?? j['candidate_user_id']),
      candidateFullName: parseString(
        j['candidateFullName'] ?? j['candidate_full_name'],
      ),
      candidatePhone: parseNullableString(
        j['candidatePhone'] ?? j['candidate_phone'],
      ),
      candidateEmail: parseNullableString(
        j['candidateEmail'] ?? j['candidate_email'],
      ),
      candidateImageUrl: parseNullableString(
        j['candidateImageUrl'] ?? j['candidate_image_url'],
      ),
      candidateWorkTitle: parseNullableString(
        j['candidateWorkTitle'] ?? j['candidate_work_title'],
      ),
      candidateWorkCompany: parseNullableString(
        j['candidateWorkCompany'] ?? j['candidate_work_company'],
      ),
      applicationsCount: parseInt(
        j['applicationsCount'] ?? j['applications_count'],
      ),
    );
  }
}
