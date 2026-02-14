import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'supabase_service.dart';

class LocationService {
  StreamSubscription<Position>? _positionSubscription;

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
            await SupabaseService.updateMotoristaLocation(
              motoristaUuid,
              position.latitude,
              position.longitude,
            );
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
    _positionSubscription = null;
  }
}
