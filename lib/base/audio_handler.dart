import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:basic_audio_handler/basic_audio_handler.dart';
import 'package:just_audio/just_audio.dart';
import 'package:nampack/reactive/reactive.dart';

import 'package:namida/class/audio_cache_detail.dart';
import 'package:namida/class/track.dart';
import 'package:namida/class/video.dart';
import 'package:namida/controller/current_color.dart';
import 'package:namida/controller/queue_controller.dart';
import 'package:namida/controller/settings_controller.dart';
import 'package:namida/core/enums.dart';
import 'package:namida/music_only/youtube_stubs.dart';

/// Local-music implementation used by the macOS port.
///
/// Namida's upstream desktop UI, indexer, queue controller, playlist pages and
/// miniplayer all talk to this class through Player. Upstream delegates the
/// low-level queue/player implementation to a private `basic_audio_handler`
/// repository. For the macOS music-only port we keep Namida's public-facing
/// Player API and replace only that private backend with just_audio.
class NamidaAudioVideoHandler<Q extends Playable> extends BaseAudioHandler {
  NamidaAudioVideoHandler() {
    _bindPlayerStreams();
  }

  final AudioPlayer _player = AudioPlayer();
  final _MusicQueue<Q> currentQueue = _MusicQueue<Q>();

  final playWhenReady = false.obs;
  final currentItem = Rxn<Q>();
  final currentIndex = 0.obs;
  final currentPositionMS = 0.obs;
  final currentSpeed = 1.0.obs;
  final currentItemDuration = Rxn<Duration>();
  final isPlaying = false.obs;
  final currentState = ProcessingState.idle.obs;
  final buffered = Duration.zero.obs;
  final numberOfRepeats = 0.obs;
  final sleepTimerConfig = SleepTimerConfig.initial.obs;
  final playErrorRemainingSecondsToSkip = 0.obs;
  final isFetchingInfo = false.obs;
  final replayGainLinearVolumeMultiplierRx = 1.0.obs;

  final audioTracks = Rxn<List<AudioTrack>>();
  final videoPlayerInfo = Rxn<VideoInfoData>();
  final currentVideoStream = Rxn<VideoStream>();
  final currentAudioStream = Rxn<AudioStream>();
  final currentCachedVideo = Rxn<NamidaVideo>();
  final currentCachedAudio = Rxn<AudioCacheDetails>();

  AndroidEqualizerExtended? get equalizerExtended => null;
  AndroidLoudnessEnhancerExtended? get loudnessEnhancerExtended => null;
  int? get androidSessionId => null;
  bool get isCurrentAudioFromCache => false;
  bool get isLastItem => currentQueue.value.isEmpty || currentIndex.value >= currentQueue.value.length - 1;
  bool isModifyingQueue = false;
  int latestInsertedIndex = -1;
  dynamic onVideoError;

  QueueSourceBase latestQueueSource = QueueSource.others(null);
  RxMap<String, int>? totalListenedTimeInSec = <String, int>{}.obs;

  double _pitch = 1.0;
  double _lastRequestedVolume = 1.0;
  final Map<String, void Function(double)> _volumeListeners = {};
  Timer? _sleepTimer;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _bufferSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<double>? _speedSub;

  double get userPlayerVolumeForItem => _lastRequestedVolume;

  void _bindPlayerStreams() {
    _stateSub = _player.playerStateStream.listen((event) {
      isPlaying.value = event.playing;
      currentState.value = event.processingState;
      playWhenReady.value = event.playing || playWhenReady.value;
      playbackState.add(
        playbackState.value.copyWith(
          playing: event.playing,
          processingState: switch (event.processingState) {
            ProcessingState.idle => AudioProcessingState.idle,
            ProcessingState.loading => AudioProcessingState.loading,
            ProcessingState.buffering => AudioProcessingState.buffering,
            ProcessingState.ready => AudioProcessingState.ready,
            ProcessingState.completed => AudioProcessingState.completed,
          },
          updatePosition: _player.position,
          bufferedPosition: _player.bufferedPosition,
          speed: _player.speed,
          queueIndex: currentQueue.value.isEmpty ? null : currentIndex.value,
        ),
      );
      if (event.processingState == ProcessingState.completed) {
        _onCompleted();
      }
    });
    _positionSub = _player.positionStream.listen((p) => currentPositionMS.value = p.inMilliseconds);
    _bufferSub = _player.bufferedPositionStream.listen((p) => buffered.value = p);
    _durationSub = _player.durationStream.listen((d) => currentItemDuration.value = d);
    _speedSub = _player.speedStream.listen((s) => currentSpeed.value = s);
  }

  Future<void> _onCompleted() async {
    if (currentQueue.value.isEmpty) return;
    final mode = settings.player.repeatMode.value;
    if (mode == PlayerRepeatMode.one || mode == PlayerRepeatMode.forNtimes) {
      await seek(Duration.zero);
      await play();
      return;
    }
    if (isLastItem) {
      if (mode == PlayerRepeatMode.all || mode == PlayerRepeatMode.allShuffle || settings.player.jumpToFirstTrackAfterFinishingQueue.value) {
        await skipToQueueItem(0);
      } else {
        setPlayWhenReady(false);
        await pause();
      }
    } else {
      await skipToNext();
    }
  }

  String? _itemPath(Q item) => item is Selectable ? item.track.path : null;

  Future<void> _loadIndex(int index, {Duration? initialPosition, bool? forcePlay}) async {
    if (currentQueue.value.isEmpty) return;
    index = index.clamp(0, currentQueue.value.length - 1);
    final item = currentQueue.value[index];
    final path = _itemPath(item);
    if (path == null || path.isEmpty) return;

    currentIndex.value = index;
    currentItem.value = item;
    currentPositionMS.value = initialPosition?.inMilliseconds ?? 0;
    settings.extra.save(lastPlayedIndex: index);

    if (item is Selectable) {
      CurrentColor.inst.updatePlayerColorFromTrack(item, index);
    }

    Duration? duration;
    if (path.startsWith('http://') || path.startsWith('https://')) {
      duration = await _player.setUrl(path, initialPosition: initialPosition);
    } else {
      duration = await _player.setFilePath(path, initialPosition: initialPosition);
    }
    currentItemDuration.value = duration;
    refreshNotification(item);

    if (forcePlay ?? playWhenReady.value) {
      setPlayWhenReady(true);
      await _player.play();
    }
  }

  PlayerConfig getDefaultPlayerConfig(Q? item) => PlayerConfig(
        skipSilence: settings.player.skipSilenceEnabled.value,
        loudnessEnhancerEnabled: settings.equalizer.loudnessEnhancerEnabled.value,
        loudnessEnhancer: settings.equalizer.loudnessEnhancer.value,
        equalizerEnabled: settings.equalizer.equalizerEnabled.value,
        equalizer: Map<double, double>.from(settings.equalizer.equalizer.value),
        preset: settings.equalizer.preset.value,
        volume: settings.player.volume.value,
        speed: settings.player.speed.value,
        pitch: settings.player.pitch.value,
      );

  PlayerConfig getDefaultPlayerConfigR(Q? item) => PlayerConfig(
        skipSilence: settings.player.skipSilenceEnabled.valueR,
        loudnessEnhancerEnabled: settings.equalizer.loudnessEnhancerEnabled.valueR,
        loudnessEnhancer: settings.equalizer.loudnessEnhancer.valueR,
        equalizerEnabled: settings.equalizer.equalizerEnabled.valueR,
        equalizer: Map<double, double>.from(settings.equalizer.equalizer.valueR),
        preset: settings.equalizer.preset.valueR,
        volume: settings.player.volume.valueR,
        speed: settings.player.speed.valueR,
        pitch: settings.player.pitch.valueR,
      );

  static AVPlayer createPlayer({
    bool disableVideo = true,
    AudioPlayer Function()? exoplayerCreator,
    AudioPlayer Function()? exoplayerSWCreator,
  }) {
    return AVPlayer(exoplayerCreator?.call() ?? AudioPlayer());
  }

  Future<Map<String, int>> prepareTotalListenTime() async {
    totalListenedTimeInSec ??= <String, int>{}.obs;
    return Map<String, int>.from(totalListenedTimeInSec!.value);
  }

  void refreshNotification([Q? item, dynamic youtubeIdMediaItem]) {
    final active = item ?? currentItem.value;
    if (active is! Selectable) return;
    final path = active.track.path;
    final title = path.replaceAll('\\', '/').split('/').last;
    final media = MediaItem(
      id: path,
      title: title,
      duration: currentItemDuration.value,
    );
    mediaItem.add(media);
    playbackState.add(
      playbackState.value.copyWith(
        playing: isPlaying.value,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: currentIndex.value,
      ),
    );
  }

  void setPlayWhenReady(bool value) {
    playWhenReady.value = value;
  }

  @override
  Future<void> play() async {
    setPlayWhenReady(true);
    if (_player.processingState == ProcessingState.completed) await _player.seek(Duration.zero);
    await _player.play();
  }

  Future<void> onPlayRaw({bool attemptFixVolume = true}) => play();

  @override
  Future<void> pause() async {
    setPlayWhenReady(false);
    await _player.pause();
  }

  Future<void> onPauseRaw() => pause();

  Future<void> togglePlayPause() => isPlaying.value ? pause() : play();

  @override
  Future<void> stop() async {
    setPlayWhenReady(false);
    await _player.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    if (position < Duration.zero) position = Duration.zero;
    final duration = currentItemDuration.value;
    if (duration != null && position > duration) position = duration;
    await _player.seek(position);
  }

  @override
  Future<void> skipToNext() async {
    if (currentQueue.value.isEmpty) return;
    final next = isLastItem ? 0 : currentIndex.value + 1;
    await skipToQueueItem(next);
  }

  @override
  Future<void> skipToPrevious() async {
    if (currentQueue.value.isEmpty) return;
    final prev = currentIndex.value <= 0 ? currentQueue.value.length - 1 : currentIndex.value - 1;
    await skipToQueueItem(prev);
  }

  @override
  Future<void> skipToQueueItem(int index) => _loadIndex(index, forcePlay: playWhenReady.value);

  Future<void> assignNewQueue<Id>({
    required int playAtIndex,
    required Iterable<Q> queue,
    bool shuffle = false,
    bool startPlaying = true,
    int? maximumItems,
    void Function()? onQueueEmpty,
    void Function()? onIndexAndQueueSame,
    void Function(List<Q> finalizedQueue)? onQueueDifferent,
    void Function(Q currentItem)? onAssigningCurrentItem,
    bool Function(Q? currentItem, Q itemToPlay)? canRestructureQueueOnly,
    void Function()? onRestructuringQueue,
    Id Function(Q currentItem)? duplicateRemover,
  }) async {
    var list = queue.where((e) => e is Selectable).toList();
    if (duplicateRemover != null) {
      final seen = <Object?>{};
      list = list.where((e) => seen.add(duplicateRemover(e))).toList();
    }
    if (maximumItems != null && maximumItems >= 0 && list.length > maximumItems) {
      list = list.take(maximumItems).toList();
    }
    if (list.isEmpty) {
      onQueueEmpty?.call();
      return;
    }
    playAtIndex = playAtIndex.clamp(0, list.length - 1);
    final selected = list[playAtIndex];
    if (shuffle) {
      final rest = [...list]..removeAt(playAtIndex);
      rest.shuffle();
      list = [selected, ...rest];
      playAtIndex = 0;
    }

    final same = _sameQueue(currentQueue.value, list) && currentIndex.value == playAtIndex;
    if (same) {
      onIndexAndQueueSame?.call();
      return;
    }

    currentQueue.value = list;
    onQueueDifferent?.call(List<Q>.from(list));
    onAssigningCurrentItem?.call(list[playAtIndex]);
    setPlayWhenReady(startPlaying);
    await _loadIndex(playAtIndex, forcePlay: startPlaying);
    await _persistQueue();
  }

  bool _sameQueue(List<Q> a, List<Q> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].key != b[i].key) return false;
    }
    return true;
  }

  Future<void> _persistQueue() async {
    try {
      await QueueController.inst.updateLatestQueue(currentQueue.value, source: latestQueueSource);
    } catch (_) {}
  }

  Future<void> addToQueue(Iterable<Q> items, {bool insertNext = false, bool insertAfterLatest = false}) async {
    final add = items.where((e) => e is Selectable).toList();
    if (add.isEmpty) return;
    var index = currentQueue.value.length;
    if (insertNext) index = math.min(currentIndex.value + 1, currentQueue.value.length);
    if (insertAfterLatest && latestInsertedIndex >= 0) index = math.min(latestInsertedIndex + 1, currentQueue.value.length);
    final list = List<Q>.from(currentQueue.value)..insertAll(index, add);
    currentQueue.value = list;
    latestInsertedIndex = index + add.length - 1;
    await _persistQueue();
  }

  Future<void> insertInQueue(Iterable<Q> items, int index) async {
    final add = items.where((e) => e is Selectable).toList();
    index = index.clamp(0, currentQueue.value.length);
    final current = currentItem.value;
    final list = List<Q>.from(currentQueue.value)..insertAll(index, add);
    currentQueue.value = list;
    if (current != null) currentIndex.value = list.indexOf(current).clamp(0, list.length - 1);
    latestInsertedIndex = index + add.length - 1;
    await _persistQueue();
  }

  Future<void> removeFromQueue(int index) async {
    if (index < 0 || index >= currentQueue.value.length) return;
    final active = currentItem.value;
    final wasCurrent = index == currentIndex.value;
    final list = List<Q>.from(currentQueue.value)..removeAt(index);
    currentQueue.value = list;
    if (list.isEmpty) {
      currentItem.value = null;
      currentIndex.value = 0;
      await stop();
    } else if (wasCurrent) {
      final next = index.clamp(0, list.length - 1);
      await _loadIndex(next, forcePlay: playWhenReady.value);
    } else if (active != null) {
      currentIndex.value = list.indexOf(active).clamp(0, list.length - 1);
    }
    await _persistQueue();
  }

  int removeRangeFromQueue(int start, int end) {
    if (currentQueue.value.isEmpty) return 0;
    start = start.clamp(0, currentQueue.value.length);
    end = end.clamp(start, currentQueue.value.length);
    final count = end - start;
    if (count <= 0) return 0;
    final active = currentItem.value;
    final list = List<Q>.from(currentQueue.value)..removeRange(start, end);
    currentQueue.value = list;
    if (active != null && list.contains(active)) currentIndex.value = list.indexOf(active);
    _persistQueue();
    return count;
  }

  int removeAllPrevious() => removeRangeFromQueue(0, currentIndex.value);
  int removeAllNext() => removeRangeFromQueue(currentIndex.value + 1, currentQueue.value.length);

  int removeAllExceptCurrent() {
    final active = currentItem.value;
    if (active == null) return 0;
    final removed = currentQueue.value.length - 1;
    currentQueue.value = <Q>[active];
    currentIndex.value = 0;
    _persistQueue();
    return removed;
  }

  int removeDuplicatesFromQueue() {
    final before = currentQueue.value.length;
    final seen = <String>{};
    final active = currentItem.value;
    currentQueue.value = currentQueue.value.where((e) => seen.add(e.key)).toList();
    if (active != null) currentIndex.value = currentQueue.value.indexOf(active).clamp(0, currentQueue.value.length - 1);
    _persistQueue();
    return before - currentQueue.value.length;
  }

  void reorderItems(int oldIndex, int newIndex) {
    final list = List<Q>.from(currentQueue.value);
    if (oldIndex < 0 || oldIndex >= list.length) return;
    newIndex = newIndex.clamp(0, list.length);
    final active = currentItem.value;
    final item = list.removeAt(oldIndex);
    if (newIndex > oldIndex) newIndex--;
    list.insert(newIndex, item);
    currentQueue.value = list;
    if (active != null) currentIndex.value = list.indexOf(active);
    _persistQueue();
  }

  void shuffleAllItems() {
    if (currentQueue.value.length < 2) return;
    final active = currentItem.value;
    final list = List<Q>.from(currentQueue.value)..shuffle();
    currentQueue.value = list;
    if (active != null) currentIndex.value = list.indexOf(active);
    _persistQueue();
  }

  Future<void> shuffleNextItems() async {
    final list = List<Q>.from(currentQueue.value);
    if (currentIndex.value + 1 < list.length) {
      final tail = list.sublist(currentIndex.value + 1)..shuffle();
      list.replaceRange(currentIndex.value + 1, list.length, tail);
      currentQueue.value = list;
      await _persistQueue();
    }
  }

  Future<bool> moveToNext(int index) => _moveItem(index, currentIndex.value + 1);
  Future<bool> moveToAfterLatestInserted(int index) => _moveItem(index, latestInsertedIndex >= 0 ? latestInsertedIndex + 1 : currentIndex.value + 1);
  Future<bool> moveToLast(int index) => _moveItem(index, currentQueue.value.length);

  Future<bool> _moveItem(int from, int to) async {
    if (from < 0 || from >= currentQueue.value.length) return false;
    reorderItems(from, to);
    return true;
  }

  Future<void> replaceAllItemsInQueue(Q oldItem, Q newItem) async {
    currentQueue.value = currentQueue.value.map((e) => e == oldItem ? newItem : e).toList();
    if (currentItem.value == oldItem) currentItem.value = newItem;
    await _persistQueue();
  }

  Future<void> replaceAllItemsInQueueBulk(Map<Q, Q> replacements) async {
    currentQueue.value = currentQueue.value.map((e) => replacements[e] ?? e).toList();
    final active = currentItem.value;
    if (active != null && replacements[active] != null) currentItem.value = replacements[active];
    await _persistQueue();
  }

  Future<void> replaceWhereInQueue(bool Function(Q) test, Q Function(Q) replace) async {
    currentQueue.value = currentQueue.value.map((e) => test(e) ? replace(e) : e).toList();
    final active = currentItem.value;
    if (active != null) currentIndex.value = currentQueue.value.indexWhere((e) => e.key == active.key).clamp(0, currentQueue.value.length - 1);
    await _persistQueue();
  }

  Future<void> clearQueue() async {
    await stop();
    currentQueue.value = <Q>[];
    currentItem.value = null;
    currentIndex.value = 0;
    currentPositionMS.value = 0;
    currentItemDuration.value = null;
    buffered.value = Duration.zero;
    currentVideoStream.value = null;
    currentAudioStream.value = null;
    currentCachedVideo.value = null;
    currentCachedAudio.value = null;
    await _persistQueue();
  }

  Future<void> setVolumeWithMultiplier(double volume) async {
    _lastRequestedVolume = volume.clamp(0.0, 1.0);
    final effective = (_lastRequestedVolume * replayGainLinearVolumeMultiplierRx.value).clamp(0.0, 1.0);
    await _player.setVolume(effective);
    for (final callback in _volumeListeners.values) callback(_lastRequestedVolume);
  }

  Future<void> setPlayerSpeed(double value) async {
    value = value.clamp(0.25, 4.0);
    await _player.setSpeed(value);
    currentSpeed.value = value;
  }

  Future<void> setPlayerPitch(double value) async {
    _pitch = value;
    // just_audio on macOS does not expose an independent pitch setter. Namida
    // keeps the value in its settings/UI; speed and playback remain functional.
  }

  Future<void> setSkipSilenceEnabled(bool enabled) async {}
  Future<void> setAudioTrack(String? trackId) async {}
  Future<void> refreshCurrentItemPlayerConfig() async {}
  Future<void> setAudioOnlyPlayback(bool audioOnly) async {}
  Future<void> setVideo(dynamic options) async {}
  Future<void> setVideoSource({required AudioVideoSource source, bool loopingAnimation = false, bool isFile = false, bool videoOnly = false}) async {}
  Future<void> resetGaplessPlaybackData() async {}
  Future<void> recheckCachedVideos(String videoId) async {}
  Future<void> tryAddingMixPlaylist(String videoId) async {}
  Future<void> tryGenerateWaveform(YoutubeID? video) async {}

  Future<void> onItemPlayYoutubeIDSetQuality({
    required VideoStreamsResult? mainStreams,
    required VideoStream? stream,
    required File? cachedFile,
    required bool useCache,
    required String videoId,
    NamidaVideo? videoItem,
  }) async {}

  Future<void> onItemPlayYoutubeIDSetAudio({
    required VideoStreamsResult? mainStreams,
    required AudioStream? stream,
    required File? cachedFile,
    bool useCache = true,
    required String videoId,
  }) async {}

  void onVolumeChangeAddListener(String key, void Function(double musicVolume) fn) => _volumeListeners[key] = fn;
  void onVolumeChangeRemoveListener(String key) => _volumeListeners.remove(key);

  void invokeQueueModifyLock() => isModifyingQueue = true;
  void invokeQueueModifyLockRelease({bool isCanceled = false}) => isModifyingQueue = false;

  void updateNumberOfRepeats(int newNumber) => numberOfRepeats.value = newNumber;

  void updateSleepTimerValues({
    bool? enableSleepAfterItems,
    bool? enableSleepAfterMins,
    int? sleepAfterMin,
    int? sleepAfterItems,
  }) {
    final next = sleepTimerConfig.value.copyWith(
      enableSleepAfterItems: enableSleepAfterItems,
      enableSleepAfterMins: enableSleepAfterMins,
      sleepAfterMin: sleepAfterMin,
      sleepAfterItems: sleepAfterItems,
    );
    sleepTimerConfig.value = next;
    _sleepTimer?.cancel();
    if (next.enableSleepAfterMins && next.sleepAfterMin > 0) {
      _sleepTimer = Timer(Duration(minutes: next.sleepAfterMin), pause);
    }
  }

  void resetSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    sleepTimerConfig.value = SleepTimerConfig.initial;
  }

  void cancelPlayErrorSkipTimer() => playErrorRemainingSecondsToSkip.value = 0;

  void refreshRxVariables() {
    isPlaying.value = _player.playing;
    currentPositionMS.value = _player.position.inMilliseconds;
    buffered.value = _player.bufferedPosition;
    currentItemDuration.value = _player.duration;
    currentSpeed.value = _player.speed;
  }

  Future<void> onDispose() async {
    setPlayWhenReady(false);
    await _player.stop();
  }

  Future<void> disposeCompletely() async {
    _sleepTimer?.cancel();
    await _stateSub?.cancel();
    await _positionSub?.cancel();
    await _bufferSub?.cancel();
    await _durationSub?.cancel();
    await _speedSub?.cancel();
    await _player.dispose();
  }
}

class _MusicQueue<Q extends Playable> {
  final RxBaseCore<List<Q>> queueRx = <Q>[].obs;

  List<Q> get value => queueRx.value;
  set value(List<Q> value) => queueRx.value = value;
}
