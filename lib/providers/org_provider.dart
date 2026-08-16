import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';

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

  // Цвета берутся из палитры темы, а не дублируются здесь литералами: раньше
  // те же hex-ы жили в двух местах, и школьный акцент на экранах входа мог
  // разъехаться с акцентом остального приложения.
  Color get primaryColor => isSchool ? C.orange : C.teal;

  Color get primaryDark => isSchool ? C.orangeDk : C.tealDk;

  Color get primaryLight => isSchool ? C.orangeLt : C.tealLt;

  List<Color> get gradientColors =>
      isSchool ? C.amberGradient : C.tealGradient;

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
