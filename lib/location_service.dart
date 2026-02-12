import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';

class LocationService {
  StreamSubscription? _positionSubscription;
  final _supabase = Supabase.instance.client;

  void iniciarRastreio(String motoristaUuid) {
    if (motoristaUuid == '0' || motoristaUuid.isEmpty) return;

    _positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
          ),
        ).listen((Position position) async {
          try {
            await _supabase
                .from('motoristas')
                .update({
                  'lat': position.latitude.toString(),
                  'lng': position.longitude.toString(),
                  'status': 'disponivel',
                  'esta_online': true,
                  'ultima_atualizacao': DateTime.now().toIso8601String(),
                })
                .eq('id', motoristaUuid);
            debugPrint('✅ GPS: Posição enviada para UUID: $motoristaUuid');
            debugPrint(
              '🚀 BANCO: Status atualizado para DISPONIVEL e coordenadas enviadas.',
            );
          } catch (e) {
            debugPrint('❌ GPS: Erro ao atualizar: $e');
          }
        });
  }

  void pararRastreio() {
    _positionSubscription?.cancel();
  }
}
