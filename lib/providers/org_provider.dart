import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum OrgType { university, school }

class OrgProvider extends ChangeNotifier {
  OrgType? _type;
  bool _initialized = false;

  OrgType? get type => _type;
  bool get isSchool => _type == OrgType.school;
  bool get isUniversity => _type == OrgType.university;
  bool get isSelected => _type != null;
  bool get isInitialized => _initialized;
  String get orgTypeString => isSchool ? 'school' : 'university';

  Color get primaryColor => isSchool
      ? const Color(0xFFF59E0B)
      : const Color(0xFF00B1C9);

  Color get primaryDark => isSchool
      ? const Color(0xFFD97706)
      : const Color(0xFF009AAF);

  Color get primaryLight => isSchool
      ? const Color(0xFFFEF3C7)
      : const Color(0xFFE6F9FB);

  List<Color> get gradientColors => isSchool
      ? [const Color(0xFFB45309), const Color(0xFFF59E0B)]
      : [const Color(0xFF006475), const Color(0xFF009AAF)];

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('org_type');
    if (saved == 'school') _type = OrgType.school;
    if (saved == 'university') _type = OrgType.university;
    _initialized = true;
    notifyListeners();
  }

  Future<void> select(OrgType type) async {
    _type = type;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('org_type', type == OrgType.school ? 'school' : 'university');
  }

  Future<void> clear() async {
    _type = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('org_type');
  }
}
