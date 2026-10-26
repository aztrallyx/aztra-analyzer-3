// Orquesta el analisis con FFmpeg. Adaptado de Mornye (LGPL-3.0), ver NOTICE.
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';
import 'package:path_provider/path_provider.dart';

import 'audio_analysis_ffmpeg.dart';
import 'audio_analysis_models.dart';

class _MediaInfo {
  _MediaInfo({
    required this.fileSize,
    required this.codecName,
    required this.container,
    required this.decodedSampleFormat,
    required this.sampleRate,
    required this.channels,
    required this.channelLayout,
    required this.bitsPerSample,
    required this.duration,
    required this.bitrate,
    required this.totalSamples,
  });
  final int fileSize;
  final String codecName;
  final String container;
  final String decodedSampleFormat;
  final int sampleRate;
  final int channels;
  final String channelLayout;
  final int bitsPerSample;
  final double duration;
  final int bitrate;
  final int totalSamples;
}

class _CutoffTask {
  const _CutoffTask(this.gray, this.maxHz);
  final Uint8List gray;
  final double maxHz;
}

double? _runCutoff(_CutoffTask t) => estimateEffectiveSpectralCutoffHz(
  intensity: t.gray,
  width: audioSpectralAnalysisWidth,
  height: audioSpectrogramHeight,
  maxFrequencyHz: t.maxHz,
);

class _Levels {
  const _Levels(this.summary, this.meta, this.channelStats);
  final AudioAstatsSummary summary;
  final AudioAnalysisMetadataSummary? meta;
  final List<ChannelAnalysisStats> channelStats;
}

class Analyzer {
  /// Evita que dos analisis simultaneos compartan nombre de archivo temporal.
  static int _seq = 0;

  /// Analisis numerico (sin imagen): pico, RMS, LUFS, pico real, canales y
  /// corte espectral. El espectrograma a color se genera aparte, al abrir.
  Future<AudioAnalysisData> analyze(String path) async {
    final info = await _mediaInfo(path);
    if (!isAudioAnalysisCodecSupported(info.codecName)) {
      throw Exception('Códec no soportado para análisis');
    }
    if (info.sampleRate <= 0) {
      throw Exception('No pude leer la frecuencia de muestreo');
    }
    final effectiveDuration = info.totalSamples > 0
        ? info.totalSamples / info.sampleRate
        : info.duration;

    final tmp = await getTemporaryDirectory();
    final stamp = '${DateTime.now().microsecondsSinceEpoch}_${_seq++}';
    final cutoffPath = '${tmp.path}/cutoff_$stamp.gray';
    final astatsPath = '${tmp.path}/astats_$stamp.txt';
    final loudnessPath = '${tmp.path}/loudness_$stamp.txt';

    try {
      // Las mediciones son independientes (cada FFmpeg usa un solo hilo para
      // su cadena de filtros), asi que corren al mismo tiempo: corte
      // espectral, astats y ebur128 = 3 sesiones por cancion. Con
      // eagerError:false se espera a todas antes de limpiar archivos
      // temporales, incluso si una falla.
      final results = await Future.wait<Object?>([
        _measureCutoff(path, cutoffPath, effectiveDuration, info),
        _measureLevels(path, astatsPath, loudnessPath, effectiveDuration),
      ], eagerError: false);
      final cutoffHz = results[0] as double?;
      final levels = results[1] as _Levels;
      final summary = levels.summary;
      final channelStats = levels.channelStats;
      final meta = levels.meta;
      final clipping = channelStats.fold<int>(0, (sum, s) {
        if (s.peakDb == null || s.peakDb! < -0.1) return sum;
        return sum + s.peakCount;
      });

      return AudioAnalysisData(
        filePath: path,
        fileSize: info.fileSize,
        codec: info.codecName.toUpperCase(),
        container: info.container,
        decodedSampleFormat: info.decodedSampleFormat,
        sampleRate: info.sampleRate,
        channels: info.channels,
        channelLayout: info.channelLayout,
        bitsPerSample: info.bitsPerSample,
        duration: info.duration,
        bitrate: info.bitrate,
        bitDepth: info.bitsPerSample > 0 ? '${info.bitsPerSample}-bit' : 'N/A',
        dynamicRange: summary.peakDb - summary.rmsDb,
        peakAmplitude: summary.peakDb,
        rmsLevel: summary.rmsDb,
        integratedLufs: meta?.integratedLufs,
        truePeakDb: meta?.truePeakDb,
        clippingSamples: clipping,
        spectralCutoffHz: cutoffHz,
        channelStats: channelStats,
        totalSamples: info.totalSamples,
      );
    } finally {
      for (final p in [cutoffPath, astatsPath, loudnessPath]) {
        try {
          final f = File(p);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }
  }

  /// Plano gris para el corte espectral + estimacion (en otro isolate).
  Future<double?> _measureCutoff(
    String path,
    String cutoffPath,
    double effectiveDuration,
    _MediaInfo info,
  ) async {
    await _run(
      buildAudioCutoffOnlyArguments(
        inputPath: path,
        cutoffOutputPath: cutoffPath,
        durationSeconds: effectiveDuration,
        sampleRate: info.sampleRate,
        channels: info.channels,
      ),
      'corte espectral',
    );
    final gray = await File(cutoffPath).readAsBytes();
    final expected = audioSpectralAnalysisWidth * audioSpectrogramHeight;
    if (gray.length != expected) {
      throw Exception('Salida de corte espectral incompleta');
    }
    final task = _CutoffTask(gray, info.sampleRate / 2);
    return Isolate.run(() => _runCutoff(task));
  }

  /// Niveles: pico, RMS, LUFS, pico real, por canal. astats y ebur128 corren
  /// en sesiones separadas y simultaneas (ebur128 con pico real es lo mas
  /// pesado de todo el analisis).
  Future<_Levels> _measureLevels(
    String path,
    String astatsPath,
    String loudnessPath,
    double effectiveDuration,
  ) async {
    var fallbackLogs = '';

    Future<String> readIfExists(String p) async {
      final f = File(p);
      return await f.exists() ? await f.readAsString() : '';
    }

    Future<String> runAstats() async {
      final session = await FFmpegKit.executeWithArguments(
        buildAudioAstatsArguments(
          inputPath: path,
          metadataPath: astatsPath,
          durationSeconds: effectiveDuration,
        ),
      );
      final rc = await session.getReturnCode();
      if (!ReturnCode.isSuccess(rc)) {
        throw Exception('FFmpeg falló al medir niveles');
      }
      final text = await readIfExists(astatsPath);
      if (parseAudioAnalysisMetadata(text) == null) {
        fallbackLogs = await session.getAllLogsAsString() ?? '';
      }
      return text;
    }

    Future<String> runLoudness() async {
      final session = await FFmpegKit.executeWithArguments(
        buildAudioLoudnessArguments(
          inputPath: path,
          metadataPath: loudnessPath,
          durationSeconds: effectiveDuration,
        ),
      );
      final rc = await session.getReturnCode();
      if (!ReturnCode.isSuccess(rc)) {
        throw Exception('FFmpeg falló al medir niveles');
      }
      return readIfExists(loudnessPath);
    }

    final texts = await Future.wait<String>([
      runAstats(),
      runLoudness(),
    ], eagerError: false);
    final meta = parseAudioAnalysisMetadata('${texts[0]}\n${texts[1]}');
    final summary = meta ?? parseAudioAstatsSummary(fallbackLogs);
    if (summary == null) {
      throw Exception('No se pudieron leer los niveles');
    }
    final channelStats = meta?.channelStats.isNotEmpty == true
        ? meta!.channelStats
        : parseChannelStats(fallbackLogs);
    return _Levels(summary, meta, channelStats);
  }

  /// Espectrograma a color (misma cadena de Mornye). [channel] -1 = combinado.
  Future<ui.Image> generateSpectrogram(
    String path,
    AudioAnalysisData data, {
    int channel = -1,
  }) async {
    final effectiveDuration = data.totalSamples > 0 && data.sampleRate > 0
        ? data.totalSamples / data.sampleRate
        : data.duration;
    final tmp = await getTemporaryDirectory();
    final rawPath =
        '${tmp.path}/spec_${DateTime.now().microsecondsSinceEpoch}_${_seq++}.rgba';
    try {
      await _run(
        buildAudioSpectrogramArguments(
          inputPath: path,
          outputPath: rawPath,
          channel: channel,
          durationSeconds: effectiveDuration,
          sampleRate: data.sampleRate,
          channels: data.channels,
        ),
        'espectrograma',
      );
      final expected = audioSpectrogramWidth * audioSpectrogramHeight * 4;
      final raw = await File(rawPath).readAsBytes();
      if (raw.length < expected) throw Exception('Espectrograma incompleto');
      final rgba = raw.length == expected
          ? raw
          : Uint8List.sublistView(raw, 0, expected);
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        rgba,
        audioSpectrogramWidth,
        audioSpectrogramHeight,
        ui.PixelFormat.rgba8888,
        completer.complete,
      );
      return await completer.future;
    } finally {
      try {
        final f = File(rawPath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  /// Cancela lo que FFmpeg este haciendo ahora mismo.
  Future<void> cancelAll() => FFmpegKit.cancel();

  Future<void> _run(List<String> args, String what) async {
    final session = await FFmpegKit.executeWithArguments(args);
    final rc = await session.getReturnCode();
    if (!ReturnCode.isSuccess(rc)) {
      final logs = await session.getAllLogsAsString() ?? '';
      final tail = logs.length > 300 ? logs.substring(logs.length - 300) : logs;
      throw Exception('FFmpeg falló ($what): $tail');
    }
  }

  Future<_MediaInfo> _mediaInfo(String filePath) async {
    final probe = await FFprobeKit.getMediaInformation(filePath);
    final info = probe.getMediaInformation();
    if (info == null) throw Exception('No se pudo leer el archivo');

    var fileSize = 0;
    try {
      fileSize = await File(filePath).length();
    } catch (_) {}

    final audioStream = info.getStreams().firstWhere(
      (s) => s.getAllProperties()?['codec_type'] == 'audio',
      orElse: () => throw Exception('No hay pista de audio'),
    );
    final props = audioStream.getAllProperties() ?? {};
    final infoProps = info.getAllProperties() ?? {};
    final codecName = props['codec_name']?.toString().toLowerCase() ?? '';
    final sampleRate =
        int.tryParse(props['sample_rate']?.toString() ?? '') ?? 0;
    final channels = int.tryParse(props['channels']?.toString() ?? '') ?? 0;
    final streamDuration = double.tryParse(props['duration']?.toString() ?? '');
    final containerDuration = double.tryParse(info.getDuration() ?? '');
    final duration =
        (streamDuration != null && streamDuration > 0
            ? streamDuration
            : containerDuration) ??
        0;
    final bitrate =
        int.tryParse(props['bit_rate']?.toString() ?? '') ??
        int.tryParse(info.getBitrate() ?? '') ??
        (duration > 0 && fileSize > 0 ? (fileSize * 8 / duration).round() : 0);

    var bits = 0;
    if (_hasStoredBitDepth(codecName)) {
      bits = int.tryParse(props['bits_per_raw_sample']?.toString() ?? '') ?? 0;
      if (bits == 0) {
        bits = int.tryParse(props['bits_per_sample']?.toString() ?? '') ?? 0;
      }
      if (bits == 0) {
        final fmt = props['sample_fmt']?.toString() ?? '';
        if (fmt.contains('16')) {
          bits = 16;
        } else if (fmt.contains('24')) {
          bits = 24;
        } else if (fmt.contains('32') || fmt == 'flt' || fmt == 'fltp') {
          bits = 32;
        }
      }
    }

    final formatLong = infoProps['format_long_name']?.toString().trim() ?? '';
    final formatName = infoProps['format_name']?.toString().trim() ?? '';
    return _MediaInfo(
      fileSize: fileSize,
      codecName: codecName,
      container: formatLong.isNotEmpty ? formatLong : formatName.toUpperCase(),
      decodedSampleFormat: props['sample_fmt']?.toString() ?? '',
      sampleRate: sampleRate,
      channels: channels,
      channelLayout:
          props['channel_layout']?.toString() ??
          props['ch_layout']?.toString() ??
          '',
      bitsPerSample: bits,
      duration: duration,
      bitrate: bitrate,
      totalSamples: _totalSamples(props, duration, sampleRate),
    );
  }

  bool _hasStoredBitDepth(String c) =>
      c == 'flac' ||
      c == 'alac' ||
      c == 'wavpack' ||
      c == 'ape' ||
      c == 'tta' ||
      c.startsWith('pcm_');

  int _totalSamples(Map<dynamic, dynamic> props, double duration, int sr) {
    final nb = int.tryParse(props['nb_samples']?.toString() ?? '');
    if (nb != null && nb > 0) return nb;
    final ts = int.tryParse(props['duration_ts']?.toString() ?? '');
    final tb = props['time_base']?.toString() ?? '';
    if (ts != null && ts > 0 && tb.contains('/') && sr > 0) {
      final parts = tb.split('/');
      final n = double.tryParse(parts[0]);
      final d = double.tryParse(parts[1]);
      if (n != null && n > 0 && d != null && d > 0) {
        return (ts * n / d * sr).round();
      }
    }
    if (duration > 0 && sr > 0) return (duration * sr).round();
    return 0;
  }
}
