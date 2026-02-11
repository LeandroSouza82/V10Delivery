import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sembast/sembast_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class CacheService {
  static final CacheService _instance = CacheService._internal();
  factory CacheService() => _instance;
  CacheService._internal();

  Database? _db;
  final StoreRef<String, dynamic> _store = StoreRef<String, dynamic>.main();
  final Map<String, dynamic> _memoryStore = <String, dynamic>{};

  Future<void> init() async {
    if (_db != null) return;
    // Em Web não tentamos acessar path_provider/sembast; usaremos SharedPreferences
    if (kIsWeb) {
      return;
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      final dbPath = p.join(dir.path, 'v10_delivery_cache.db');
      _db = await databaseFactoryIo.openDatabase(dbPath);
    } catch (e) {
      debugPrint('CacheService: não foi possível abrir DB em disco: $e');
      _db = null;
    }
  }

  Future<void> saveEntregas(List<Map<String, dynamic>> lista) async {
    await init();
    if (kIsWeb || _db == null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('v10_entregas_cache', jsonEncode(lista));
        return;
      } catch (e) {
        _memoryStore['entregas'] = lista;
        return;
      }
    }
    await _store.record('entregas').put(_db!, lista);
  }

  Future<List<Map<String, dynamic>>> loadEntregas() async {
    await init();
    if (kIsWeb || _db == null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final s = prefs.getString('v10_entregas_cache');
        if (s == null || s.isEmpty) return [];
        final data = jsonDecode(s) as List<dynamic>;
        return data
            .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } catch (e) {
        final data = _memoryStore['entregas'];
        if (data == null) return [];
        if (data is List) {
          return data
              .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
        return [];
      }
    }
    final data = await _store.record('entregas').get(_db!);
    if (data == null) return [];
    if (data is List) {
      return data
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    return [];
  }
}
