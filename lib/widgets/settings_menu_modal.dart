import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:v10_delivery/globals.dart';
import '../core/app_colors.dart';
import '../core/app_styles.dart';
import '../core/constants.dart';

class SettingsMenuModal {
  const SettingsMenuModal._();

  static Future<void> show(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.modalTop),
      builder: (ctx) {
        return const _SettingsMenuContent();
      },
    );
  }
}

class _SettingsMenuContent extends StatefulWidget {
  const _SettingsMenuContent();

  @override
  State<_SettingsMenuContent> createState() => _SettingsMenuContentState();
}

class _SettingsMenuContentState extends State<_SettingsMenuContent> {
  String _selectedMap = 'google_maps';
  bool _googleAvailable = false;
  bool _wazeAvailable = false;

  @override
  void initState() {
    super.initState();
    _loadSelected();
    _checkAppAvailability();
    _loadDriverName();
  }

  Future<void> _loadDriverName() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      String fullName = '';
      // Tenta obter nome diretamente pelo UUID salvo (driver_uuid) ou pelo user_id
      String? lookupUuid;
      final prefs = await SharedPreferences.getInstance();
      lookupUuid = prefs.getString('driver_uuid') ?? idLogado;

      if (lookupUuid != null && lookupUuid.isNotEmpty) {
        try {
          final row = await Supabase.instance.client
              .from('motoristas')
              .select('nome')
              .eq('id', lookupUuid)
              .maybeSingle();
          if (row != null && row['nome'] != null) {
            fullName = row['nome'].toString();
          }
        } catch (e) {
          debugPrint('Erro ao buscar motoristas por id (UUID): $e');
        }
      } else if (user != null) {
        try {
          final row = await Supabase.instance.client
              .from('motoristas')
              .select('nome')
              .eq('user_id', user.id)
              .maybeSingle();
          if (row != null && row['nome'] != null) {
            fullName = row['nome'].toString();
          }
        } catch (e) {
          debugPrint('Erro ao buscar motoristas por user_id: $e');
        }
      }

      if (fullName.isEmpty) {
        // fallback to stored prefs name
        final prefs = await SharedPreferences.getInstance();
        fullName = prefs.getString('driver_name') ?? '';
      }

      if (!mounted) return;
      final first = fullName.split(' ').where((s) => s.isNotEmpty).toList();
      setState(() => _firstName = first.isNotEmpty ? first.first : '');
    } catch (e) {
      debugPrint('Erro ao carregar nome do motorista: $e');
    }
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h >= 5 && h < 12) return 'Bom dia';
    if (h >= 12 && h < 18) return 'Boa tarde';
    return 'Boa noite';
  }

  String _firstName = '';

  Future<void> _loadSelected() async {
    final prefs = await SharedPreferences.getInstance();
    final sel = prefs.getString(prefSelectedMapKey) ?? 'google_maps';
    if (!mounted) return;
    setState(() => _selectedMap = sel);
  }

  Future<void> _saveSelected(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefSelectedMapKey, key);
    if (!mounted) return;
    setState(() => _selectedMap = key);
  }

  Future<void> _checkAppAvailability() async {
    try {
      final google = await canLaunchUrl(Uri.parse('comgooglemaps://'));
      final waze = await canLaunchUrl(Uri.parse('waze://'));
      if (!mounted) return;
      setState(() {
        _googleAvailable = google;
        _wazeAvailable = waze;
      });
    } catch (_) {
      // ignore errors — availability will remain false
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.s20,
          right: AppSpacing.s20,
          top: AppSpacing.s20,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.s20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
                // Header de saudação
                Row(
                  children: [
                    const Icon(Icons.account_circle, color: Colors.white, size: 64),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_greeting()}, ${_firstName.isNotEmpty ? _firstName : 'Motorista'}!',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          if (_firstName.isNotEmpty)
                            Text(
                              'Que tenha um bom trabalho.',
                              style: TextStyle(color: Colors.white70),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s12),
                const Divider(color: Colors.white24),
                const SizedBox(height: AppSpacing.s12),

                const Text(
                  'ESCOLHER MAPA PADRÃO',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                ),
              const SizedBox(height: AppSpacing.s12),

              Card(
                color: Colors.transparent,
                elevation: 0,
                child: Column(
                  children: [
                    ListTile(
                      title: const Text('Google Maps', style: TextStyle(color: Colors.white, fontSize: 18)),
                      subtitle: Text(_googleAvailable ? 'Disponível' : 'Não instalado', style: TextStyle(color: _googleAvailable ? Colors.greenAccent : Colors.white70)),
                      trailing: _selectedMap == 'google_maps'
                          ? const Icon(Icons.check, color: Colors.green)
                          : null,
                      onTap: _googleAvailable
                          ? () => _saveSelected('google_maps')
                          : null,
                    ),
                    const Divider(color: Colors.white12),
                    ListTile(
                      title: const Text('Waze', style: TextStyle(color: Colors.white, fontSize: 18)),
                      subtitle: Text(_wazeAvailable ? 'Disponível' : 'Não instalado', style: TextStyle(color: _wazeAvailable ? Colors.greenAccent : Colors.white70)),
                      trailing: _selectedMap == 'waze' ? const Icon(Icons.check, color: Colors.green) : null,
                      onTap: _wazeAvailable ? () => _saveSelected('waze') : null,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.s20),

              Divider(color: Colors.white12),

              ListTile(
                leading: const Icon(Icons.exit_to_app, color: Colors.red),
                title: const Text('SAIR DO APLICATIVO', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                onTap: () async {
                  if (!mounted) return;
                  Navigator.of(context).pop();
                  final navigator = Navigator.of(context);
                  try {
                    await Supabase.instance.client.auth.signOut();
                  } catch (e) {
                    debugPrint('Erro ao deslogar do Supabase: $e');
                  }
                  if (!mounted) return;
                  navigator.pushNamedAndRemoveUntil('/login', (route) => false);
                },
              ),

              const SizedBox(height: AppSpacing.s30),
            ],
          ),
        ),
      ),
    );
  }
}
