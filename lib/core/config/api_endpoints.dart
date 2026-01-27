import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiEndpoints {
  ApiEndpoints._();

  static String get baseUrl => (dotenv.env['BASE_URL'] ?? '').trim();
  static String get apiPrefix => (dotenv.env['API_PREFIX'] ?? '/api').trim();

  static String _join(String a, String b) {
    final aa = a.endsWith('/') ? a.substring(0, a.length - 1) : a;
    final bb = b.startsWith('/') ? b : '/$b';
    return '$aa$bb';
  }

  // Public / Health
  static String get root => baseUrl;
  static String get health => _join(baseUrl, '/health');
  static String get swagger => _join(baseUrl, '/api-docs');

  // Auth / Users
  static String get login => _join(baseUrl, '/login');
  static String get apiRoot => _join(baseUrl, apiPrefix);
  static String get userRole => _join(baseUrl, '$apiPrefix/user-role');
  static String get masterRole => _join(baseUrl, '$apiPrefix/master-role');
  static String get userDetails => _join(baseUrl, '$apiPrefix/user-dtls');

  // Master Data
  static String get masterCollege => _join(baseUrl, '/master-college');
  static String get masterDepts => _join(baseUrl, '$apiPrefix/master-depts');
  static String get masterAcadYear => _join(baseUrl, '$apiPrefix/master-acadyear');
  static String get collegeGroup => _join(baseUrl, '$apiPrefix/college-group');
  static String get course => _join(baseUrl, '$apiPrefix/course');
  static String get subject => _join(baseUrl, '$apiPrefix/subject');
  static String get subjectList => _join(baseUrl, '$apiPrefix/subject/list');
  static String get subjectCourse => _join(baseUrl, '$apiPrefix/subject-course');
  static String get subjectElective => _join(baseUrl, '$apiPrefix/subject-elective');
  static String get classRoom => _join(baseUrl, '$apiPrefix/class-room');
  static String get teacher => _join(baseUrl, '$apiPrefix/teacher');
  static String get teacherDetails => _join(baseUrl, '$apiPrefix/teacher-dtls');
  static String get teacherAvailabilityManager => _join(baseUrl, '$apiPrefix/teacher-availability-manager');

  // Students / Bulk
  static String get students => _join(baseUrl, '$apiPrefix/students');
  static String get studentsUp => _join(baseUrl, '$apiPrefix/students-up');
  static String get bulkStudents => _join(baseUrl, '$apiPrefix/bulk-students');
  static String get student => _join(baseUrl, '$apiPrefix/student');

  // Teacher Bulk
  static String get teacherMasterBulkUp => _join(baseUrl, '$apiPrefix/teacher-master-bulk-up');

  // Routine / Exam / Attendance
  static String get dailyRoutine => _join(baseUrl, '$apiPrefix/daily-routine');
  static String get collegeDailyRoutine => _join(baseUrl, '$apiPrefix/college-daily-routine');
  static String get examRoutineManager => _join(baseUrl, '$apiPrefix/exam-routine-manager');
  static String get collegeAttendanceManager => _join(baseUrl, '$apiPrefix/CollegeAttendenceManager');
  static String get employeeAttendance => _join(baseUrl, '$apiPrefix/employee-attendance');

  // Course Offering / Registration / Results
  static String get courseOffering => _join(baseUrl, '$apiPrefix/course-offering');
  static String get courseRegistration => _join(baseUrl, '$apiPrefix/course-registration');
  static String get examResult => _join(baseUrl, '$apiPrefix/exam-result');
  static String get examResultRaw => _join(baseUrl, '$apiPrefix/exam-result-raw');

  // CMS / Finance
  static String get cmsFeeStructure => _join(baseUrl, '$apiPrefix/cms-fee-structure');
  static String get cmsPayments => _join(baseUrl, '$apiPrefix/cms-payments');
  static String get cmsStudentFeeInvoice => _join(baseUrl, '$apiPrefix/cms-student-fee-invoice');
  static String get cmsStuScholarship => _join(baseUrl, '$apiPrefix/cms-stu-scholarship');
  static String get finMasterStudent => _join(baseUrl, '$apiPrefix/fin-master-student');

  // Misc / Utilities
  static String get chartData => _join(baseUrl, '$apiPrefix/chart-data');
  static String get calendarAttendance => _join(baseUrl, '$apiPrefix/calendar-attendance');
  static String get smsDevice => _join(baseUrl, '$apiPrefix/sms-device');
  static String get whiteboardCms => _join(baseUrl, '$apiPrefix/whiteboard-cms');
  static String get demandLetters => _join(baseUrl, '$apiPrefix/demand-letters');
  static String get teacherInfo => _join(baseUrl, '$apiPrefix/teacher-info');
  static String get studentInformation => _join(baseUrl, '$apiPrefix/student-information');
  static String get leaveApplication => _join(baseUrl, '$apiPrefix/leave-application');
  static String get studentAy => _join(baseUrl, '$apiPrefix/student-ay');

  // Events / Announcements / Notices
  static String get events => _join(baseUrl, '$apiPrefix/events');
  static String get announcements => _join(baseUrl, '$apiPrefix/announcements');
  static String get notices => _join(baseUrl, '$apiPrefix/notices');

  // Campus Activity
  static String get campusActivity => _join(baseUrl, '$apiPrefix/campus-activity');

  // Master Fetcher
  static String get master => _join(baseUrl, '$apiPrefix/master');
  static String get masterFetchAll => _join(baseUrl, '$apiPrefix/master/fetch-all');

  static get masterEvents => null;
}
