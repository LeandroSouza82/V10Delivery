import 'package:sembast/sembast_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class CacheService {
  static final CacheService _instance = CacheService._internal();
  factory CacheService() => _instance;
  CacheService._internal();

  Database? _db;
  final StoreRef<String, dynamic> _store = StoreRef<String, dynamic>.main();

  Future<void> init() async {
    if (_db != null) return;
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'v10_delivery_cache.db');
    _db = await databaseFactoryIo.openDatabase(dbPath);
  }

  Future<void> saveEntregas(List<Map<String, dynamic>> lista) async {
    await init();
    await _store.record('entregas').put(_db!, lista);
  }

  Future<List<Map<String, dynamic>>> loadEntregas() async {
    await init();
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
