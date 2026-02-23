import 'package:shared_preferences/shared_preferences.dart';

class Settings {
  Settings._();
  static final Settings _instance = Settings._();
  static SharedPreferences? _storage;
  static Future<void> ensureInitialized() async => _storage = await SharedPreferences.getInstance();
  static Settings get local {
    if (_storage != null) return _instance;
    throw Exception("Settings aren't initialized. Call Settings.ensureInitialized() first");
  }

  int get quality       => _storage!.getInt("_QUALITY") ?? 99;
  int get selectionFrom => _storage!.getInt("_SELECTION_FROM") ?? 0;

  Future<void> setQuality(int v) async {
    if (v != quality)
      await _storage!.setInt("_QUALITY", v);
  }

  Future<void> setSelectionFrom(int v) async {
    if (v != selectionFrom)
      await _storage!.setInt("_SELECTION_FROM", v);
  }
}
