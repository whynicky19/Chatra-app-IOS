import 'package:chatra_app/providers/auth_provider.dart';
import 'package:chatra_app/providers/classes_provider.dart';
import 'package:chatra_app/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApi extends ApiService {
  _FakeApi() : super(baseUrl: 'http://localhost:1/api');

  int classesCalls = 0;
  int allClassesCalls = 0;

  static final List<dynamic> response = [
    {
      'id': 7,
      'name': 'Математика',
      'teacher': 'Преподаватель',
      'created_by': 42,
      'is_archived_for_user': false,
    },
  ];

  @override
  Future<List<dynamic>> getClasses() async {
    classesCalls++;
    return response;
  }

  @override
  Future<List<dynamic>> getAllClasses() async {
    allClassesCalls++;
    return response;
  }
}

class _FakeAuth extends AuthProvider {
  _FakeAuth(super.api, {required this.admin});

  final bool admin;

  @override
  bool get isAdmin => admin;

  @override
  bool get isTeacher => admin;

  @override
  int? get userId => 1;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('студент загружает доступные предметы без admin-маршрута', () async {
    final api = _FakeApi();
    final provider = ClassesProvider(api, _FakeAuth(api, admin: false));

    await provider.load();

    expect(api.classesCalls, 1);
    expect(api.allClassesCalls, 0);
    expect(provider.errorMessage, isNull);
    expect(provider.activeClasses.single['id'], 7);
  });

  test('администратор по-прежнему загружает общий каталог', () async {
    final api = _FakeApi();
    final provider = ClassesProvider(api, _FakeAuth(api, admin: true));

    await provider.load();

    expect(api.classesCalls, 0);
    expect(api.allClassesCalls, 1);
    expect(provider.errorMessage, isNull);
    expect(provider.activeClasses.single['id'], 7);
  });
}
