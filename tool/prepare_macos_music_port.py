#!/usr/bin/env python3
"""Prepare the real Namida source tree for the macOS music-only build.

This script intentionally edits only the CI checkout. The repository keeps the
upstream source layout, while the build replaces YouTube/private-package imports
outside lib/youtube with a small compatibility layer. Unreferenced lib/youtube
files are then not part of the Flutter kernel build.
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
                # A new dependency key is exactly two-space indented.
                if line.startswith("  ") and not line.startswith("    ") and stripped and not stripped.startswith("#"):
                    break
                i += 1
            continue
        out.append(lines[i])
        i += 1
    return "".join(out)


def patch_pubspec() -> None:
    text = PUBSPEC.read_text()
    for dep in ("youtipie", "namico_login_manager", "namico_subscription_manager"):
        text = remove_dependency_block(text, dep)

    # Keep the known working flutter_file_picker revision used by the first
    # macOS experiments; upstream HEAD has API/native changes incompatible with
    # this Namida snapshot.
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
            # Replace only the URI, preserving aliases and show/hide clauses.
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

    text = text.replace(
        "static final showDownloadNotifications = _isWindows || _isLinux;",
        "static final showDownloadNotifications = _isWindows || _isLinux || _isMacOS;",
    )
    text = text.replace(
        "static final showVideoControlsOnHover = _isWindows || _isLinux;",
        "static final showVideoControlsOnHover = _isWindows || _isLinux || _isMacOS;",
    )
    text = text.replace(
        "static final tiltingCardsEffect = _isWindows || _isLinux;",
        "static final tiltingCardsEffect = _isWindows || _isLinux || _isMacOS;",
    )
    text = text.replace(
        "static final smoothScrolling = _isWindows || _isLinux;",
        "static final smoothScrolling = _isWindows || _isLinux || _isMacOS;",
    )
    text = text.replace(
        "static final isStoragePermissionNotRequired = _isWindows || _isLinux;",
        "static final isStoragePermissionNotRequired = _isWindows || _isLinux || _isMacOS;",
    )
    text = text.replace(
        "static final recieveDragAndDrop = _isWindows || _isLinux;",
        "static final recieveDragAndDrop = _isWindows || _isLinux || _isMacOS;",
    )
    path.write_text(text)


def patch_platform_base() -> None:
    path = ROOT / "lib/controller/platform/base.dart"
    text = path.read_text()

    # macOS release prefers bundled executables next to the app binary, then the
    # generic helpers already fall back to `which ffmpeg/ffprobe` where enabled.
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
        text = text.replace(
            old_exe,
            old_exe + "      macos: () => name,\n",
            1,
        )

    path.write_text(text)


def patch_main_music_only_link_handling() -> None:
    # Prevent the desktop app from trying to interpret dropped text/URLs as
    # YouTube or Patreon. Local files/directories and M3U input remain intact.
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
