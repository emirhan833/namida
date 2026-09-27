import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart' as ja;

export 'package:just_audio/just_audio.dart' show AndroidEqualizerBand;

enum PlayerRepeatMode { none, one, forNtimes, all, allShuffle }
enum InterruptionType { shouldPause, shouldDuck, unknown }
enum InterruptionAction { doNothing, duckAudio, pause }
enum PlayerConfigModificationScale { none, main, alt }

class EqualizerPreset {
  final String name;
  final Map<double, double> gains;

  const EqualizerPreset(this.name, [this.gains = const {}]);

  static const flat = EqualizerPreset('Flat');
  static const List<EqualizerPreset> allDefaults = [flat];

  Map<String, dynamic> toMap() => {
        'name': name,
        'gains': gains.map((k, v) => MapEntry(k.toString(), v)),
      };

  factory EqualizerPreset.fromMap(dynamic map) {
    if (map is! Map) return flat;
    final raw = map['gains'];
    final gains = <double, double>{};
    if (raw is Map) {
      for (final entry in raw.entries) {
        final k = double.tryParse(entry.key.toString());
        final v = entry.value is num ? (entry.value as num).toDouble() : null;
        if (k != null && v != null) gains[k] = v;
      }
    }
    return EqualizerPreset(map['name']?.toString() ?? 'Custom', gains);
  }

  static List<EqualizerPreset> fromListOrDefault(dynamic value) {
    if (value is! List) return [...allDefaults];
    final parsed = value.map(EqualizerPreset.fromMap).toList();
    return parsed.isEmpty ? [...allDefaults] : parsed;
  }

  @override
  bool operator ==(Object other) => other is EqualizerPreset && other.name == name;
  @override
  int get hashCode => name.hashCode;
}

class PlayerConfig {
  final bool skipSilence;
  final bool loudnessEnhancerEnabled;
  final double loudnessEnhancer;
  final bool equalizerEnabled;
  final Map<double, double> equalizer;
  final EqualizerPreset? preset;
  final double volume;
  final double speed;
  final double pitch;

  const PlayerConfig({
    this.skipSilence = false,
    this.loudnessEnhancerEnabled = false,
    this.loudnessEnhancer = 0.0,
    this.equalizerEnabled = false,
    this.equalizer = const {},
    this.preset,
    this.volume = 1.0,
    this.speed = 1.0,
    this.pitch = 1.0,
  });

  static const initial = PlayerConfig();

  factory PlayerConfig.fromMap(dynamic map) {
    if (map is! Map) return initial;
    final eq = <double, double>{};
    final rawEq = map['equalizer'];
    if (rawEq is Map) {
      for (final e in rawEq.entries) {
        final k = double.tryParse(e.key.toString());
        final v = e.value is num ? (e.value as num).toDouble() : null;
        if (k != null && v != null) eq[k] = v;
      }
    }
    return PlayerConfig(
      skipSilence: map['skipSilence'] == true,
      loudnessEnhancerEnabled: map['loudnessEnhancerEnabled'] == true,
      loudnessEnhancer: (map['loudnessEnhancer'] as num?)?.toDouble() ?? 0,
      equalizerEnabled: map['equalizerEnabled'] == true,
      equalizer: eq,
      preset: map['preset'] == null ? null : EqualizerPreset.fromMap(map['preset']),
      volume: (map['volume'] as num?)?.toDouble() ?? 1,
      speed: (map['speed'] as num?)?.toDouble() ?? 1,
      pitch: (map['pitch'] as num?)?.toDouble() ?? 1,
    );
  }

  Map<String, dynamic> toMap() => {
        'skipSilence': skipSilence,
        'loudnessEnhancerEnabled': loudnessEnhancerEnabled,
        'loudnessEnhancer': loudnessEnhancer,
        'equalizerEnabled': equalizerEnabled,
        'equalizer': equalizer.map((k, v) => MapEntry(k.toString(), v)),
        'preset': preset?.toMap(),
        'volume': volume,
        'speed': speed,
        'pitch': pitch,
      };

  PlayerConfig copyWith({
    bool? skipSilence,
    bool? loudnessEnhancerEnabled,
    double? loudnessEnhancer,
    bool? equalizerEnabled,
    Map<double, double>? equalizer,
    EqualizerPreset? preset,
    double? volume,
    double? speed,
    double? pitch,
  }) =>
      PlayerConfig(
        skipSilence: skipSilence ?? this.skipSilence,
        loudnessEnhancerEnabled: loudnessEnhancerEnabled ?? this.loudnessEnhancerEnabled,
        loudnessEnhancer: loudnessEnhancer ?? this.loudnessEnhancer,
        equalizerEnabled: equalizerEnabled ?? this.equalizerEnabled,
        equalizer: equalizer ?? Map<double, double>.from(this.equalizer),
        preset: preset ?? this.preset,
        volume: volume ?? this.volume,
        speed: speed ?? this.speed,
        pitch: pitch ?? this.pitch,
      );

  PlayerConfigModificationScale getModificationScale() => this == initial ? PlayerConfigModificationScale.none : PlayerConfigModificationScale.main;

  @override
  bool operator ==(Object other) =>
      other is PlayerConfig &&
      other.skipSilence == skipSilence &&
      other.loudnessEnhancerEnabled == loudnessEnhancerEnabled &&
      other.loudnessEnhancer == loudnessEnhancer &&
      other.equalizerEnabled == equalizerEnabled &&
      other.volume == volume &&
      other.speed == speed &&
      other.pitch == pitch &&
      other.preset == preset &&
      _mapEquals(other.equalizer, equalizer);

  static bool _mapEquals(Map<double, double> a, Map<double, double> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(skipSilence, loudnessEnhancerEnabled, loudnessEnhancer, equalizerEnabled, volume, speed, pitch, preset);
}

class SleepTimerConfig {
  final bool enableSleepAfterItems;
  final bool enableSleepAfterMins;
  final int sleepAfterMin;
  final int sleepAfterItems;

  const SleepTimerConfig({
    this.enableSleepAfterItems = false,
    this.enableSleepAfterMins = false,
    this.sleepAfterMin = 0,
    this.sleepAfterItems = 0,
  });

  static const initial = SleepTimerConfig();

  SleepTimerConfig copyWith({
    bool? enableSleepAfterItems,
    bool? enableSleepAfterMins,
    int? sleepAfterMin,
    int? sleepAfterItems,
  }) =>
      SleepTimerConfig(
        enableSleepAfterItems: enableSleepAfterItems ?? this.enableSleepAfterItems,
        enableSleepAfterMins: enableSleepAfterMins ?? this.enableSleepAfterMins,
        sleepAfterMin: sleepAfterMin ?? this.sleepAfterMin,
        sleepAfterItems: sleepAfterItems ?? this.sleepAfterItems,
      );
}

class AudioTrack {
  final String id;
  final String? name;
  final String? language;
  const AudioTrack({required this.id, this.name, this.language});
}

class VideoInfoData {
  final String id;
  final int textureId;
  final int width;
  final int height;
  final double frameRate;
  final int bitrate;
  final int sampleRate;
  final int encoderDelay;
  final int rotationDegrees;
  final String containerMimeType;
  final String label;
  final String language;

  const VideoInfoData({
    this.id = '',
    this.textureId = -1,
    this.width = -1,
    this.height = -1,
    this.frameRate = -1,
    this.bitrate = -1,
    this.sampleRate = -1,
    this.encoderDelay = -1,
    this.rotationDegrees = -1,
    this.containerMimeType = '',
    this.label = '',
    this.language = '',
  });
}

class AndroidLoudnessEnhancerExtended {
  Future<void> setEnabledUser(bool enabled) async {}
  Future<void> setTargetGainUser(double gain) async {}
  Future<void> setTargetGainTrack(double gain) async {}
}

class AndroidEqualizerExtended {
  Future<void> setEnabled(bool enabled) async {}
  Future<EqualizerPreset?> setPreset(EqualizerPreset? preset, Map<double, double> values) async => preset;
}

class AudioPipeline {
  const AudioPipeline();
}

class UriSource {
  final Uri uri;
  final dynamic tag;
  const UriSource(this.uri, {this.tag});
}

class VideoSourceOptions {
  final UriSource source;
  final bool loop;
  final bool videoOnly;
  const VideoSourceOptions({required this.source, this.loop = false, this.videoOnly = false});
}

class AudioVideoSource extends UriSource {
  AudioVideoSource(Uri uri, {super.tag}) : super(uri);
  factory AudioVideoSource.file(String path, {dynamic tag}) => AudioVideoSource(Uri.file(path), tag: tag);
  factory AudioVideoSource.uri(Uri uri, {dynamic tag}) => AudioVideoSource(uri, tag: tag);
}

class ItemPrepareConfig<T, S> {
  final S source;
  final int index;
  final T? item;
  final Duration? initialPosition;
  final String? audioTrackId;
  final VideoSourceOptions? videoOptions;
  final bool keepOldVideoSource;

  const ItemPrepareConfig(
    this.source, {
    this.index = 0,
    this.item,
    this.initialPosition,
    this.audioTrackId,
    this.videoOptions,
    this.keepOldVideoSource = false,
  });
}

class AVPlayer {
  AVPlayer([ja.AudioPlayer? player]) : _player = player ?? ja.AudioPlayer();
  final ja.AudioPlayer _player;

  Future<Duration?> setSource<T>(ItemPrepareConfig<T, UriSource> config) async {
    return _player.setAudioSource(
      ja.AudioSource.uri(config.source.uri, tag: config.source.tag),
      initialPosition: config.initialPosition ?? Duration.zero,
    );
  }

  Future<void> play() => _player.play();
  Future<void> pause() => _player.pause();
  Future<void> stop() => _player.stop();
  Future<void> seek(Duration position) => _player.seek(position);
  Future<void> setVolume(double volume) => _player.setVolume(volume);
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);
  Future<void> dispose() => _player.dispose();
  Duration? get duration => _player.duration;
  Duration get position => _player.position;
  bool get playing => _player.playing;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<ja.PlayerState> get playerStateStream => _player.playerStateStream;
}

/// Kept only so old type annotations compile. The macOS music-only build uses
/// Namida's local `NamidaAudioVideoHandler` implementation instead.
abstract class BasicAudioHandler<Q> extends BaseAudioHandler {}
