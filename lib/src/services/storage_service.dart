import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  // Singleton instance
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  late final FlutterSecureStorage _secureStorage;
  late final SharedPreferences _sharedPrefs;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    
    _secureStorage = const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
      // Linux uses libsecret by default, which is what we want.
    );
    
    _sharedPrefs = await SharedPreferences.getInstance();
    _initialized = true;
  }

  // --- General Preferences (SharedPreferences) ---

  Future<void> saveLastProject(String projectId) async {
    await _sharedPrefs.setString('last_project_id', projectId);
  }

  String? getLastProject() {
    return _sharedPrefs.getString('last_project_id');
  }

  // --- Secure Credentials (FlutterSecureStorage) ---

  // Key format: "rdp_creds_<instance_name>" -> JSON or separate keys?
  // Let's use separate keys for simplicity: "rdp_user_<instance>" and "rdp_pass_<instance>"
  // We can also store "rdp_domain_<instance>"

  Future<void> saveRdpCredentials({
    required String instanceName,
    required String username,
    required String password,
    String? domain,
  }) async {
    await _secureStorage.write(key: 'rdp_user_$instanceName', value: username);
    await _secureStorage.write(key: 'rdp_pass_$instanceName', value: password);
    if (domain != null && domain.isNotEmpty) {
      await _secureStorage.write(key: 'rdp_domain_$instanceName', value: domain);
    } else {
      await _secureStorage.delete(key: 'rdp_domain_$instanceName');
    }
  }

  Future<Map<String, String?>> getRdpCredentials(String instanceName) async {
    final user = await _secureStorage.read(key: 'rdp_user_$instanceName');
    final pass = await _secureStorage.read(key: 'rdp_pass_$instanceName');
    final domain = await _secureStorage.read(key: 'rdp_domain_$instanceName');
    
    return {
      'username': user,
      'password': pass,
      'domain': domain,
    };
  }

  Future<void> clearRdpCredentials(String instanceName) async {
    await _secureStorage.delete(key: 'rdp_user_$instanceName');
    await _secureStorage.delete(key: 'rdp_pass_$instanceName');
    await _secureStorage.delete(key: 'rdp_domain_$instanceName');
  }
}
