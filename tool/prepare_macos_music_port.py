#!/usr/bin/env python3
"""Prepare the real Namida source tree for the macOS music-only build.

The macOS branch keeps Namida's real UI/indexer/playlist/player-controller code.
Private YouTube services are disconnected and the private basic_audio_handler
package is replaced by the local compatibility package in stubs/.
"""

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
PUBSPEC = ROOT / "pubspec.yaml"
STUB_URI = "package:namida/music_only/youtube_stubs.dart"


def remove_dependency_block(text: str, key: str) -> str:
    lines = text.splitlines(keepends=True)
    out: list[str] = []
    i = 0
    marker = f"  {key}:"
    while i < len(lines):
        if lines[i].rstrip("\r\n") == marker:
            i += 1
            while i < len(lines):
                line = lines[i]
                stripped = line.strip()
                if line.startswith("  ") and not line.startswith("    ") and stripped and not stripped.startswith("#"):
                    break
                i += 1
            continue
        out.append(lines[i])
        i += 1
    return "".join(out)


def patch_pubspec() -> None:
    text = PUBSPEC.read_text()
    for dep in (
        "youtipie",
        "namico_login_manager",
        "namico_subscription_manager",
        "basic_audio_handler",
    ):
        text = remove_dependency_block(text, dep)

    # Reintroduce the audio API as a local package. The actual sound engine is
    # lib/base/audio_handler.dart and uses just_audio directly.
    deps_marker = "dependencies:\n"
    local_audio = (
        "dependencies:\n"
        "  basic_audio_handler:\n"
        "    path: stubs/basic_audio_handler\n"
    )
    if deps_marker not in text:
        raise SystemExit("dependencies block not found")
    text = text.replace(deps_marker, local_audio, 1)

    # Known compatible file_picker revision for this Namida snapshot.
    old = (
        "  file_picker:\n"
        "    git:\n"
        "      url: https://github.com/miguelpruivo/flutter_file_picker\n"
    )
    new = old + "      ref: 8dc97859f42ca7ca2d6d347dd7960a3c7b657baf\n"
    if old in text and "8dc97859f42ca7ca2d6d347dd7960a3c7b657baf" not in text:
        text = text.replace(old, new, 1)

    PUBSPEC.write_text(text)


def rewrite_imports() -> None:
    prefixes = (
        "package:youtipie/",
        "package:namida/youtube/",
        "package:namico_login_manager/",
        "package:namico_subscription_manager/",
    )
    for path in (ROOT / "lib").rglob("*.dart"):
        rel = path.relative_to(ROOT).as_posix()
        if rel.startswith("lib/youtube/") or rel.startswith("lib/music_only/"):
            continue
        text = path.read_text()
        original = text
        for prefix in prefixes:
            text = re.sub(
                rf"(?<=['\"])({re.escape(prefix)}[^'\"]+)(?=['\"])",
                STUB_URI,
                text,
            )
        if text != original:
            path.write_text(text)


def patch_music_only_defaults() -> None:
    settings = ROOT / "lib/controller/settings_controller.dart"
    text = settings.read_text()
    text = text.replace("    LibraryTab.youtube,\n", "")
    settings.write_text(text)


def patch_macos_feature_flags() -> None:
    path = ROOT / "lib/core/constants.dart"
    text = path.read_text()
    old = (
        "  static final _isAndroid = _platform == TargetPlatform.android;\n"
        "  static final _isWindows = _platform == TargetPlatform.windows;\n"
        "  static final _isLinux = _platform == TargetPlatform.linux;\n"
    )
    new = old + "  static final _isMacOS = _platform == TargetPlatform.macOS;\n"
    if "static final _isMacOS" not in text and old in text:
        text = text.replace(old, new, 1)

    for source, target in (
        ("static final showDownloadNotifications = _isWindows || _isLinux;", "static final showDownloadNotifications = _isWindows || _isLinux || _isMacOS;"),
        ("static final showVideoControlsOnHover = _isWindows || _isLinux;", "static final showVideoControlsOnHover = _isWindows || _isLinux || _isMacOS;"),
        ("static final tiltingCardsEffect = _isWindows || _isLinux;", "static final tiltingCardsEffect = _isWindows || _isLinux || _isMacOS;"),
        ("static final smoothScrolling = _isWindows || _isLinux;", "static final smoothScrolling = _isWindows || _isLinux || _isMacOS;"),
        ("static final isStoragePermissionNotRequired = _isWindows || _isLinux;", "static final isStoragePermissionNotRequired = _isWindows || _isLinux || _isMacOS;"),
        ("static final recieveDragAndDrop = _isWindows || _isLinux;", "static final recieveDragAndDrop = _isWindows || _isLinux || _isMacOS;"),
    ):
        text = text.replace(source, target)
    path.write_text(text)


def patch_platform_base() -> None:
    path = ROOT / "lib/controller/platform/base.dart"
    text = path.read_text()
    linux_dir = """      linux: () {
        final appDir = Platform.environment['APPDIR'];
        if (appDir != null && appDir.isNotEmpty) {
          // for AppImage
          return p.join(appDir, 'bin');
        }
        var processDir = p.dirname(Platform.resolvedExecutable);
        if (kDebugMode) {
          var midway = r'../../../../../external/ffmpeg_build/linux';
          return p.normalize(p.join(processDir, midway));
        } else {
          return p.join(processDir, 'bin');
        }
      },
"""
    if linux_dir in text and "macos: ()" not in text[text.find("getExecutablesDirectoryPath"):text.find("_getExecutablePath")]:
        text = text.replace(
            linux_dir,
            linux_dir
            + """      macos: () {
        final processDir = p.dirname(Platform.resolvedExecutable);
        return p.join(processDir, 'bin');
      },
""",
            1,
        )

    old_exe = """      android: () => '',
      windows: () => '$name.exe',
      linux: () => name,
"""
    if old_exe in text:
        text = text.replace(old_exe, old_exe + "      macos: () => name,\n", 1)
    path.write_text(text)


def patch_main_music_only_link_handling() -> None:
    path = ROOT / "lib/main.dart"
    text = path.read_text()
    text = text.replace(
        "    final youtubeId = link.getYoutubeID;\n    final youtubePlaylistId = NamidaLinkUtils.extractPlaylistId(link);\n",
        "    const youtubeId = '';\n    const String? youtubePlaylistId = null;\n",
    )
    path.write_text(text)


def main() -> None:
    patch_pubspec()
    rewrite_imports()
    patch_music_only_defaults()
    patch_macos_feature_flags()
    patch_platform_base()
    patch_main_music_only_link_handling()
    print("Prepared Namida macOS music-only source tree")


if __name__ == "__main__":
    main()
