import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/foundation.dart';

class TtsService {
  final FlutterTts _flutterTts = FlutterTts();
  bool _isPlaying = false;

  Function(String)? onStateChanged;
  Function()? onCompletion;

  TtsService() {
    _initTts();
  }

  Future<void> _initTts() async {
    await _flutterTts.setLanguage("zh-CN");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.awaitSpeakCompletion(true);
    await _flutterTts
        .setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [
          IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
        ]);

    // 尝试寻找高质量女声（御姐音/成熟女声）
    try {
      final voices = await _flutterTts.getVoices;
      if (voices != null) {
        // 在 iOS 上，Tingting 是一个著名的优质女声。在 Android 上，可能叫 xiaoxiao
        for (var voice in voices) {
          final v = voice.toString().toLowerCase();
          if (v.contains('zh-cn') || v.contains('cmn')) {
            if (v.contains('tingting') ||
                v.contains('xiaoxiao') ||
                v.contains('female')) {
              await _flutterTts.setVoice({
                "name": voice["name"],
                "locale": voice["locale"],
              });
              break;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error setting voice: $e');
    }

    _flutterTts.setStartHandler(() {
      _isPlaying = true;
      onStateChanged?.call("playing");
    });

    _flutterTts.setCompletionHandler(() {
      onCompletion?.call();
      _isPlaying = false;
    });

    _flutterTts.setCancelHandler(() {
      _isPlaying = false;
      onStateChanged?.call("stopped");
    });

    _flutterTts.setErrorHandler((msg) {
      _isPlaying = false;
      onStateChanged?.call("error");
    });
  }

  bool get isPlaying => _isPlaying;

  Future<void> speak(String text) async {
    if (text.isEmpty) {
      onCompletion?.call();
      return;
    }
    await _flutterTts.speak(text);
  }

  Future<void> stop() async {
    await _flutterTts.stop();
  }
}
