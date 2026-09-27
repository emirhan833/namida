// Compatibility layer used by the macOS music-only port.
//
// Namida shares a few model/controller types between local playback and its
// YouTube feature. The real YouTube implementation is deliberately excluded
// from this build; these types keep the shared UI/indexer code source-compatible
// while every network/account operation remains disabled.

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:nampack/reactive/reactive.dart';

import 'package:namida/class/track.dart';

class _Noop {
  const _Noop();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

enum MembershipType { none, unknown, cutie, pookie, patootie, owner }

class ExecuteDetails {
  const ExecuteDetails();
}

class _StubAudioTrack {
  final String? langCode;
  final String? displayName;
  const _StubAudioTrack({this.langCode, this.displayName});
}

class AudioStream {
  final Duration? duration;
  final String? url;
  final int bitrate;
  final int itag;
  final int sizeInBytes;
  final _StubAudioTrack? audioTrack;
  final dynamic codecInfo;

  const AudioStream({
    this.duration,
    this.url,
    this.bitrate = 0,
    this.itag = 0,
    this.sizeInBytes = 0,
    this.audioTrack,
    this.codecInfo,
  });

  String? buildUrl() => url;
}

class VideoStream {
  final Duration? duration;
  final String? url;
  final int bitrate;
  final int itag;
  final int sizeInBytes;
  final int height;
  final int width;
  final num fps;
  final dynamic codecInfo;

  const VideoStream({
    this.duration,
    this.url,
    this.bitrate = 0,
    this.itag = 0,
    this.sizeInBytes = 0,
    this.height = 0,
    this.width = 0,
    this.fps = 0,
    this.codecInfo,
  });

  String? buildUrl() => url;
}

class VideoStreamInfo {
  final int? width;
  final int? height;
  final dynamic publishedAt;
  final dynamic publishDate;
  final int? durSeconds;
  const VideoStreamInfo({this.width, this.height, this.publishedAt, this.publishDate, this.durSeconds});
}

class VideoStreamsResult {
  final List<VideoStream> videoStreams;
  final List<AudioStream> audioStreams;
  final dynamic loudnessDBData;
  const VideoStreamsResult({this.videoStreams = const [], this.audioStreams = const [], this.loudnessDBData});
  bool hasExpired() => true;
}

class YTWatch {
  final int? dateMSNull;
  final bool isYTMusic;
  const YTWatch({required this.dateMSNull, required this.isYTMusic});

  factory YTWatch.fromJson(dynamic json) => json is Map
      ? YTWatch(dateMSNull: json['dateMS'], isYTMusic: json['isYTMusic'] == true)
      : const YTWatch(dateMSNull: null, isYTMusic: false);

  Map<String, dynamic> toJson() => {'dateMS': dateMSNull, 'isYTMusic': isYTMusic};
}

class YoutubeID implements Playable<Map<String, dynamic>> {
  final String id;
  final YTWatch? watchNull;
  final dynamic playlistID;
  final dynamic queueSource;
  final dynamic sourceNull;

  const YoutubeID({
    required this.id,
    dynamic source,
    this.watchNull,
    this.queueSource,
    required this.playlistID,
  }) : sourceNull = source;

  factory YoutubeID.fromJson(Map<String, dynamic> json) => YoutubeID(
        id: json['id']?.toString() ?? '',
        watchNull: YTWatch.fromJson(json['watch']),
        queueSource: null,
        source: null,
        playlistID: json['playlistID'],
      );

  YTWatch get watch => watchNull ?? const YTWatch(dateMSNull: null, isYTMusic: false);
  int get dateAddedMS => watchNull?.dateMSNull ?? 0;
  dynamic get source => sourceNull;
  bool get isFavourite => false;

  @override
  String get key => id;

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'watch': watch.toJson(),
        if (queueSource != null) 'qs': queueSource,
        if (sourceNull != null) 'source': sourceNull.toString(),
        if (playlistID != null) 'playlistID': playlistID,
      };

  MediaItem toMediaItem([
    String? videoId,
    dynamic info,
    dynamic thumbnail,
    int? index,
    int? queueLength,
    Duration? duration,
  ]) =>
      MediaItem(id: id, title: id, duration: duration);

  @override
  bool operator ==(Object other) => other is YoutubeID && other.id == id && other.dateAddedMS == dateAddedMS;
  @override
  int get hashCode => Object.hash(id, dateAddedMS);
}

typedef YoutubeIDToMediaItemCallback = FutureOr<MediaItem?> Function(YoutubeID item);
typedef YoutubeIDToMediaItem = MediaItem?;

class DownloadTaskFilename {
  final String filename;
  const DownloadTaskFilename(this.filename);

  static String cleanupFilename(String value, {String? parentDirPath}) {
    var result = value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    while (result.contains('  ')) result = result.replaceAll('  ', ' ');
    return result;
  }

  @override
  String toString() => filename;
}

class YoutubeInfoController {
  static dynamic current = _YoutubeInfoCurrent();
  static dynamic utils = _YoutubeInfoUtils();
  static dynamic video = const _Noop();
  static dynamic history = const _Noop();
  static dynamic related = const _Noop();
  static dynamic comments = const _Noop();

  static Future<void> initialize([Completer<void>? completer]) async {
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  static void dispose() {}
}

class _YoutubeInfoCurrent extends _Noop {
  _YoutubeInfoCurrent();
  final currentYTStreams = Rxn<VideoStreamsResult>();
  void resetAll() => currentYTStreams.value = null;
}

class _YoutubeInfoUtils extends _Noop {
  _YoutubeInfoUtils();
  Future<Duration?> getVideoDuration(String id) async => null;
  Future<int?> getVideoDurationSeconds(String id) async => null;
  Future<void> fillBackupInfoMap() async {}
}

class YoutubeController {
  static dynamic inst = const _Noop();
  static dynamic getPreferredAudioStream(dynamic streams) => null;
  static dynamic getPreferredStreamQuality(dynamic streams, {bool preferIncludeWebm = false}) => null;
}

class YoutubeHistoryController { static dynamic inst = const _Noop(); }
class YoutubePlaylistController { static dynamic inst = const _Noop(); }
class YoutubeSubscriptionsController { static dynamic inst = const _Noop(); }
class YoutubeImportController { static dynamic inst = const _Noop(); }
class YTLocalSearchController { static dynamic inst = const _Noop(); }

class YoutubeAccountController {
  static dynamic membership = _YoutubeMembership();
  static dynamic current = const _Noop();
  static dynamic signInProgress;
  static Future<void> initialize() async {}
  static Future<void> fetchAccSupportDetails() async {}
}

class _YoutubeMembership extends _Noop {
  _YoutubeMembership();
  dynamic redirectUrlCompleter;
}

class YoutubeMiniplayerUiController { static dynamic inst = _YoutubeMiniplayerUiControllerInstance(); }
class _YoutubeMiniplayerUiControllerInstance extends _Noop {
  _YoutubeMiniplayerUiControllerInstance();
  void startDimTimer({Brightness? brightness}) {}
}

class YTUtils {
  const YTUtils();
  void showVideoClearDialog(String id) {}
}

class YoutubeThumbnail extends StatelessWidget {
  const YoutubeThumbnail({super.key, this.width, this.customUrl, this.isImportantInCache, this.type, this.forceSquared, this.isCircle});
  final double? width;
  final String? customUrl;
  final bool? isImportantInCache;
  final dynamic type;
  final bool? forceSquared;
  final bool? isCircle;
  @override
  Widget build(BuildContext context) => SizedBox.square(dimension: width ?? 0);
}

class YTHostedPlaylistSubpage extends StatelessWidget {
  const YTHostedPlaylistSubpage({super.key});
  factory YTHostedPlaylistSubpage.fromId({required String playlistId, dynamic userPlaylist}) => const YTHostedPlaylistSubpage();
  void navigate() {}
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class YTChannelSubpage extends StatelessWidget {
  const YTChannelSubpage({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class YouTubeHomeView extends StatelessWidget {
  const YouTubeHomeView({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class YoutubeAccountManagePage extends StatelessWidget {
  const YoutubeAccountManagePage({super.key});
  void navigate() {}
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class YoutubeSearchResultsPage extends StatelessWidget {
  const YoutubeSearchResultsPage({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class YoutubeSearchResultsPageState {}
class YoutubeChannel {}
class YoutubeFeed {}
class YoutubeStreamsManager extends _Noop { const YoutubeStreamsManager(); }
class YoutubeSubscription {}
class YoutubeVideoHistory {}
class YTLinkToID {}
class YTMarkVideoWatchedResult {}
class YTMiniplayerQueueChipState {}
class YTVideoLikeParamters {}
class YoutiPie {}
class YoutiPieChannelPageResult {}
class YoutiPieChannelTabResult {}
class YoutiPieFetchAllRes {}
class YoutiPieListWrapper<T> extends ListBaseCompat<T> {}
class YoutiPiePlaylistResultBase {}
class YoutiPieVideoPageResult {}
class YoutiPieVideoThumbnail {}
class YTPlaylistDownloadPage extends StatelessWidget { const YTPlaylistDownloadPage({super.key}); @override Widget build(BuildContext context) => const SizedBox.shrink(); }
class YTQueueChipHeaderRow extends StatelessWidget { const YTQueueChipHeaderRow({super.key}); @override Widget build(BuildContext context) => const SizedBox.shrink(); }
class YTHistoryVideoCard extends StatelessWidget { const YTHistoryVideoCard({super.key}); @override Widget build(BuildContext context) => const SizedBox.shrink(); }
class YoutubeMiniPlayer extends StatelessWidget { const YoutubeMiniPlayer({super.key}); @override Widget build(BuildContext context) => const SizedBox.shrink(); }

class ListBaseCompat<T> {
  final List<T> _items = <T>[];
  int get length => _items.length;
  T operator [](int index) => _items[index];
}

enum YoutiPieFetchAllResType { none }
enum YTHomePages { home }
enum YTSeekActionMode { none, expandedMiniplayer, all }
enum YTSortType { relevance }
enum YTVideoQuality { auto }
enum YTVideosSorting { relevance }
enum YTVisibleMixesPlaces { history, homeFeed, relatedVideos, search }
enum YTVisibleShortPlaces { history, homeFeed, relatedVideos, search }

extension YTHomePagesL10n on YTHomePages { String get toText => name; }
extension YTSeekActionModeL10n on YTSeekActionMode { String get toText => name; }
extension YTSortTypeL10n on YTSortType { String get toText => name; }
extension YTVisibleMixesPlacesL10n on YTVisibleMixesPlaces { String get toText => name; }
extension YTVisibleShortPlacesL10n on YTVisibleShortPlaces { String get toText => name; }

class YTThumbnails { const YTThumbnails(); }
class YTUrlUtils {
  static String? extractPlaylistId(String input) => null;
  static String buildVideoUrl(String id) => '';
}

extension ThumbnailPickerExt<T> on Iterable<T> { T? pick() => isEmpty ? null : first; }
extension CodecInfoUtils on Object { String get codecText => toString(); }
extension StreamFilterVideoUtils<T> on Iterable<T> { List<T> get videoStreams => toList(); }

const String YT_DOWNLOAD_TASKS = '';
const String YT_HISTORY_PLAYLIST = '';
const String YT_LIKES_PLAYLIST = '';
const String YT_PALETTES = '';
const String YT_PLAYLISTS = '';
const String YT_PLAYLISTS_ARTWORKS = '';
const String YT_PLAYLISTS_METADATA = '';
const String YT_STATS = '';
const String YT_SUBSCRIPTIONS = '';
const String YT_SUBSCRIPTIONS_GROUPS_ALL = '';
const String YT_THUMBNAILS = '';
const String YT_THUMBNAILS_CHANNELS = '';
