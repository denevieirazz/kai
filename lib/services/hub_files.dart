import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Centraliza a leitura/escrita dos arquivos reais do Hub no PC do usuário.
///
/// Tudo fica em:  <Documentos>/HubAI/
///   - memoria_ia.json  -> histórico completo das conversas com a IA
///   - mapa_mental.json -> nós e conexões do mapa mental
///
/// São arquivos JSON normais: dá pra abrir, ler e até fazer backup na mão.
class HubFiles {
  static Directory? _dir;

  static Future<Directory> _hubDir() async {
    if (_dir != null) return _dir!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}HubAI');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _dir = dir;
    return dir;
  }

  /// Caminho da pasta HubAI (pra mostrar pro usuário).
  static Future<String> hubFolderPath() async => (await _hubDir()).path;

  static Future<File> _file(String name) async {
    final dir = await _hubDir();
    return File('${dir.path}${Platform.pathSeparator}$name');
  }

  // ----------------------------------------------------------------
  // MEMÓRIA DA IA
  // ----------------------------------------------------------------
  static const String _memoryFileName = 'memoria_ia.json';

  /// Lê o histórico salvo. Cada item: {role: 'user'|'model', text: '...', ts: ISO}
  static Future<List<Map<String, dynamic>>> loadMemory() async {
    try {
      final f = await _file(_memoryFileName);
      if (!await f.exists()) return [];
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) return [];
      final data = jsonDecode(raw);
      if (data is List) {
        return data
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
      }
      if (data is Map && data['messages'] is List) {
        return (data['messages'] as List)
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveMemory(List<Map<String, dynamic>> messages) async {
    try {
      final f = await _file(_memoryFileName);
      await f.writeAsString(
        const JsonEncoder.withIndent('  ').convert(messages),
      );
    } catch (_) {}
  }

  static Future<String> memoryFilePath() async =>
      (await _file(_memoryFileName)).path;

  static Future<void> clearMemory() async {
    try {
      final f = await _file(_memoryFileName);
      if (await f.exists()) await f.writeAsString('[]');
    } catch (_) {}
  }

  // ----------------------------------------------------------------
  // MAPA MENTAL
  // ----------------------------------------------------------------
  static const String _mapFileName = 'mapa_mental.json';

  static Future<Map<String, dynamic>?> loadMindMap() async {
    try {
      final f = await _file(_mapFileName);
      if (!await f.exists()) return null;
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) return null;
      final data = jsonDecode(raw);
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return data.cast<String, dynamic>();
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveMindMap(Map<String, dynamic> data) async {
    try {
      final f = await _file(_mapFileName);
      await f.writeAsString(
        const JsonEncoder.withIndent('  ').convert(data),
      );
    } catch (_) {}
  }

  static Future<String> mindMapFilePath() async =>
      (await _file(_mapFileName)).path;

  // ----------------------------------------------------------------
  // TAREFAS (TO-DO)
  // ----------------------------------------------------------------
  static const String _todosFileName = 'tarefas.json';

  /// Lê as tarefas salvas. Cada item: {title: '...', done: bool}
  static Future<List<Map<String, dynamic>>> loadTodos() async {
    try {
      final f = await _file(_todosFileName);
      if (!await f.exists()) return [];
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) return [];
      final data = jsonDecode(raw);
      if (data is List) {
        return data
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveTodos(List<Map<String, dynamic>> todos) async {
    try {
      final f = await _file(_todosFileName);
      await f.writeAsString(
        const JsonEncoder.withIndent('  ').convert(todos),
      );
    } catch (_) {}
  }

  static Future<String> todosFilePath() async =>
      (await _file(_todosFileName)).path;
}
