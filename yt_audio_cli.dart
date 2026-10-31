import 'dart:async';
import 'dart:io';
import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main(List<String> arguments) async {
  final parser = ArgParser()
  ..addOption('url', abbr: 'u', help: 'YouTube URL / Video ID / Playlist URL')
  ..addOption('output', abbr: 'o', defaultsTo: 'downloads', help: 'תיקיית יעד')
  ..addFlag('list', abbr: 'l', help: 'הצג streams ובחר איכות')
  ..addOption('index', abbr: 'i', help: 'מספר stream (כשמשתמשים ב--list)')
  ..addFlag('mp3', defaultsTo: true, help: 'המרה אוטומטית ל-MP3 עם FFmpeg')
  ..addFlag('keep-original', help: 'שמור גם את הקובץ המקורי (webm/m4a)')
  ..addFlag('playlist', abbr: 'p', help: 'כפה טיפול כפלייליסט')
  ..addOption('concurrency',
              abbr: 'c',
              defaultsTo: '3',
                help: 'כמה שירים להוריד במקביל (ברירת מחדל: 3)')
  ..addFlag('help', abbr: 'h', negatable: false);

  late ArgResults args;
  try {
    args = parser.parse(arguments);
  } catch (e) {
    print('❌ שגיאה בפרמטרים: $e\n');
    _printUsage(parser);
    exit(1);
  }

  if (args['help'] as bool || args['url'] == null) {
    _printUsage(parser);
    exit(0);
  }

  final rawUrl = args['url'] as String;
  final forcePlaylist = args['playlist'] as bool;
  final urlOrId = _normalizeUrl(rawUrl, preferPlaylist: forcePlaylist);
  final outputDir = args['output'] as String;
  final showList = args['list'] as bool;
  final convertToMp3 = args['mp3'] as bool;
  final keepOriginal = args['keep-original'] as bool;
  final selectedIndex =
  args['index'] != null ? int.tryParse(args['index'] as String) : null;
  final concurrency = (int.tryParse(args['concurrency'] as String) ?? 3).clamp(1, 10);

  if (convertToMp3 && !await _isFfmpegAvailable()) {
    print('❌ FFmpeg לא נמצא במערכת.');
    print('   התקן אותו ואז נסה שוב, או הרץ עם --no-mp3');
    exit(1);
  }

  final yt = YoutubeExplode();

  try {
    if (forcePlaylist || _looksLikePlaylist(urlOrId)) {
      await _downloadPlaylist(
        yt: yt,
        url: urlOrId,
        outputDir: outputDir,
        convertToMp3: convertToMp3,
        keepOriginal: keepOriginal,
        selectedIndex: selectedIndex,
        concurrency: concurrency,
      );
    } else {
      await _downloadSingle(
        yt: yt,
        urlOrId: urlOrId,
        outputDir: outputDir,
        convertToMp3: convertToMp3,
        keepOriginal: keepOriginal,
        showList: showList,
        selectedIndex: selectedIndex,
      );
    }
  } catch (e) {
    print('\n❌ שגיאה כללית: $e');
  } finally {
    yt.close();
  }
}

// ====================== Single Video ======================

Future<void> _downloadSingle({
  required YoutubeExplode yt,
  required String urlOrId,
  required String outputDir,
  required bool convertToMp3,
  required bool keepOriginal,
  required bool showList,
  int? selectedIndex,
}) async {
  print('🔍 מקבל מידע על הסרטון...');
  final video = await _getVideoWithRetry(yt, urlOrId);

  print('\n📀 ${video.title}');
  print('👤 ${video.author}');
  print('⏱  ${video.duration}\n');

  final stream = await _selectAudioStream(
    yt: yt,
    videoId: video.id,
    showList: showList,
    selectedIndex: selectedIndex,
  );

  if (stream == null) return;

  await Directory(outputDir).create(recursive: true);

  await _downloadAndProcess(
    yt: yt,
    video: video,
    streamInfo: stream,
    outputDir: outputDir,
    convertToMp3: convertToMp3,
    keepOriginal: keepOriginal,
    showProgress: true,
  );
}

// ====================== Playlist ======================

Future<void> _downloadPlaylist({
  required YoutubeExplode yt,
  required String url,
  required String outputDir,
  required bool convertToMp3,
  required bool keepOriginal,
  int? selectedIndex,
  required int concurrency,
}) async {
  print('📂 טוען פלייליסט...');
  final playlist = await yt.playlists.get(url);
  final videos = await yt.playlists.getVideos(playlist.id).toList();

  print('\n📁 ${playlist.title}');
  print('👤 ${playlist.author}');
  print('🎵 ${videos.length} שירים');
  print('⚡ הורדה מקבילית: $concurrency במקביל\n');

  final playlistDir = p.join(outputDir, _sanitizeFileName(playlist.title));
  await Directory(playlistDir).create(recursive: true);

  var success = 0;
  var failed = 0;

  final semaphore = _Semaphore(concurrency);
  final futures = <Future<void>>[];

  for (var i = 0; i < videos.length; i++) {
    final trackNum = i + 1;
    final video = videos[i];

    futures.add(() async {
      await semaphore.acquire();
      try {
        print('[$trackNum/${videos.length}] ⬇️ מתחיל: ${video.title}');

        final stream = await _selectAudioStream(
          yt: yt,
          videoId: video.id,
          showList: false,
          selectedIndex: selectedIndex,
          silent: true,
        );

        if (stream == null) {
          failed++;
          print('[$trackNum/${videos.length}] ❌ אין stream אודיו: ${video.title}');
          return;
        }

        await _downloadAndProcess(
          yt: yt,
          video: video,
          streamInfo: stream,
          outputDir: playlistDir,
          convertToMp3: convertToMp3,
          keepOriginal: keepOriginal,
          trackNumber: trackNum,
          album: playlist.title,
          showProgress: concurrency == 1, // מציג פס התקדמות רק אם מורידים אחד-אחד
        );

        success++;
        print('[$trackNum/${videos.length}] ✅ הסתיים: ${video.title}');
      } catch (e) {
        failed++;
        print('[$trackNum/${videos.length}] ❌ נכשל (${video.title}): $e');
      } finally {
        semaphore.release();
      }
    }());
  }

  await Future.wait(futures);

  print('\n════════════════════════════════');
  print('✅ הושלם: $success הצליחו | ❌ $failed נכשלו');
  print('📁 נשמר בתיקייה: $playlistDir');
}

// ====================== בחירת Stream ======================

Future<AudioOnlyStreamInfo?> _selectAudioStream({
  required YoutubeExplode yt,
  required VideoId videoId,
  required bool showList,
  int? selectedIndex,
  bool silent = false,
}) async {
  StreamManifest? manifest;
  Object? lastErr;
  for (var attempt = 1; attempt <= 3; attempt++) {
    try {
      manifest = await yt.videos.streams.getManifest(
        videoId,
        ytClients: [
          _visionOsClient,
        ],
      );
      break;
    } catch (e) {
      lastErr = e;
      if (attempt < 3) {
        await Future.delayed(Duration(milliseconds: 500 * attempt));
      }
    }
  }
  if (manifest == null) throw lastErr!;

  final audioStreams = manifest.audioOnly.toList();
  if (audioStreams.isEmpty) {
    if (!silent) print('❌ לא נמצאו streams של אודיו');
    return null;
  }

  audioStreams.sort((a, b) => b.bitrate.compareTo(a.bitrate));

  if (showList) {
    print('🎵 Streams זמינים:\n');
    for (var i = 0; i < audioStreams.length; i++) {
      final s = audioStreams[i];
      final sizeMB = (s.size.totalBytes / (1024 * 1024)).toStringAsFixed(1);
      print(
        '  [$i] ${s.bitrate} | ${s.container.name.toUpperCase()} | $sizeMB MB | ${s.audioCodec}');
    }
    print('');

    if (selectedIndex != null) {
      if (selectedIndex < 0 || selectedIndex >= audioStreams.length) {
        print('❌ אינדקס לא חוקי');
        return null;
      }
      return audioStreams[selectedIndex];
    }

    stdout.write('בחר מספר stream (0-${audioStreams.length - 1}): ');
    final input = stdin.readLineSync();
    final idx = int.tryParse(input ?? '');
    if (idx == null || idx < 0 || idx >= audioStreams.length) {
      print('❌ בחירה לא חוקית');
      return null;
    }
    return audioStreams[idx];
  }

  if (selectedIndex != null &&
    selectedIndex >= 0 &&
    selectedIndex < audioStreams.length) {
    return audioStreams[selectedIndex];
    }

    final best = audioStreams.first;
  if (!silent) {
    print('✅ נבחר: ${best.bitrate} | ${best.container.name}');
  }
  return best;
}

// ====================== הורדה + המרה + מטא-דאטה ======================

Future<void> _downloadAndProcess({
  required YoutubeExplode yt,
  required Video video,
  required AudioOnlyStreamInfo streamInfo,
  required String outputDir,
  required bool convertToMp3,
  required bool keepOriginal,
  int? trackNumber,
  String? album,
  bool showProgress = true,
}) async {
  final prefix = trackNumber != null ? '${trackNumber.toString().padLeft(2, '0')} - ' : '';
  final safeTitle = '$prefix${_sanitizeFileName(video.title)}';
  final originalExt = streamInfo.container.name;
  final originalPath = p.join(outputDir, '$safeTitle.$originalExt');
  final mp3Path = p.join(outputDir, '$safeTitle.mp3');

  final originalFile = File(originalPath);
  final mp3File = File(mp3Path);

  // בדיקה אם הקובץ הסופי כבר קיים
  if (convertToMp3 && await mp3File.exists()) {
    if (showProgress) print('⚠️  הקובץ MP3 כבר קיים, מדלג...');
    return;
  } else if (!convertToMp3 && await originalFile.exists()) {
    if (showProgress) print('⚠️  הקובץ כבר קיים, מדלג...');
    return;
  }

  if (!await originalFile.exists()) {
    if (showProgress) print('⬇️  מוריד...');
    final stream = yt.videos.streams.get(streamInfo);
    final output = originalFile.openWrite();

    final total = streamInfo.size.totalBytes;
    var downloaded = 0;
    final sw = Stopwatch()..start();

    try {
      await for (final data in stream) {
        output.add(data);
        downloaded += data.length;
        if (showProgress) {
          final percent = downloaded / total * 100;
          final speed =
          downloaded / (sw.elapsedMilliseconds / 1000 + 0.001) / 1024;
          stdout.write(
            '\r   ${_progressBar(percent)} ${percent.toStringAsFixed(1)}% | ${speed.toStringAsFixed(0)} KB/s');
        }
      }
      await output.flush();
    } catch (e) {
      await output.close();
      if (await originalFile.exists()) await originalFile.delete();
      rethrow;
    } finally {
      await output.close();
    }

    if (showProgress) print('\n   ✅ הורדה הושלמה');
  }

  if (convertToMp3) {
    if (showProgress) print('🔄 ממיר ל-MP3 + מוסיף מטא-דאטה...');

    final metadataArgs = <String>[
      '-metadata',
      'title=${video.title}',
      '-metadata',
      'artist=${video.author}',
      if (album != null) ...['-metadata', 'album=$album'],
        if (trackNumber != null) ...['-metadata', 'track=$trackNumber'],
          if (video.uploadDate != null) ...[
            '-metadata',
            'date=${video.uploadDate!.year}'
          ],
          '-metadata',
          'comment=Downloaded with yt_audio_cli',
    ];

    final result = await Process.run('ffmpeg', [
      '-y',
      '-i',
      originalPath,
      '-vn',
      '-c:a',
      'libmp3lame',
      '-q:a',
      '2',
      ...metadataArgs,
      mp3Path,
    ]);

    if (result.exitCode == 0) {
      if (showProgress) print('   ✅ MP3 נוצר עם מטא-דאטה');
      if (!keepOriginal && await originalFile.exists()) {
        await originalFile.delete();
        if (showProgress) print('   🗑  הקובץ המקורי נמחק');
      }
    } else {
      throw Exception('שגיאת FFmpeg: ${result.stderr}');
    }
  } else {
    if (showProgress) print('📁 נשמר כ: $originalPath');
  }
}

// ====================== Helpers ======================

String _normalizeUrl(String input, {bool preferPlaylist = false}) {
  var url = input
  .replaceAll('music.youtube.com', 'www.youtube.com')
  .replaceAll('m.youtube.com', 'www.youtube.com');

  try {
    final uri = Uri.parse(url);
    if (preferPlaylist && uri.queryParameters.containsKey('list')) {
      return 'https://www.youtube.com/playlist?list=${uri.queryParameters['list']}';
    }
    if (uri.queryParameters.containsKey('v')) {
      return 'https://www.youtube.com/watch?v=${uri.queryParameters['v']}';
    }
    if (uri.queryParameters.containsKey('list')) {
      return 'https://www.youtube.com/playlist?list=${uri.queryParameters['list']}';
    }
  } catch (_) {}

  return url;
}

bool _looksLikePlaylist(String url) {
  return url.contains('list=') || url.contains('playlist?');
}

Future<bool> _isFfmpegAvailable() async {
  try {
    final result = await Process.run('ffmpeg', ['-version']);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

String _sanitizeFileName(String name) {
  final sanitized = name
  .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
  .replaceAll(RegExp(r'\s+'), ' ')
  .trim();
  return sanitized.isEmpty ? 'untitled_audio' : sanitized;
}

String _progressBar(double percent, {int width = 28}) {
  final filled = (percent / 100 * width).round().clamp(0, width);
  return '[${'█' * filled}${'░' * (width - filled)}]';
}

void _printUsage(ArgParser parser) {
  print('''
  🎵 YouTube Audio Downloader CLI (Advanced)

  שימוש:
  dart run bin/yt_audio_cli.dart -u <url> [options]

  אפשרויות:
  ${parser.usage}

  דוגמאות:
  dart run bin/yt_audio_cli.dart -u "https://youtu.be/dQw4w9WgXcQ"
  dart run bin/yt_audio_cli.dart -u "https://music.youtube.com/playlist?list=PLxxxx" -c 4
  dart run bin/yt_audio_cli.dart -u VIDEO_ID --no-mp3
  dart run bin/yt_audio_cli.dart -u VIDEO_ID --list
  ''');
}

// ====================== Semaphore ======================

class _Semaphore {
  final int max;
  int _current = 0;
  final _waitQueue = <Completer<void>>[];

  _Semaphore(this.max);

  Future<void> acquire() async {
    if (_current < max) {
      _current++;
      return;
    }
    final completer = Completer<void>();
    _waitQueue.add(completer);
    await completer.future;
  }

  void release() {
    if (_waitQueue.isNotEmpty) {
      final next = _waitQueue.removeAt(0);
      next.complete();
    } else {
      _current--;
    }
  }
}

// ====================== VisionOS YouTube Client ======================

Future<Video> _getVideoWithRetry(YoutubeExplode yt, String urlOrId) async {
  for (var attempt = 1; attempt <= 4; attempt++) {
    try {
      return await yt.videos.get(urlOrId);
    } on VideoUnavailableException {
      if (attempt == 4) rethrow;
      await Future.delayed(Duration(milliseconds: 500 * attempt));
    }
  }
  return await yt.videos.get(urlOrId);
}

const _visionOsClient = YoutubeApiClient(
  {
    'context': {
      'client': {
        'clientName': 'VISIONOS',
        'clientVersion': '1.02',
        'deviceMake': 'Apple',
        'deviceModel': 'RealityDevice17,1',
        'hl': 'en',
        'osName': 'visionOS',
        'osVersion': '26.5.23O471',
        'userAgent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15',
        'timeZone': 'UTC',
        'utcOffsetMinutes': 0,
      },
    },
  },
  'https://www.youtube.com/youtubei/v1/player?prettyPrint=false',
  headers: {
    'X-Youtube-Client-Name': '101',
  },
);
