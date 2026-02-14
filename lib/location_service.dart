import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:v10_delivery/utils/logging.dart';

class LocationService {
  StreamSubscription<Position>? _positionSubscription;
  Timer? _timer;
  final _supabase = Supabase.instance.client;

  Future<void> iniciarRastreio(String motoristaUuid) async {
    if (motoristaUuid == '0' || motoristaUuid.isEmpty) {
      dlog('LocationService: motoristaUuid inválido - abortando.');
      return;
    }

    // Checar permissões aqui por redundância (pode ter sido feita na UI)
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        perm = await Geolocator.requestPermission();
      }
      if (perm != LocationPermission.always &&
          perm != LocationPermission.whileInUse) {
        dlog('LocationService: permissão não concedida: $perm');
        return;
      }
    } catch (e) {
      dlog('LocationService: falha na checagem de permissão: $e');
      return;
    }

    // Enviar posição imediata
    try {
      final Position pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
        ),
      );
      await _updatePositionWithFallback(
        motoristaUuid,
        pos.latitude,
        pos.longitude,
      );
    } catch (e) {
      dlog('LocationService: erro obtendo posição imediata: $e');
    }

    // Timer periódico (30s)
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (t) async {
      try {
        final Position pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 0,
          ),
        );
        await _updatePositionWithFallback(
          motoristaUuid,
          pos.latitude,
          pos.longitude,
        );
      } catch (e) {
        dlog('LocationService: erro no Timer.periodic ao obter posição: $e');
      }
    });

    // Stream baseado em distância (com proteção)
    try {
      await _positionSubscription?.cancel();
    } catch (_) {}

    _positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
          ),
        ).listen((Position position) async {
          try {
            await _updatePositionWithFallback(
              motoristaUuid,
              position.latitude,
              position.longitude,
            );
          } catch (e) {
            dlog('LocationService: erro no stream ao atualizar posição: $e');
          }
        });
  }

  Future<void> _updatePositionWithFallback(
    String motoristaUuid,
    double lat,
    double lng,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final int? codigoV10 = prefs.getInt('codigo_v10');

      final String ts = DateTime.now().toUtc().toIso8601String();
      final Map<String, dynamic> payload = {
        'lat': lat.toString(),
        'lng': lng.toString(),
        'ultima_atualizacao': ts,
      };

      // 1) Tentar por user_id (UUID do Auth)
      try {
        await _supabase
            .from('motoristas')
            .update(payload)
            .eq('user_id', motoristaUuid);
        final check = await _supabase
            .from('motoristas')
            .select('id')
            .eq('user_id', motoristaUuid)
            .limit(1);
        try {
          final List<dynamic> checkList = List<dynamic>.from(
            check as List<dynamic>,
          );
          if (checkList.isNotEmpty) {
            dlog('Identificando motorista via: UUID');
            return;
          }
        } catch (_) {}
      } catch (_) {}

      // 2) Tentar por id numérico (se motoristaUuid parseável)
      final int? parsed = int.tryParse(motoristaUuid);
      if (parsed != null) {
        try {
          await _supabase.from('motoristas').update(payload).eq('id', parsed);
          final check2 = await _supabase
              .from('motoristas')
              .select('id')
              .eq('id', parsed)
              .limit(1);
          try {
            final List<dynamic> checkList2 = List<dynamic>.from(
              check2 as List<dynamic>,
            );
            if (checkList2.isNotEmpty) {
              dlog('Identificando motorista via: ID Sequencial');
              return;
            }
          } catch (_) {}
        } catch (_) {}
      }

      // 3) Tentar por codigo_v10 (campo curto)
      if (codigoV10 != null) {
        try {
          await _supabase
              .from('motoristas')
              .update(payload)
              .eq('codigo_v10', codigoV10);
          final check3 = await _supabase
              .from('motoristas')
              .select('id')
              .eq('codigo_v10', codigoV10)
              .limit(1);
          try {
            final List<dynamic> checkList3 = List<dynamic>.from(
              check3 as List<dynamic>,
            );
            if (checkList3.isNotEmpty) {
              dlog('Identificando motorista via: ID Sequencial (codigo_v10)');
              return;
            }
          } catch (_) {}
        } catch (_) {}
      }

      // 4) Fallback final: tentar id como string
      try {
        await _supabase
            .from('motoristas')
            .update(payload)
            .eq('id', motoristaUuid);
        final check4 = await _supabase
            .from('motoristas')
            .select('id')
            .eq('id', motoristaUuid)
            .limit(1);
        try {
          final List<dynamic> checkList4 = List<dynamic>.from(
            check4 as List<dynamic>,
          );
          if (checkList4.isNotEmpty) {
            dlog(
              'Identificando motorista via: ID Sequencial (string fallback)',
            );
            return;
          }
        } catch (_) {}
      } catch (e) {
        dlog('LocationService: fallback final falhou: $e');
      }

      dlog(
        'LocationService: não foi possível localizar registro correspondente para atualizar.',
      );
    } catch (e) {
      dlog('LocationService: erro em _updatePositionWithFallback: $e');
    }
  }

  void pararRastreio() {
    _positionSubscription?.cancel();
    _timer?.cancel();
  }
}
