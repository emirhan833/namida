library playlist_manager;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nampack/reactive/reactive.dart';

import 'module/playlist_id.dart';

export 'module/playlist_id.dart';

abstract class PlaylistItemWithDate {
  int get dateAddedMS;
}

enum PlaylistAddDuplicateAction {
  justAddEverything,
  addOnlyMissing,
  addAllAndRemoveOldOnes,
  mergeAndSortByAddedDate,
  deleteAndCreateNewPlaylist;

  static const valuesForAdd = <PlaylistAddDuplicateAction>[
    addOnlyMissing,
    justAddEverything,
    addAllAndRemoveOldOnes,
    mergeAndSortByAddedDate,
  ];

  static const valuesForAddExcludingAddEverything = <PlaylistAddDuplicateAction>[
    addOnlyMissing,
    addAllAndRemoveOldOnes,
    mergeAndSortByAddedDate,
  ];
}

class GeneralPlaylist<T, S> {
  String name;
  List<T> tracks;
  int creationDate;
  int modifiedDate;
  String comment;
  List<String> moods;
  String? m3uPath;
  List<S>? sortsType;
  bool sortReverse;
  PlaylistID playlistID;

  GeneralPlaylist({
    required this.name,
    List<T>? tracks,
    int? creationDate,
    int? modifiedDate,
    this.comment = '',
    List<String>? moods,
    this.m3uPath,
    this.sortsType,
    this.sortReverse = false,
    PlaylistID? playlistID,
  })  : tracks = tracks ?? <T>[],
        creationDate = creationDate ?? DateTime.now().millisecondsSinceEpoch,
        modifiedDate = modifiedDate ?? DateTime.now().millisecondsSinceEpoch,
        moods = moods ?? <String>[],
        playlistID = playlistID ?? PlaylistID(id: name);

  String get id => playlistID.id;

  GeneralPlaylist<T, S> copyWith({
    String? name,
    List<T>? tracks,
    int? creationDate,
    int? modifiedDate,
    String? comment,
    List<String>? moods,
    String? m3uPath,
    bool clearM3uPath = false,
    List<S>? sortsType,
    bool? sortReverse,
    PlaylistID? playlistID,
  }) {
    return GeneralPlaylist<T, S>(
      name: name ?? this.name,
      tracks: tracks ?? List<T>.from(this.tracks),
      creationDate: creationDate ?? this.creationDate,
      modifiedDate: modifiedDate ?? this.modifiedDate,
      comment: comment ?? this.comment,
      moods: moods ?? List<String>.from(this.moods),
      m3uPath: clearM3uPath ? null : (m3uPath ?? this.m3uPath),
      sortsType: sortsType ?? this.sortsType,
      sortReverse: sortReverse ?? this.sortReverse,
      playlistID: playlistID ?? this.playlistID,
    );
  }

  Map<String, dynamic> toJson([dynamic Function(T item)? itemToJson, dynamic Function(List<S> sorts)? sortToJson]) {
    return <String, dynamic>{
      'name': name,
      'tracks': tracks.map((e) => itemToJson?.call(e) ?? _tryToJson(e)).toList(),
      'creationDate': creationDate,
      'modifiedDate': modifiedDate,
      'comment': comment,
      'moods': moods,
      if (m3uPath != null) 'm3uPath': m3uPath,
      if (sortsType != null) 'sortsType': sortToJson?.call(sortsType!) ?? sortsType!.map((e) => e.toString()).toList(),
      'sortReverse': sortReverse,
      'playlistID': playlistID.toJson(),
    };
  }

  static dynamic _tryToJson(dynamic item) {
    try {
      return item.toJson();
    } catch (_) {
      return item;
    }
  }

  factory GeneralPlaylist.fromJson(
    dynamic json,
    T Function(dynamic json) itemFromJson,
    List<S>? Function(dynamic json) sortFromJson,
  ) {
    final map = json is Map ? json : const <String, dynamic>{};
    final rawTracks = map['tracks'];
    final tracks = <T>[];
    if (rawTracks is List) {
      for (final item in rawTracks) {
        try {
          tracks.add(itemFromJson(item));
        } catch (_) {}
      }
    }
    return GeneralPlaylist<T, S>(
      name: map['name']?.toString() ?? '',
      tracks: tracks,
      creationDate: _asInt(map['creationDate']) ?? _asInt(map['dateCreated']),
      modifiedDate: _asInt(map['modifiedDate']) ?? _asInt(map['dateModified']),
      comment: map['comment']?.toString() ?? '',
      moods: (map['moods'] is List) ? (map['moods'] as List).map((e) => e.toString()).toList() : <String>[],
      m3uPath: map['m3uPath']?.toString(),
      sortsType: sortFromJson(map['sortsType'] ?? map['sortType']),
      sortReverse: map['sortReverse'] == true,
      playlistID: map['playlistID'] == null ? null : PlaylistID.fromJson(map['playlistID']),
    );
  }

  static int? _asInt(dynamic value) => value is int ? value : int.tryParse(value?.toString() ?? '');
}

typedef FavouritePlaylist<T, E, S> = RxBaseCore<GeneralPlaylist<T, S>>;

extension FavouritePlaylistUtils<T, E, S> on RxBaseCore<GeneralPlaylist<T, S>> {
  bool isSubItemFavourite(E item) {
    for (final entry in value.tracks) {
      if (entry == item) return true;
      try {
        if ((entry as dynamic).track == item) return true;
      } catch (_) {}
      try {
        if ((entry as dynamic).id == item) return true;
      } catch (_) {}
    }
    return false;
  }
}

abstract class PlaylistManager<T extends PlaylistItemWithDate, E, S> {
  final playlistsMap = <String, GeneralPlaylist<T, S>>{}.obs;
  final customIndicesOrderRx = <String>[].obs;

  RxBaseCore<GeneralPlaylist<T, S>>? _favouritesPlaylist;
  RxBaseCore<GeneralPlaylist<T, S>> get favouritesPlaylist => _favouritesPlaylist ??= GeneralPlaylist<T, S>(name: PLAYLIST_NAME_FAV).obs;

  final Completer<void> _playlistsCompleter = Completer<void>();
  final Completer<void> _favouritesCompleter = Completer<void>();

  Future<void> get waitForPlaylistsLoad => _playlistsCompleter.future;
  Future<void> get waitForFavouritePlaylistLoad => _favouritesCompleter.future;

  RegExp get cleanupFilenameRegex => RegExp(r'[\\/:*?"<>|]');
  E identifyBy(T item);

  String get playlistsDirectory;
  String get playlistsArtworksDirectory;
  String get playlistsMetadataDirectory;
  String get favouritePlaylistPath;
  bool get sortAfterPreparing => false;
  bool get addTracksAtBeginning => false;

  String get EMPTY_NAME => 'Empty name';
  String get NAME_CONTAINS_BAD_CHARACTER => 'Name contains invalid character';
  String get SAME_NAME_EXISTS => 'Same name exists';
  String get NAME_IS_NOT_ALLOWED => 'Name is not allowed';
  String get PLAYLIST_NAME_FAV => 'Favourites';
  String get PLAYLIST_NAME_HISTORY => 'History';
  String get PLAYLIST_NAME_MOST_PLAYED => 'Most Played';

  Map<String, dynamic> itemToJson(T item);
  dynamic sortToJson(List<S> items) => items.map((e) => e.toString()).toList();
  void sortPlaylists() {}
  void onPlaylistItemsSort(List<S> sorts, bool reverse, List<T> items) {}
  FutureOr<void> onPlaylistTracksChanged(GeneralPlaylist<T, S> playlist) {}
  FutureOr<bool> canSavePlaylist(GeneralPlaylist<T, S> playlist) => true;
  bool canRemovePlaylist(GeneralPlaylist<T, S> playlist) => true;
  void onPlaylistRemovedFromMap(List<String> names) {}

  Future<Map<String, GeneralPlaylist<T, S>>> prepareAllPlaylistsFunction() async => <String, GeneralPlaylist<T, S>>{};
  Future<GeneralPlaylist<T, S>?> prepareFavouritePlaylistFunction() async => null;

  bool get canReorderItems => true;
  void resetCanReorder() {}

  String? validatePlaylistName(String? name, {String? oldName}) {
    final value = name?.trim() ?? '';
    if (value.isEmpty) return EMPTY_NAME;
    if (cleanupFilenameRegex.hasMatch(value)) return NAME_CONTAINS_BAD_CHARACTER;
    if (isOneOfDefaultPlaylists(value) && value != oldName) return NAME_IS_NOT_ALLOWED;
    if (playlistsMap.value.containsKey(value) && value != oldName) return SAME_NAME_EXISTS;
    return null;
  }

  bool isOneOfDefaultPlaylists(String name) => name == PLAYLIST_NAME_FAV || name == PLAYLIST_NAME_HISTORY || name == PLAYLIST_NAME_MOST_PLAYED;

  GeneralPlaylist<T, S>? getPlaylist(String? name) {
    if (name == null) return null;
    if (name == PLAYLIST_NAME_FAV) return favouritesPlaylist.value;
    return playlistsMap.value[name];
  }

  Future<void> prepareAllPlaylistsFile() async {
    try {
      final map = await prepareAllPlaylistsFunction();
      playlistsMap.value = map;
      ensureCustomOrderValid(removeNonExistent: true);
      if (sortAfterPreparing) sortPlaylists();
    } finally {
      if (!_playlistsCompleter.isCompleted) _playlistsCompleter.complete();
    }
  }

  Future<void> prepareDefaultPlaylistsFileAsync() async {
    try {
      final fav = await prepareFavouritePlaylistFunction();
      _favouritesPlaylist = (fav ?? GeneralPlaylist<T, S>(name: PLAYLIST_NAME_FAV)).obs;
    } finally {
      if (!_favouritesCompleter.isCompleted) _favouritesCompleter.complete();
    }
  }

  Future<GeneralPlaylist<T, S>> addNewPlaylistRaw({
    required String name,
  }) async => throw UnimplementedError();

  Future<GeneralPlaylist<T, S>> addNewPlaylistRawCompat(
    String name, {
    List<E> tracks = const [],
    required T Function(E item, int dateAdded, PlaylistID playlistID) convertItem,
    int? creationDate,
    String comment = '',
    List<String> moods = const [],
    String? m3uPath,
    required FutureOr<PlaylistAddDuplicateAction> Function() actionIfAlreadyExists,
  }) async {
    return _addNewPlaylistRawInternal(
      name,
      tracks: tracks,
      convertItem: convertItem,
      creationDate: creationDate,
      comment: comment,
      moods: moods,
      m3uPath: m3uPath,
      actionIfAlreadyExists: actionIfAlreadyExists,
    );
  }

  Future<GeneralPlaylist<T, S>> _addNewPlaylistRawInternal(
    String name, {
    required List<E> tracks,
    required T Function(E item, int dateAdded, PlaylistID playlistID) convertItem,
    int? creationDate,
    required String comment,
    required List<String> moods,
    String? m3uPath,
    required FutureOr<PlaylistAddDuplicateAction> Function() actionIfAlreadyExists,
  }) async {
    name = name.trim();
    final existing = playlistsMap.value[name];
    if (existing != null) {
      final action = await actionIfAlreadyExists();
      if (action == PlaylistAddDuplicateAction.deleteAndCreateNewPlaylist) {
        await removePlaylist(name);
      } else {
        await addTracksToPlaylistRaw(
          existing,
          tracks,
          () => action,
          (item, dateAdded) => convertItem(item, dateAdded, existing.playlistID),
        );
        return existing;
      }
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final id = PlaylistID(id: name);
    final converted = <T>[];
    var offset = 0;
    for (final item in tracks) {
      converted.add(convertItem(item, now + offset++, id));
    }
    if (addTracksAtBeginning) converted.sort((a, b) => b.dateAddedMS.compareTo(a.dateAddedMS));
    final playlist = GeneralPlaylist<T, S>(
      name: name,
      tracks: converted,
      creationDate: creationDate ?? now,
      modifiedDate: now,
      comment: comment,
      moods: moods,
      m3uPath: m3uPath,
      playlistID: id,
    );
    playlistsMap.value[name] = playlist;
    playlistsMap.refresh();
    ensureCustomOrderValid(removeNonExistent: true);
    await _savePlaylist(playlist);
    return playlist;
  }

  Future<int?> addTracksToPlaylistRaw(
    GeneralPlaylist<T, S> playlist,
    List<E> tracks,
    FutureOr<PlaylistAddDuplicateAction> Function() getDuplicateAction,
    T Function(E item, int dateAdded) convertItem,
  ) async {
    if (tracks.isEmpty) return 0;
    final existingIds = <E>{};
    for (final item in playlist.tracks) existingIds.add(identifyBy(item));
    final hasDuplicates = tracks.any(existingIds.contains);
    final action = hasDuplicates ? await getDuplicateAction() : PlaylistAddDuplicateAction.addOnlyMissing;

    if (action == PlaylistAddDuplicateAction.deleteAndCreateNewPlaylist) {
      playlist.tracks.clear();
    } else if (action == PlaylistAddDuplicateAction.addAllAndRemoveOldOnes) {
      final adding = tracks.toSet();
      playlist.tracks.removeWhere((e) => adding.contains(identifyBy(e)));
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final converted = <T>[];
    var offset = 0;
    for (final item in tracks) {
      if (action == PlaylistAddDuplicateAction.addOnlyMissing && existingIds.contains(item)) continue;
      converted.add(convertItem(item, now + offset++));
    }
    if (addTracksAtBeginning) {
      playlist.tracks.insertAll(0, converted);
    } else {
      playlist.tracks.addAll(converted);
    }
    if (action == PlaylistAddDuplicateAction.mergeAndSortByAddedDate) {
      playlist.tracks.sort((a, b) => a.dateAddedMS.compareTo(b.dateAddedMS));
    }
    playlist.modifiedDate = now;
    await onPlaylistTracksChanged(playlist);
    await _savePlaylist(playlist);
    _refreshPlaylist(playlist);
    return converted.length;
  }

  bool toggleTrackFavourite(T item) {
    final playlist = favouritesPlaylist.value;
    final sub = identifyBy(item);
    final index = playlist.tracks.indexWhere((e) => identifyBy(e) == sub);
    final nowFav = index < 0;
    if (nowFav) {
      if (addTracksAtBeginning) {
        playlist.tracks.insert(0, item);
      } else {
        playlist.tracks.add(item);
      }
    } else {
      playlist.tracks.removeAt(index);
    }
    playlist.modifiedDate = DateTime.now().millisecondsSinceEpoch;
    favouritesPlaylist.refresh();
    _saveFavourite();
    return nowFav;
  }

  Future<void> removeTracksFromPlaylist(GeneralPlaylist<T, S> playlist, List<int> indices) async {
    final sorted = indices.toSet().where((e) => e >= 0 && e < playlist.tracks.length).toList()..sort((a, b) => b.compareTo(a));
    for (final index in sorted) playlist.tracks.removeAt(index);
    playlist.modifiedDate = DateTime.now().millisecondsSinceEpoch;
    await onPlaylistTracksChanged(playlist);
    await _savePlaylistOrFavourite(playlist);
    _refreshPlaylist(playlist);
  }

  Future<void> insertTracksInPlaylistWithEachIndex(GeneralPlaylist<T, S> playlist, Map<T, int> items) async {
    final sorted = items.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
    var inserted = 0;
    for (final e in sorted) {
      final index = (e.value + inserted).clamp(0, playlist.tracks.length);
      playlist.tracks.insert(index, e.key);
      inserted++;
    }
    playlist.modifiedDate = DateTime.now().millisecondsSinceEpoch;
    await onPlaylistTracksChanged(playlist);
    await _savePlaylistOrFavourite(playlist);
    _refreshPlaylist(playlist);
  }

  Future<void> reorderTrack(GeneralPlaylist<T, S> playlist, int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= playlist.tracks.length) return;
    newIndex = newIndex.clamp(0, playlist.tracks.length);
    final item = playlist.tracks.removeAt(oldIndex);
    if (newIndex > oldIndex) newIndex--;
    playlist.tracks.insert(newIndex, item);
    playlist.modifiedDate = DateTime.now().millisecondsSinceEpoch;
    await onPlaylistTracksChanged(playlist);
    await _savePlaylistOrFavourite(playlist);
    _refreshPlaylist(playlist);
  }

  Future<bool> renamePlaylist(String playlistName, String newName) async {
    final playlist = playlistsMap.value[playlistName];
    if (playlist == null) return false;
    if (validatePlaylistName(newName, oldName: playlistName) != null) return false;
    newName = newName.trim();
    playlistsMap.value.remove(playlistName);
    final oldFile = _playlistFile(playlistName);
    playlist.name = newName;
    playlist.playlistID = PlaylistID(id: newName);
    playlist.modifiedDate = DateTime.now().millisecondsSinceEpoch;
    playlistsMap.value[newName] = playlist;
    playlistsMap.refresh();
    try {
      if (await oldFile.exists()) await oldFile.delete();
    } catch (_) {}
    await _savePlaylist(playlist);
    ensureCustomOrderValid(removeNonExistent: true);
    return true;
  }

  Future<void> removePlaylist(String name) => removePlaylists(<String>[name]);

  Future<void> removePlaylists(Iterable<String> names) async {
    final removed = <String>[];
    for (final name in names) {
      final playlist = playlistsMap.value[name];
      if (playlist == null || !canRemovePlaylist(playlist)) continue;
      playlistsMap.value.remove(name);
      removed.add(name);
      try {
        await _playlistFile(name).delete();
      } catch (_) {}
    }
    if (removed.isNotEmpty) {
      playlistsMap.refresh();
      onPlaylistRemovedFromMap(removed);
      ensureCustomOrderValid(removeNonExistent: true);
    }
  }

  Future<void> reAddPlaylist(GeneralPlaylist<T, S> playlist) async {
    playlistsMap.value[playlist.name] = playlist;
    playlistsMap.refresh();
    ensureCustomOrderValid(removeNonExistent: true);
    await _savePlaylist(playlist);
  }

  Future<void> updatePropertyInPlaylist(
    String? playlistName, {
    List<T>? tracks,
    List<E>? tracksRaw,
    T Function(E item, int dateAdded)? convertItem,
    int? modifiedDate,
    int? creationDate,
    String? comment,
    List<String>? moods,
    String? m3uPath,
    List<S>? itemsSortType,
    bool? itemsSortReverse,
  }) async {
    if (playlistName == null) return;
    final playlist = getPlaylist(playlistName);
    if (playlist == null) return;
    if (tracks != null) playlist.tracks = List<T>.from(tracks);
    if (tracksRaw != null && convertItem != null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      playlist.tracks = <T>[
        for (var i = 0; i < tracksRaw.length; i++) convertItem(tracksRaw[i], now + i),
      ];
    }
    if (modifiedDate != null) playlist.modifiedDate = modifiedDate;
    if (creationDate != null) playlist.creationDate = creationDate;
    if (comment != null) playlist.comment = comment;
    if (moods != null) playlist.moods = List<String>.from(moods);
    if (m3uPath != null) playlist.m3uPath = m3uPath.isEmpty ? null : m3uPath;
    if (itemsSortType != null) playlist.sortsType = List<S>.from(itemsSortType);
    if (itemsSortReverse != null) playlist.sortReverse = itemsSortReverse;
    if (modifiedDate == null) playlist.modifiedDate = DateTime.now().millisecondsSinceEpoch;
    if (playlist.sortsType?.isNotEmpty == true) onPlaylistItemsSort(playlist.sortsType!, playlist.sortReverse, playlist.tracks);
    await _savePlaylistOrFavourite(playlist);
    _refreshPlaylist(playlist);
  }

  Future<void> replaceTheseTracksInPlaylists(bool Function(T item) test, T Function(T old) replace) async {
    for (final playlist in <GeneralPlaylist<T, S>>[favouritesPlaylist.value, ...playlistsMap.value.values]) {
      var changed = false;
      for (var i = 0; i < playlist.tracks.length; i++) {
        if (test(playlist.tracks[i])) {
          playlist.tracks[i] = replace(playlist.tracks[i]);
          changed = true;
        }
      }
      if (changed) {
        playlist.modifiedDate = DateTime.now().millisecondsSinceEpoch;
        await _savePlaylistOrFavourite(playlist);
        _refreshPlaylist(playlist);
      }
    }
  }

  Future<void> replaceTheseTracksInPlaylistsBulk(List<MapEntry<bool Function(T item), T Function(T old)>> replacements) async {
    for (final entry in replacements) {
      await replaceTheseTracksInPlaylists(entry.key, entry.value);
    }
  }

  Future<bool> setArtworkForPlaylist(String playlistName, {required File? artworkFile, required Uint8List? artworkBytes}) async {
    try {
      final target = getArtworkFileForPlaylist(playlistName);
      await target.parent.create(recursive: true);
      if (artworkBytes != null) {
        await target.writeAsBytes(artworkBytes, flush: true);
      } else if (artworkFile != null) {
        await artworkFile.copy(target.path);
      } else {
        if (await target.exists()) await target.delete();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  File getArtworkFileForPlaylist(String playlistName) {
    final safe = playlistName.replaceAll(cleanupFilenameRegex, '_');
    return File('${playlistsArtworksDirectory}${Platform.pathSeparator}$safe.jpg');
  }

  RxBaseCore<List<String>> getCustomIndicesOrderListRx() => customIndicesOrderRx;

  void ensureCustomOrderValid({bool removeNonExistent = false}) {
    final names = playlistsMap.value.keys.toList();
    final current = customIndicesOrderRx.value;
    if (removeNonExistent) current.removeWhere((e) => !playlistsMap.value.containsKey(e));
    for (final name in names) {
      if (!current.contains(name)) current.add(name);
    }
    customIndicesOrderRx.refresh();
  }

  void onPlaylistReorder(int oldIndex, int newIndex) {
    final list = customIndicesOrderRx.value;
    if (oldIndex < 0 || oldIndex >= list.length) return;
    newIndex = newIndex.clamp(0, list.length);
    final item = list.removeAt(oldIndex);
    if (newIndex > oldIndex) newIndex--;
    list.insert(newIndex, item);
    customIndicesOrderRx.refresh();
  }

  Future<void> _savePlaylistOrFavourite(GeneralPlaylist<T, S> playlist) async {
    if (identical(playlist, favouritesPlaylist.value) || playlist.name == PLAYLIST_NAME_FAV) {
      await _saveFavourite();
    } else {
      await _savePlaylist(playlist);
    }
  }

  Future<void> _savePlaylist(GeneralPlaylist<T, S> playlist) async {
    if (!await Future<bool>.sync(() => canSavePlaylist(playlist))) return;
    try {
      final file = _playlistFile(playlist.name);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(playlist.toJson(itemToJson, sortToJson)), flush: true);
    } catch (_) {}
  }

  Future<void> _saveFavourite() async {
    try {
      final file = File(favouritePlaylistPath);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(favouritesPlaylist.value.toJson(itemToJson, sortToJson)), flush: true);
    } catch (_) {}
  }

  File _playlistFile(String name) {
    final safe = name.replaceAll(cleanupFilenameRegex, '_');
    return File('${playlistsDirectory}${Platform.pathSeparator}$safe.json');
  }

  void _refreshPlaylist(GeneralPlaylist<T, S> playlist) {
    if (identical(playlist, favouritesPlaylist.value) || playlist.name == PLAYLIST_NAME_FAV) {
      favouritesPlaylist.refresh();
    } else {
      playlistsMap.refresh();
    }
  }
}
