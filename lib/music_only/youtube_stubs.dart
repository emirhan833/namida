// Compatibility layer used by the macOS music-only port.
//
// The original Namida source shares a number of model/controller types between
// local playback and YouTube playback. The macOS music-only build rewrites
// those imports to this file so the real local Player/Indexer/Playlist/UI code
// can stay intact without downloading Namida's private YouTube packages.

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

enum MembershipType {
  none,
  unknown,
  cutie,
  pookie,
  patootie,
  owner,
}

/// Minimal replacement for the private youtipie request metadata object.
class ExecuteDetails {
  const ExecuteDetails();
}

class AudioStream {
  final Duration? duration;
  final String? url;
  const AudioStream({this.duration, this.url});
}

class VideoStream {
  final Duration? duration;
  final String? url;
  const VideoStream({this.duration, this.url});
}

class VideoStreamInfo {
  final int? width;
  final int? height;
  const VideoStreamInfo({this.width, this.height});
}

class VideoStreamsResult {
  final List<VideoStream> videoStreams;
  final List<AudioStream> audioStreams;
  const VideoStreamsResult({this.videoStreams = const [], this.audioStreams = const []});
}

class YoutubeID implements Playable<Map<String, dynamic>> {
  final String id;
  final int dateAdded;

  const YoutubeID(this.id, {this.dateAdded = 0});

  @override
  String get key => id;

  @override
  Map<String, dynamic> toJson() => {'id': id, if (dateAdded != 0) 'dateAdded': dateAdded};
}

typedef YoutubeIDToMediaItemCallback = FutureOr<MediaItem?> Function(YoutubeID item);
typedef YoutubeIDToMediaItem = MediaItem?;

class DownloadTaskFilename {
  final String filename;
  const DownloadTaskFilename(this.filename);

  static String cleanupFilename(String value, {String? parentDirPath}) {
    var result = value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    while (result.contains('  ')) {
      result = result.replaceAll('  ', ' ');
    }
    return result;
  }

  @override
  String toString() => filename;
}

class YoutubeInfoController {
  static final current = _YoutubeInfoCurrent();
  static final utils = _YoutubeInfoUtils();

  static Future<void> initialize([Completer<void>? completer]) async {
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  static void dispose() {}
}

class _YoutubeInfoCurrent {
  final currentYTStreams = Rxn<VideoStreamsResult>();
}

class _YoutubeInfoUtils extends _Noop {
  Future<Duration?> getVideoDuration(String id) async => null;
  Future<void> fillBackupInfoMap() async {}
}

class YoutubeController {
  static final inst = _Noop();
}

class YoutubeHistoryController {
  static final inst = _Noop();
}

class YoutubePlaylistController {
  static final inst = _Noop();
}

class YoutubeSubscriptionsController {
  static final inst = _Noop();
}

class YoutubeImportController {
  static final inst = _Noop();
}

class YTLocalSearchController {
  static final inst = _Noop();
}

class YoutubeAccountController {
  static final membership = _YoutubeMembership();

  static void initialize() {}
  static Future<void> fetchAccSupportDetails() async {}
}

class _YoutubeMembership extends _Noop {
  final redirectUrlCompleter = null;
}

class YoutubeMiniplayerUiController {
  static final inst = _YoutubeMiniplayerUiControllerInstance();
}

class _YoutubeMiniplayerUiControllerInstance extends _Noop {
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
class YTWatch {}
class YoutiPie {}
class YoutiPieChannelPageResult {}
class YoutiPieChannelTabResult {}
class YoutiPieFetchAllRes {}
class YoutiPieListWrapper<T> extends ListBaseCompat<T> {}
class YoutiPiePlaylistResultBase {}
class YoutiPieVideoPageResult {}
class YoutiPieVideoThumbnail {}

/// Tiny growable-list implementation used only to satisfy old shared type
/// signatures. It is never populated by the music-only build.
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

class YTThumbnails {
  const YTThumbnails();
}

class YTUrlUtils {
  static String? extractPlaylistId(String input) => null;
}

extension ThumbnailPickerExt<T> on Iterable<T> {
  T? pick() => isEmpty ? null : first;
}

extension CodecInfoUtils on Object {
  String get codecText => toString();
}

extension StreamFilterVideoUtils<T> on Iterable<T> {
  List<T> get videoStreams => toList();
}

// These names are intentionally retained because shared backup/settings code
// refers to their identifiers even though the music-only build never reads or
// writes YouTube state.
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
