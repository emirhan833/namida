import 'dart:async';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;

void main() {
  runApp(const NamidaMacOSLiteApp());
}

class NamidaMacOSLiteApp extends StatelessWidget {
  const NamidaMacOSLiteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Namida macOS Lite',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFFE89B73),
        scaffoldBackgroundColor: const Color(0xFF101013),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1A1A20),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: const PlayerHomePage(),
    );
  }
}

class LocalTrack {
  final String path;
  final String title;
  final String extension;

  const LocalTrack({
    required this.path,
    required this.title,
    required this.extension,
  });

  factory LocalTrack.fromPath(String filePath) {
    return LocalTrack(
      path: filePath,
      title: p.basenameWithoutExtension(filePath),
      extension: p.extension(filePath).replaceFirst('.', '').toUpperCase(),
    );
  }
}

class PlayerHomePage extends StatefulWidget {
  const PlayerHomePage({super.key});

  @override
  State<PlayerHomePage> createState() => _PlayerHomePageState();
}

class _PlayerHomePageState extends State<PlayerHomePage> {
  final AudioPlayer _player = AudioPlayer(maxSkipsOnError: 3);
  final List<LocalTrack> _tracks = [];
  final TextEditingController _searchController = TextEditingController();

  StreamSubscription<int?>? _indexSubscription;
  StreamSubscription<PlayerException>? _errorSubscription;

  int? _currentIndex;
  String _search = '';
  String? _lastError;

  @override
  void initState() {
    super.initState();
    _indexSubscription = _player.currentIndexStream.listen((index) {
      if (!mounted) return;
      setState(() => _currentIndex = index);
    });
    _errorSubscription = _player.errorStream.listen((error) {
      if (!mounted) return;
      setState(() => _lastError = error.message);
    });
  }

  @override
  void dispose() {
    _indexSubscription?.cancel();
    _errorSubscription?.cancel();
    _searchController.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _pickTracks() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowMultiple: true,
      allowedExtensions: const [
        'mp3',
        'm4a',
        'aac',
        'wav',
        'flac',
        'ogg',
        'opus',
        'aiff',
        'aif',
        'caf',
      ],
    );

    if (result == null) return;

    final selected = result.files
        .map((file) => file.path)
        .whereType<String>()
        .where((path) => !_tracks.any((track) => track.path == path))
        .map(LocalTrack.fromPath)
        .toList();

    if (selected.isEmpty) return;

    final wasEmpty = _tracks.isEmpty;
    setState(() {
      _tracks.addAll(selected);
      _lastError = null;
    });

    final sources = selected
        .map(
          (track) => AudioSource.uri(
            Uri.file(track.path),
            tag: track.title,
          ),
        )
        .toList();

    try {
      if (wasEmpty) {
        await _player.setAudioSources(
          sources,
          initialIndex: 0,
          initialPosition: Duration.zero,
        );
      } else {
        await _player.addAudioSources(sources);
      }
    } on PlayerException catch (e) {
      if (!mounted) return;
      setState(() => _lastError = e.message);
    }
  }

  Future<void> _playTrack(int index) async {
    if (index < 0 || index >= _tracks.length) return;
    try {
      await _player.seek(Duration.zero, index: index);
      await _player.play();
    } on PlayerException catch (e) {
      if (!mounted) return;
      setState(() => _lastError = e.message);
    }
  }

  Future<void> _removeTrack(int index) async {
    if (index < 0 || index >= _tracks.length) return;
    try {
      await _player.removeAudioSourceAt(index);
    } catch (_) {
      // Keep the UI usable even if the player has already dropped the item.
    }
    if (!mounted) return;
    setState(() {
      _tracks.removeAt(index);
      if (_tracks.isEmpty) _currentIndex = null;
    });
  }

  Future<void> _clearPlaylist() async {
    await _player.stop();
    await _player.clearAudioSources();
    if (!mounted) return;
    setState(() {
      _tracks.clear();
      _currentIndex = null;
      _lastError = null;
    });
  }

  Future<void> _togglePlayback() async {
    if (_tracks.isEmpty) return;
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> _previous() async {
    if (_tracks.isEmpty) return;
    final index = _player.currentIndex ?? 0;
    if (index > 0) {
      await _player.seekToPrevious();
    } else {
      await _player.seek(Duration.zero, index: 0);
    }
  }

  Future<void> _next() async {
    if (_tracks.isEmpty) return;
    final index = _player.currentIndex ?? 0;
    if (index < _tracks.length - 1) {
      await _player.seekToNext();
    }
  }

  String _formatDuration(Duration value) {
    final totalSeconds = value.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  List<MapEntry<int, LocalTrack>> get _visibleTracks {
    final query = _search.trim().toLowerCase();
    final indexed = _tracks.asMap().entries;
    if (query.isEmpty) return indexed.toList();
    return indexed
        .where((entry) => entry.value.title.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _buildSidebar(),
          Expanded(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(child: _buildLibrary()),
                _buildPlayerBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 220,
      decoration: const BoxDecoration(
        color: Color(0xFF151519),
        border: Border(
          right: BorderSide(color: Color(0xFF25252C)),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  _LogoMark(),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Namida',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'macOS Lite 0.1',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF8B8B96),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 34),
              _SideItem(
                icon: Icons.library_music_rounded,
                label: 'Library',
                selected: true,
                onTap: () {},
              ),
              _SideItem(
                icon: Icons.queue_music_rounded,
                label: 'Queue',
                selected: false,
                onTap: () {},
              ),
              _SideItem(
                icon: Icons.history_rounded,
                label: 'History',
                selected: false,
                onTap: () {},
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E24),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.computer_rounded, size: 18),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Native macOS prototype',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 86,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Color(0xFF101013),
        border: Border(
          bottom: BorderSide(color: Color(0xFF222228)),
        ),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Local Library',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Your music, directly from this Mac',
                  style: TextStyle(
                    color: Color(0xFF9696A0),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 270,
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _search = value),
              decoration: const InputDecoration(
                hintText: 'Search tracks',
                prefixIcon: Icon(Icons.search_rounded),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: _pickTracks,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add music'),
          ),
        ],
      ),
    );
  }

  Widget _buildLibrary() {
    if (_tracks.isEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Container(
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: const Color(0xFF17171C),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFF292931)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _LogoMark(size: 64),
                const SizedBox(height: 18),
                const Text(
                  'Add your first songs',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'This first macOS build focuses on local playback. MP3, FLAC, M4A, AAC, WAV, OGG and OPUS files are supported.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF9A9AA5),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _pickTracks,
                  icon: const Icon(Icons.folder_open_rounded),
                  label: const Text('Choose music files'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final visible = _visibleTracks;
    return Column(
      children: [
        if (_lastError != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF3B2020),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _lastError!,
              style: const TextStyle(color: Color(0xFFFFC8C8)),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 10),
          child: Row(
            children: [
              Text(
                '${_tracks.length} track${_tracks.length == 1 ? '' : 's'}',
                style: const TextStyle(color: Color(0xFF9696A0)),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _clearPlaylist,
                icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                label: const Text('Clear'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            itemCount: visible.length,
            itemBuilder: (context, listIndex) {
              final entry = visible[listIndex];
              final index = entry.key;
              final track = entry.value;
              final active = index == _currentIndex;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Material(
                  color: active
                      ? const Color(0xFF32251F)
                      : const Color(0xFF17171C),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _playTrack(index),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: active
                                  ? const Color(0xFFE89B73)
                                  : const Color(0xFF24242B),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              active
                                  ? Icons.graphic_eq_rounded
                                  : Icons.music_note_rounded,
                              color: active ? Colors.black : Colors.white70,
                            ),
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  track.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: active
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${track.extension}  •  Local file',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF8E8E99),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remove',
                            onPressed: () => _removeTrack(index),
                            icon: const Icon(Icons.close_rounded, size: 19),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPlayerBar() {
    final track = (_currentIndex != null &&
            _currentIndex! >= 0 &&
            _currentIndex! < _tracks.length)
        ? _tracks[_currentIndex!]
        : null;

    return Container(
      height: 118,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF16161B),
        border: Border(
          top: BorderSide(color: Color(0xFF292930)),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 240,
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A211E),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.album_rounded,
                    color: Color(0xFFE89B73),
                    size: 30,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track?.title ?? 'Nothing playing',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        track == null ? 'Add music to begin' : 'Local library',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF8F8F99),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                StreamBuilder<bool>(
                  stream: _player.playingStream,
                  initialData: _player.playing,
                  builder: (context, snapshot) {
                    final playing = snapshot.data ?? false;
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          onPressed: _tracks.isEmpty ? null : _previous,
                          icon: const Icon(Icons.skip_previous_rounded),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _tracks.isEmpty ? null : _togglePlayback,
                          style: FilledButton.styleFrom(
                            shape: const CircleBorder(),
                            padding: const EdgeInsets.all(13),
                          ),
                          child: Icon(
                            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _tracks.isEmpty ? null : _next,
                          icon: const Icon(Icons.skip_next_rounded),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 3),
                StreamBuilder<Duration?>(
                  stream: _player.durationStream,
                  builder: (context, durationSnapshot) {
                    final duration = durationSnapshot.data ?? Duration.zero;
                    return StreamBuilder<Duration>(
                      stream: _player.positionStream,
                      initialData: Duration.zero,
                      builder: (context, positionSnapshot) {
                        final position = positionSnapshot.data ?? Duration.zero;
                        final maxMs = math.max(1, duration.inMilliseconds).toDouble();
                        final valueMs = math.min(
                          position.inMilliseconds.toDouble(),
                          maxMs,
                        );
                        return Row(
                          children: [
                            SizedBox(
                              width: 42,
                              child: Text(
                                _formatDuration(position),
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF90909A),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Slider(
                                min: 0,
                                max: maxMs,
                                value: valueMs,
                                onChanged: duration == Duration.zero
                                    ? null
                                    : (value) => _player.seek(
                                          Duration(milliseconds: value.round()),
                                        ),
                              ),
                            ),
                            SizedBox(
                              width: 42,
                              child: Text(
                                _formatDuration(duration),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF90909A),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(width: 240),
        ],
      ),
    );
  }
}

class _LogoMark extends StatelessWidget {
  final double size;

  const _LogoMark({this.size = 42});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF2B18B), Color(0xFFD97864)],
        ),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(
        Icons.music_note_rounded,
        size: size * 0.55,
        color: Colors.black,
      ),
    );
  }
}

class _SideItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SideItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? const Color(0xFF30241F) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: selected
                      ? const Color(0xFFF0AA84)
                      : const Color(0xFF8F8F99),
                ),
                const SizedBox(width: 11),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? Colors.white : const Color(0xFFB0B0B8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
