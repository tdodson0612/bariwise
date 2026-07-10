// lib/services/sound_service.dart
// Plays a gentle in-app notification chime for new messages.
// Debounced so rapid messages only trigger one sound.

import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:bari_wise/config/app_config.dart';

class SoundService {
  static final AudioPlayer _player = AudioPlayer();
  static DateTime? _lastPlayed;
  static const Duration _debounce = Duration(seconds: 2);

  /// Play the message chime. Silently no-ops on error — sound is non-critical.
  static Future<void> playMessageChime() async {
    try {
      final now = DateTime.now();
      if (_lastPlayed != null &&
          now.difference(_lastPlayed!) < _debounce) {
        AppConfig.debugPrint('🔕 Chime debounced');
        return;
      }
      _lastPlayed = now;
      await _player.play(AssetSource('sounds/message_chime.mp3'));
      AppConfig.debugPrint('🔔 Message chime played');
    } catch (e) {
      AppConfig.debugPrint('⚠️ Sound playback failed (non-critical): $e');
    }
  }

  static Future<void> dispose() async {
    await _player.dispose();
  }
}