import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';

class LocationService {
  StreamSubscription? _positionSubscription;
  final _supabase = Supabase.instance.client;

  /// Valida se as coordenadas estão dentro dos limites do estado de SC.
  /// Latitude: entre -30.0 e -26.0 | Longitude: entre -54.0 e -48.0
  /// Correção crítica: o operador da longitude era invertido (lng < -54.0 && lng > -48.0)
  /// tornando a condição impossível. O correto é lng > -54.0 && lng < -48.0.
  bool _isValidSC(double lat, double lng) {
    return lat > -30.0 && lat < -26.0 && lng > -54.0 && lng < -48.0;
  }

  void iniciarRastreio(String motoristaUuid) {
    if (motoristaUuid == '0' || motoristaUuid.isEmpty) {
      return;
    }

    _positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
          ),
        ).listen((Position position) async {
          try {
            if (!_isValidSC(position.latitude, position.longitude)) {
              debugPrint(
                '⚠️ GPS: coordenadas fora de SC (${position.latitude}, ${position.longitude}) — sinal ignorado.',
              );
              return;
            }
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
          } catch (e) {
            debugPrint('❌ GPS: Erro ao atualizar: $e');
          }
        });
  }

  void pararRastreio() {
    _positionSubscription?.cancel();
  }
}
