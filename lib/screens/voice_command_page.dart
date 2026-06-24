import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import '../services/hub_files.dart';
import '../services/screen_service.dart';
import '../services/gui_automation.dart';
import '../services/ui_finder.dart';
import '../services/web_gemini_service.dart';

enum MsgKind { user, ai, action }

class ChatMessage {
  final String text;
  final MsgKind kind;
  final DateTime time;
  ChatMessage(this.text, this.kind) : time = DateTime.now();
  ChatMessage.at(this.text, this.kind, this.time);
}

class VoiceCommandPage extends StatefulWidget {
  const VoiceCommandPage({super.key});

  @override
  State<VoiceCommandPage> createState() => _VoiceCommandPageState();
}

class _VoiceCommandPageState extends State<VoiceCommandPage> {
  // ---- voz ----
  final SpeechToText _speechToText = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();
  bool _speechEnabled = false;

  // ---- chaves / modelo / config ----
  List<String> _apiKeys = [];
  int _activeKeyIndex = 0;
  String _model = 'gemini-2.5-flash-lite';
  bool _freeMode = false; // se true, executa ações sem pedir confirmação
  bool _isSosMode = false; // se true, usa automação do Gemini Web ao invés da API
  bool _muted = false; // se true, não fala em voz alta (TTS)
  String _cwd = ''; // diretório de trabalho atual (pra comandos/arquivos de dev)

  // flash-lite é o mais RÁPIDO e tem cota grátis. O 2.0-flash fica por último:
  // ele anda com a cota grátis ZERADA em conta nova (limit: 0) -> dá 429 na hora.
  static const List<String> _availableModels = [
    'gemini-2.5-flash-lite',
    'gemini-2.5-flash',
    'gemini-flash-latest',
    'gemini-2.0-flash',
  ];

  // ---- estado ----
  final List<ChatMessage> _messages = [];
  bool _isProcessing = false;
  bool _showSettings = false;
  String _listeningStatus = "Pressione o botÃ£o para falar";
  DateTime _lastMessageTime =
      DateTime.now().subtract(const Duration(seconds: 10));
  String _memoryPath = '';
  String _hubFolder = '';
  Uint8List? _pendingScreenshot;

  // ---- gemini ----
  GenerativeModel? _genModel;
  ChatSession? _chatSession;

  // ---- controllers ----
  final TextEditingController _chatController = TextEditingController();
  final TextEditingController _newKeyController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _chatController.dispose();
    _newKeyController.dispose();
    _scrollController.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  Future<void> _init() async {
    await _loadPrefs();

    // carrega memÃ³ria do arquivo no PC
    final mem = await HubFiles.loadMemory();
    for (final m in mem) {
      final role = (m['role'] ?? 'model').toString();
      final txt = (m['text'] ?? '').toString();
      if (txt.trim().isEmpty) continue;
      DateTime t = DateTime.now();
      try {
        if (m['ts'] != null) t = DateTime.parse(m['ts'].toString());
      } catch (_) {}
      _messages.add(ChatMessage.at(
          txt, role == 'user' ? MsgKind.user : MsgKind.ai, t));
    }

    _memoryPath = await HubFiles.memoryFilePath();
    _hubFolder = await HubFiles.hubFolderPath();

    await _initSpeech();
    await _initTts();

    if (_apiKeys.isNotEmpty) {
      _chatSession = _buildSession();
      if (_messages.isEmpty) {
        _addAi("Sistemas online, memÃ³ria zerada. ComeÃ§ando do zero. Manda ver, chefe.");
      } else {
        _addAction("ðŸ§  MemÃ³ria carregada: ${_messages.length} mensagens lembradas.");
      }
    }
    if (mounted) setState(() {});
  }

  // ================================================================
  // PREFERÃŠNCIAS
  // ================================================================
  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    _apiKeys = p.getStringList('hub_api_keys') ?? [];
    _activeKeyIndex = p.getInt('hub_active_key') ?? 0;
    _model = p.getString('hub_model') ?? 'gemini-2.5-flash-lite';
    _freeMode = p.getBool('hub_free_mode') ?? false;
    _muted = p.getBool('hub_muted') ?? false;
    _cwd = p.getString('hub_cwd') ??
        (Platform.environment['USERPROFILE'] ?? Directory.current.path);
    // 2.0-flash tem cota grátis zerada em conta nova -> migra pra um que funciona
    if (_model == 'gemini-2.0-flash') _model = 'gemini-2.5-flash-lite';
    if (!_availableModels.contains(_model)) _model = 'gemini-2.5-flash-lite';
    if (_apiKeys.isEmpty) {
      _activeKeyIndex = 0;
    } else if (_activeKeyIndex >= _apiKeys.length) {
      _activeKeyIndex = 0;
    }
  }

  Future<void> _savePrefs() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList('hub_api_keys', _apiKeys);
    await p.setInt('hub_active_key', _activeKeyIndex);
    await p.setString('hub_model', _model);
    await p.setBool('hub_free_mode', _freeMode);
    await p.setBool('hub_muted', _muted);
    await p.setString('hub_cwd', _cwd);
  }

  // ================================================================
  // VOZ
  // ================================================================
  Future<void> _initSpeech() async {
    try {
      _speechEnabled = await _speechToText.initialize();
    } catch (_) {
      _speechEnabled = false;
    }
  }

  Future<void> _initTts() async {
    try {
      await _flutterTts.setLanguage("pt-BR");
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setPitch(1.0);
    } catch (_) {}
  }

  void _speak(String text) async {
    if (_muted || text.trim().isEmpty) return;
    try {
      await _flutterTts.speak(text);
    } catch (_) {}
  }

  Future<void> _toggleMute() async {
    setState(() => _muted = !_muted);
    if (_muted) {
      try {
        await _flutterTts.stop();
      } catch (_) {}
    }
    await _savePrefs();
    _snack(_muted ? "🔇 Voz mutada" : "🔊 Voz ativada");
  }

  void _startListening() async {
    if (_apiKeys.isEmpty) {
      _snack("Adicione uma chave da API primeiro!");
      return;
    }
    await _flutterTts.stop();
    setState(() => _listeningStatus = "Ouvindo...");
    await _speechToText.listen(onResult: _onSpeechResult, localeId: 'pt_BR');
  }

  void _stopListening() async {
    await _speechToText.stop();
    if (_listeningStatus != "Ouvindo..." &&
        _listeningStatus != "Processando..." &&
        _listeningStatus != "Pensando..." &&
        _listeningStatus != "Pressione o botÃ£o para falar" &&
        _listeningStatus.isNotEmpty) {
      _processUserMessage(_listeningStatus);
    } else {
      setState(() => _listeningStatus = "Processando...");
      Future.delayed(const Duration(seconds: 2), () {
        if (!_isProcessing && mounted) {
          setState(() => _listeningStatus = "Pressione o botÃ£o para falar");
        }
      });
    }
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    setState(() => _listeningStatus = result.recognizedWords);
    if (result.finalResult) {
      _processUserMessage(result.recognizedWords);
    }
  }

  // ================================================================
  // SESSÃO GEMINI + HISTÓRICO
  // ================================================================
  String get _systemPrompt =>
      'CONTEXTO ATUAL (Windows):\n'
      'Pasta de trabalho: $_cwd\n'
      'Comandos [RUN] rodam NESSA pasta; caminhos relativos em [LIST]/[READ]/[WRITE] resolvem a partir dela. Troque com [CD:pasta].\n\n'
      r'''Você é a IA pessoal do Hub, uma IA de DESENVOLVIMENTO rodando dentro do PC (Windows) do usuário.
Personalidade: sincera, direta, debochada e sem papo motivacional furado. Fala a real, sem rodeio, mas é útil de verdade.

Você TEM memória: o histórico das conversas anteriores foi carregado, então use o que já sabe sobre o usuário em vez de perguntar tudo de novo.

Você pode AGIR no PC do usuário. Quando (e somente quando) precisar fazer algo no computador, inclua UMA linha de ação com o formato EXATO abaixo. Pode escrever uma frase curta antes, mas a ação tem que ficar numa linha própria:

=== AÇÕES DE ARQUIVO/SISTEMA ===
[OPEN:alvo]                 -> abre um programa ou site. Ex: [OPEN:notepad]  [OPEN:calc]  [OPEN:https://github.com]
[LIST:caminho]              -> lista os arquivos de uma pasta. Ex: [LIST:C:\Users]
[READ:caminho]              -> lê o conteúdo de um arquivo de texto. Ex: [READ:C:\Users\eu\nota.txt]
[WRITE:caminho|||conteudo]  -> cria ou sobrescreve um arquivo de texto (o conteúdo vem depois de |||).
[RUN:comando]               -> roda um comando no cmd, NA pasta de trabalho atual. Ex: [RUN:git status]  [RUN:flutter analyze]  [RUN:npm test]
[CD:caminho]                -> troca a pasta de trabalho. Aceita caminho relativo. Ex: [CD:C:\Users\dougl\projeto]  [CD:..]

=== AÇÕES DE VISÃO (você pode VER a tela!) ===
[SCREENSHOT]                -> tira uma foto da tela inteira. A imagem volta pra você como input visual — analise e descreva o que vê.
[SCREENSHOT:x,y,w,h]       -> tira foto de uma região específica.

=== AÇÕES DE GUI (você pode CONTROLAR a interface!) ===
[CLICK:x,y]                 -> clique esquerdo na posição. Ex: [CLICK:500,300]
[DBLCLICK:x,y]              -> duplo clique.
[RCLICK:x,y]                -> clique direito.
[TYPE:texto]                -> digita texto no campo ativo. Ex: [TYPE:minha mensagem]
[KEY:tecla]                 -> pressiona uma tecla especial. Ex: [KEY:enter] [KEY:tab] [KEY:escape]
[HOTKEY:combo]              -> atalho de teclado. Ex: [HOTKEY:ctrl+c] [HOTKEY:alt+f4] [HOTKEY:ctrl+s]
[SCROLL:x,y,n]             -> scroll do mouse. n>0 pra cima, n<0 pra baixo. Ex: [SCROLL:500,300,-3]
[FIND:nome]                 -> busca elementos de UI pelo nome/texto (retorna coordenadas). Ex: [FIND:Próximo]
[FOCUS:janela]              -> traz uma janela pro foco/frente. Ex: [FOCUS:Google Chrome]
[WINDOWS]                   -> lista todas as janelas abertas.
[WAIT:segundos]             -> espera N segundos (máx 10). Útil após OPEN pra tela carregar.

=== FLUXO DE AUTOMAÇÃO GUI ===
Para tarefas visuais complexas, siga SEMPRE este ciclo:
1. ABRA o programa/site com [OPEN]
2. ESPERE com [WAIT:2]
3. OLHE com [SCREENSHOT] — analise a imagem recebida
4. ENCONTRE com [FIND:nome] se souber o texto do botão/campo
5. AJA com [CLICK], [TYPE], [KEY], etc.
6. VERIFIQUE com [SCREENSHOT] de novo pra confirmar que funcionou

=== MODO DESENVOLVEDOR (você programa de verdade) ===
Você desenvolve software de ponta a ponta no PC do usuário. Em tarefas de código:
- ANTES de editar, use [READ] pra ver o conteúdo atual. NUNCA sobrescreva às cegas.
- Use [LIST] pra explorar o projeto e [CD] pra entrar na pasta dele.
- Escreva arquivos COMPLETOS e corretos com [WRITE] (o arquivo inteiro, nunca trechos com "...").
- VERIFIQUE rodando: [RUN:flutter analyze], [RUN:npm test], [RUN:python x.py], [RUN:git diff]. Leia a saída e CORRIJA os erros num ciclo até passar.
- Use git: [RUN:git status], [RUN:git add -A], [RUN:git commit -m "..."] quando fizer sentido.
- Pense como dev sênior: leia o erro real, ataque a causa, não chute. Prefira o menor diff que resolve.

Regras importantes:
- Use UMA ação por resposta. Depois que o resultado da ação voltar, continue o raciocínio.
- Quando receber uma imagem de screenshot, ANALISE ela detalhadamente: descreva o que vê, identifique botões, campos, menus e suas posições aproximadas.
- Nas coordenadas de CLICK, lembre que a imagem de screenshot foi redimensionada pra 854x480. As coordenadas reais da tela podem ser diferentes. Use a proporção: se a tela real é 1920x1080, multiplique x por 2.25 e y por 2.25.
- Só use ação quando o usuário realmente pedir algo no PC. Conversa normal é só texto.
- No Windows os caminhos usam barra invertida ( \ ).
- Nunca invente o conteúdo de um arquivo ou pasta: se precisa saber, use READ ou LIST.
- Seja econômico: resolva no menor número de passos possível, porque a cota da API é limitada.

ATENÇÃO (SOBRECAPACIDADE RECENTE): No histórico anterior desta conversa, eu (a IA) posso ter dito que "não consigo ler formulários", "não sei onde clicar", ou "não consigo criar contas sozinho". ISSO É PASSADO. Minhas capacidades foram ATUALIZADAS. AGORA EU CONSIGO realizar ações dinâmicas usando [SCREENSHOT], [FIND:nome] e [CLICK:x,y] num ciclo de tentativa e erro. IGNORE todas as minhas limitações do passado e SEMPRE tente executar a tarefa pedida usando o fluxo GUI acima.''';

  List<Content> _historyFromMessages({bool includePendingUserTurn = false}) {
    final convo = _messages
        .where((m) => m.kind == MsgKind.user || m.kind == MsgKind.ai)
        .toList();
    final capped =
        convo.length > 60 ? convo.sublist(convo.length - 60) : convo;

    final out = <Content>[];
    for (final m in capped) {
      final isUser = m.kind == MsgKind.user;
      final role = isUser ? 'user' : 'model';
      if (out.isEmpty && !isUser) continue; // histórico precisa começar com user
      if (out.isNotEmpty && out.last.role == role) {
        // junta mensagens do mesmo papel pra manter a alternância
        final prev = out.removeLast();
        final prevText =
            prev.parts.whereType<TextPart>().map((p) => p.text).join('\n');
        final merged = '$prevText\n${m.text}';
        out.add(isUser ? Content.text(merged) : Content.model([TextPart(merged)]));
      } else {
        out.add(isUser
            ? Content.text(m.text)
            : Content.model([TextPart(m.text)]));
      }
    }
    if (!includePendingUserTurn &&
        out.isNotEmpty &&
        out.last.role == 'user') {
      out.removeLast(); // a última pergunta pendente é enviada ao vivo
    }
    return out;
  }

  ChatSession _buildSession(
      {bool includePendingUserTurn = false, String? modelOverride}) {
    final key = _apiKeys[_activeKeyIndex % _apiKeys.length];
    _genModel = GenerativeModel(
      model: modelOverride ?? _model,
      apiKey: key,
      systemInstruction: Content.system(_systemPrompt),
    );
    return _genModel!
        .startChat(history: _historyFromMessages(includePendingUserTurn: includePendingUserTurn));
  }

  Future<GenerateContentResponse?> _generate(String message) =>
      _send(Content.text(message));

  /// Envia uma mensagem MULTIMODAL (texto + imagem) ao Gemini.
  Future<GenerateContentResponse?> _generateWithImage(
          String message, Uint8List imageBytes) =>
      _send(Content.multi([
        TextPart(message),
        DataPart('image/png', imageBytes),
      ]));

  /// Núcleo do envio ao Gemini, com recuperação automática em camadas:
  ///  1) servidor sobrecarregado (503): tenta de novo, depois troca de modelo;
  ///  2) cota do modelo esgotada (inclui o limit:0 do 2.0-flash): troca de MODELO;
  ///  3) problema da chave (inválida/sem permissão): troca de CONTA.
  /// Só estoura erro (e aí o modo SOS pode entrar) quando TUDO foi tentado.
  Future<GenerateContentResponse?> _send(Content content) async {
    final total = _apiKeys.length;
    int rotations = 0;
    int serverRetries = 0;
    const maxServerRetries = 2;

    final fallbackModels = <String>[
      _model,
      ..._availableModels.where((m) => m != _model),
    ];
    int modelIdx = 0;
    String currentModel = fallbackModels[modelIdx];

    while (true) {
      try {
        _chatSession ??= _buildSession(modelOverride: currentModel);
        return await _chatSession!.sendMessage(content);
      } catch (e) {
        final s = e.toString().toLowerCase();
        _chatSession = null; // recria a sessão na próxima tentativa

        // 1) servidor sobrecarregado (transitório)
        final serverBusy = s.contains('503') ||
            s.contains('500') ||
            s.contains('overloaded') ||
            s.contains('unavailable') ||
            s.contains('high demand') ||
            s.contains('try again later') ||
            s.contains('internal error');
        if (serverBusy) {
          if (serverRetries < maxServerRetries) {
            serverRetries++;
            _addAction(
                "⏳ $currentModel sobrecarregado. Tentando de novo ($serverRetries/$maxServerRetries)...");
            await Future.delayed(Duration(milliseconds: 900 * serverRetries));
            continue;
          }
          if (modelIdx < fallbackModels.length - 1) {
            modelIdx++;
            currentModel = fallbackModels[modelIdx];
            serverRetries = 0;
            _addAction("🔀 Servidor lotado. Trocando pro modelo $currentModel...");
            continue;
          }
          rethrow;
        }

        // 2) cota do modelo esgotada (inclui limit:0) -> outro modelo tem cota
        final quota = s.contains('quota') ||
            s.contains('429') ||
            s.contains('resource_exhausted') ||
            s.contains('limit: 0') ||
            s.contains('limit:0');
        if (quota && modelIdx < fallbackModels.length - 1) {
          modelIdx++;
          currentModel = fallbackModels[modelIdx];
          _addAction(
              "🔀 Cota do modelo esgotada. Tentando o modelo $currentModel...");
          continue;
        }

        // 3) problema da chave -> troca de conta e recomeça pelo modelo preferido
        final keyProblem = quota ||
            s.contains('leaked') ||
            s.contains('api_key_invalid') ||
            s.contains('permission_denied') ||
            s.contains('401') ||
            s.contains('403');
        rotations++;
        if (keyProblem && total > 1 && rotations < total) {
          _activeKeyIndex = (_activeKeyIndex + 1) % total;
          await _savePrefs();
          _addAction(
              "🔁 Conta anterior falhou. Tentando a conta ${_activeKeyIndex + 1}/$total...");
          modelIdx = 0;
          currentModel = fallbackModels[0];
          serverRetries = 0;
          continue;
        }
        rethrow;
      }
    }
  }

  // ================================================================
  // LOOP PRINCIPAL (com ações no PC)
  // ================================================================
  Future<void> _processUserMessage(String text) async {
    if (_isProcessing) return;
    text = text.trim();
    if (text.isEmpty) return;
    if (_apiKeys.isEmpty) {
      _snack("Adicione uma chave da API primeiro.");
      return;
    }
    final now = DateTime.now();
    if (now.difference(_lastMessageTime).inSeconds < 4) {
      _snack("Calma aí chefe, espera uns segundos...");
      return;
    }
    _lastMessageTime = now;

    // Cada mensagem nova recomeça tentando a API normal. O modo SOS (web) só
    // entra se TODOS os modelos/chaves falharem nesta mensagem — não fica preso.
    _isSosMode = false;

    await _flutterTts.stop();
    _addUser(text);
    setState(() {
      _isProcessing = true;
      _listeningStatus = "Pensando...";
    });

    try {
      String toSend = text;
      for (int step = 0; step < 10; step++) {
        String aiText = '';

        if (_isSosMode) {
          setState(() { _listeningStatus = "Modo SOS (Web)..."; });
          if (_pendingScreenshot != null) {
            _pendingScreenshot = null;
            toSend += "\n\n[AVISO DO SISTEMA: Modo SOS Web ativado. A cota da API acabou e eu perdi a Visão. Não consigo processar as imagens de screenshot. Analise o que puder do texto e aja às cegas.]";
          }
          final hist = _messages.length > 20 ? _messages.sublist(_messages.length - 20) : _messages;
          final histText = hist.map((m) => "${m.kind.name.toUpperCase()}: ${m.text}").join("\n");
          final formattedPrompt = "$_systemPrompt\n\nHISTORICO RECENTE:\n$histText\n\nNOVA MENSAGEM (Humano ou Sistema): $toSend\n\nResponda diretamente com a ação final na última linha, sem muitas explicações.";
          
          try {
            aiText = await WebGeminiService.askWebGemini(formattedPrompt);
          } catch (e) {
            aiText = "Erro fatal no modo SOS: \$e";
          }
        } else {
          try {
            GenerateContentResponse? resp;
            if (_pendingScreenshot != null) {
              final imgBytes = _pendingScreenshot!;
              _pendingScreenshot = null;
              resp = await _generateWithImage(toSend, imgBytes);
            } else {
              resp = await _generate(toSend);
            }
            aiText = (resp?.text ?? '').trim();
          } catch (e) {
            final msg = e.toString().toLowerCase();
            if (msg.contains('quota') || msg.contains('429') || msg.contains('exhausted')) {
               _isSosMode = true;
               _snack("Cota esgotada! Ativando Modo SOS (Web)...");
               _addAction("⚠️ Cota da API esgotada. Tentando modo SOS Web Fallback...");
               step--; // repete o passo usando o SOS
               continue;
            } else {
               rethrow;
            }
          }
        }

        if (aiText.isEmpty) {
          _addAi("...(a IA não respondeu nada dessa vez)");
          break;
        }

        final action = _parseAction(aiText);
        if (action == null) {
          _addAi(aiText);
          _speak(aiText);
          break;
        }

        if (action.preface.isNotEmpty) {
          _addAi(action.preface);
          _speak(action.preface);
        }

        final result = await _executeAction(action);
        _addAction(result.status);

        if (result.feedback == null && result.imageBytes == null) break;
        if (result.imageBytes != null) {
          _pendingScreenshot = result.imageBytes;
          toSend = result.feedback ?? "SCREENSHOT capturado. Analise a imagem e descreva o que vê na tela.";
        } else {
          toSend = "RESULTADO DA AÇÃO (${action.type} ${action.arg}):\n${result.feedback}";
        }
      }
    } catch (e) {
      final msg = _errorMessage(e);
      _addAi(msg);
      _speak("Deu ruim na conexão, chefe.");
    } finally {
      setState(() {
        _isProcessing = false;
        _listeningStatus = "Pressione o botão para falar";
      });
    }
  }

  String _errorMessage(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('limit: 0') || s.contains('limit:0')) {
      return "Esse modelo está com a cota grátis ZERADA nessas contas. Abre o ⚙️ e usa o gemini-2.5-flash-lite ou gemini-2.5-flash (esses funcionam).";
    }
    if (s.contains('503') ||
        s.contains('overloaded') ||
        s.contains('unavailable') ||
        s.contains('high demand')) {
      return "O servidor do Google tá sobrecarregado agora (503), não é a sua chave. Já tentei trocar de modelo sozinho. Manda de novo daqui a pouco.";
    }
    if (s.contains('quota') ||
        s.contains('429') ||
        s.contains('resource_exhausted')) {
      return "Cota das suas chaves esgotou em todos os modelos, chefe. Adiciona outra chave (de outra conta Google) nas configurações ⚙️ ou espera o limite resetar.";
    }
    if (s.contains('leaked')) {
      return "O Google bloqueou essa chave porque ela vazou (apareceu em algum lugar público). Gera uma nova no AI Studio e adiciona aqui.";
    }
    if (s.contains('api_key_invalid') ||
        s.contains('401') ||
        s.contains('403') ||
        s.contains('permission')) {
      return "Essa chave tá inválida ou sem permissão. Confere no Google AI Studio e adiciona uma nova nas configurações.";
    }
    return "Deu ruim na conexão: ${e.toString().split('\n').first}";
  }

  // ================================================================
  // PARSE + EXECUÇÃO DAS AÇÕES
  // ================================================================
  _AiAction? _parseAction(String text) {
    final upper = text.toUpperCase();

    // Ações sem argumento (tag exata)
    for (final noarg in ['SCREENSHOT', 'WINDOWS']) {
      final i = upper.indexOf('[$noarg]');
      if (i >= 0) {
        return _AiAction(noarg, '', null, text.substring(0, i).trim());
      }
    }

    // Ações com argumento [TAG:arg]
    const types = [
      'OPEN', 'LIST', 'READ', 'WRITE', 'RUN', 'CD',
      'SCREENSHOT', 'CLICK', 'DBLCLICK', 'RCLICK',
      'TYPE', 'KEY', 'HOTKEY', 'SCROLL',
      'FIND', 'FOCUS', 'WAIT',
    ];
    int bestStart = -1;
    String bestType = '';
    for (final t in types) {
      final i = upper.indexOf('[$t:');
      if (i >= 0 && (bestStart == -1 || i < bestStart)) {
        bestStart = i;
        bestType = t;
      }
    }
    if (bestStart == -1) return null;

    final preface = text.substring(0, bestStart).trim();
    final afterTag = text.substring(bestStart + bestType.length + 2);
    String payload;
    if (bestType == 'WRITE') {
      final end = afterTag.lastIndexOf(']');
      payload = end >= 0 ? afterTag.substring(0, end) : afterTag;
    } else {
      final end = afterTag.indexOf(']');
      payload = end >= 0 ? afterTag.substring(0, end) : afterTag;
    }

    String arg = payload.trim();
    String? content;
    if (bestType == 'WRITE') {
      final idx = payload.indexOf('|||');
      if (idx >= 0) {
        arg = payload.substring(0, idx).trim();
        content = payload.substring(idx + 3);
      } else {
        content = '';
      }
    }
    return _AiAction(bestType, arg, content, preface);
  }

  Future<({String status, String? feedback, Uint8List? imageBytes})> _executeAction(
      _AiAction a) async {
    try {
      switch (a.type) {
        case 'OPEN':
          await _openTarget(a.arg);
          return (status: "🚀 Abrindo: ${a.arg}", feedback: "Ação OPEN executada com sucesso.", imageBytes: null);

        case 'CD':
          {
            final target = _resolvePath(a.arg);
            final dir = Directory(target);
            if (!await dir.exists()) {
              return (
                status: "📁 Pasta não existe: $target",
                feedback:
                    "A pasta \"$target\" não existe. A pasta de trabalho continua: $_cwd",
                imageBytes: null
              );
            }
            setState(() => _cwd = dir.absolute.path);
            await _savePrefs();
            return (
              status: "📂 Pasta de trabalho: $_cwd",
              feedback: "Ok. A pasta de trabalho agora é: $_cwd",
              imageBytes: null
            );
          }

        case 'LIST':
          {
            final path = _resolvePath(a.arg);
            final dir = Directory(path);
            if (!await dir.exists()) {
              return (
                status: "📁 Pasta não encontrada: $path",
                feedback: "A pasta \"$path\" não existe.",
                imageBytes: null
              );
            }
            final items = <String>[];
            await for (final e in dir.list()) {
              final name = e.path.split(Platform.pathSeparator).last;
              items.add((e is Directory ? "[pasta] " : "[arq]   ") + name);
              if (items.length >= 200) break;
            }
            final out = items.isEmpty ? "(pasta vazia)" : items.join('\n');
            return (
              status: "📁 Listei ${items.length} item(ns) em $path",
              feedback: out,
              imageBytes: null
            );
          }

        case 'READ':
          {
            final f = File(_resolvePath(a.arg));
            if (!await f.exists()) {
              return (
                status: "📄 Arquivo não encontrado: ${a.arg}",
                feedback: "O arquivo \"${a.arg}\" não existe.",
                imageBytes: null
              );
            }
            var content = await f.readAsString();
            if (content.length > 8000) {
              content = "${content.substring(0, 8000)}\n...[cortado, arquivo grande]";
            }
            return (
              status: "📄 Li o arquivo: ${a.arg}",
              feedback: content.isEmpty ? "(arquivo vazio)" : content,
              imageBytes: null
            );
          }

        case 'WRITE':
          {
            final path = _resolvePath(a.arg);
            if (!_freeMode) {
              final ok = await _confirm("Escrever arquivo",
                  "A IA quer criar/sobrescrever:\n\n$path\n\n(${(a.content ?? '').length} caracteres)");
              if (!ok) {
                return (status: "🚫 Escrita bloqueada por você", feedback: null, imageBytes: null);
              }
            }
            final f = File(path);
            await f.create(recursive: true);
            await f.writeAsString(a.content ?? '');
            return (status: "💾 Salvei o arquivo: $path", feedback: "Ação WRITE concluída. Arquivo salvo em $path.", imageBytes: null);
          }

        case 'RUN':
          {
            if (!_freeMode) {
              final ok = await _confirm("Rodar comando no terminal",
                  "A IA quer rodar no cmd:\n\n${a.arg}");
              if (!ok) {
                return (status: "🚫 Comando bloqueado por você", feedback: null, imageBytes: null);
              }
            }
            final res = await Process.run('cmd', ['/c', a.arg],
                runInShell: true,
                workingDirectory:
                    Directory(_cwd).existsSync() ? _cwd : null);
            var out = (res.stdout?.toString() ?? '') +
                (res.stderr?.toString() ?? '');
            if (out.length > 8000) {
              out = "${out.substring(0, 8000)}\n...[cortado]";
            }
            return (
              status: "⚙️ Rodei (em $_cwd): ${a.arg}",
              feedback: out.trim().isEmpty
                  ? "(sem saída, código de saída ${res.exitCode})"
                  : out,
              imageBytes: null
            );
          }

        // ============ AÇÕES DE VISÃO ============
        case 'SCREENSHOT':
          {
            Uint8List? bytes;
            if (a.arg.isNotEmpty && a.arg.contains(',')) {
              final parts = a.arg.split(',').map((s) => int.tryParse(s.trim()) ?? 0).toList();
              if (parts.length == 4) {
                bytes = await ScreenService.captureRegion(parts[0], parts[1], parts[2], parts[3]);
              }
            } else {
              bytes = await ScreenService.captureFullScreen();
            }
            if (bytes == null) {
              return (
                status: "📷 Falha ao capturar tela",
                feedback: "Não foi possível capturar a tela.",
                imageBytes: null
              );
            }
            final res = await ScreenService.getScreenResolution();
            final resInfo = res != null ? "Resolução real: ${res.$1}x${res.$2}. Imagem redimensionada pra 854x480. Fator: x=${(res.$1 / 854.0).toStringAsFixed(2)} y=${(res.$2 / 480.0).toStringAsFixed(2)}" : "";
            return (
              status: "📷 Screenshot capturado (${(bytes.length / 1024).toStringAsFixed(0)}KB)",
              feedback: "SCREENSHOT capturado. $resInfo\nAnalise a imagem e descreva o que vê: janelas, botões, campos, textos. Identifique posições dos elementos.",
              imageBytes: bytes
            );
          }

        // ============ AÇÕES DE GUI ============
        case 'CLICK':
          {
            final coords = _parseCoords(a.arg);
            if (coords == null) return (status: "❌ Coordenadas inválidas: ${a.arg}", feedback: "Use formato: [CLICK:x,y]", imageBytes: null);
            if (!_freeMode) {
              final ok = await _confirm("Clicar na tela", "A IA quer clicar em (${coords.$1}, ${coords.$2})");
              if (!ok) return (status: "🚫 Clique bloqueado", feedback: "Ação CLICK bloqueada pelo usuário.", imageBytes: null);
            }
            await GuiAutomation.click(coords.$1, coords.$2);
            return (status: "🖱️ Cliquei em (${coords.$1}, ${coords.$2})", feedback: "Ação CLICK executada.", imageBytes: null);
          }

        case 'DBLCLICK':
          {
            final coords = _parseCoords(a.arg);
            if (coords == null) return (status: "❌ Coordenadas inválidas", feedback: "Coordenadas inválidas", imageBytes: null);
            if (!_freeMode) {
              final ok = await _confirm("Duplo clique", "Em (${coords.$1}, ${coords.$2})");
              if (!ok) return (status: "🚫 Clique bloqueado", feedback: "Ação DBLCLICK bloqueada.", imageBytes: null);
            }
            await GuiAutomation.doubleClick(coords.$1, coords.$2);
            return (status: "🖱️ Duplo clique em (${coords.$1}, ${coords.$2})", feedback: "Ação DBLCLICK executada.", imageBytes: null);
          }

        case 'RCLICK':
          {
            final coords = _parseCoords(a.arg);
            if (coords == null) return (status: "❌ Coordenadas inválidas", feedback: "Coordenadas inválidas", imageBytes: null);
            if (!_freeMode) {
              final ok = await _confirm("Clique direito", "Em (${coords.$1}, ${coords.$2})");
              if (!ok) return (status: "🚫 Clique bloqueado", feedback: "Ação RCLICK bloqueada.", imageBytes: null);
            }
            await GuiAutomation.rightClick(coords.$1, coords.$2);
            return (status: "🖱️ Clique direito em (${coords.$1}, ${coords.$2})", feedback: "Ação RCLICK executada.", imageBytes: null);
          }

        case 'TYPE':
          {
            if (!_freeMode) {
              final ok = await _confirm("Digitar texto", "A IA quer digitar:\n\n${a.arg}");
              if (!ok) return (status: "🚫 Digitação bloqueada", feedback: "Ação TYPE bloqueada.", imageBytes: null);
            }
            await GuiAutomation.typeText(a.arg);
            return (status: "⌨️ Digitei: ${a.arg.length > 40 ? '${a.arg.substring(0, 40)}...' : a.arg}", feedback: "Ação TYPE executada.", imageBytes: null);
          }

        case 'KEY':
          {
            await GuiAutomation.pressKey(a.arg);
            return (status: "⌨️ Tecla: ${a.arg}", feedback: "Ação KEY executada.", imageBytes: null);
          }

        case 'HOTKEY':
          {
            if (!_freeMode) {
              final ok = await _confirm("Atalho de teclado", "A IA quer pressionar: ${a.arg}");
              if (!ok) return (status: "🚫 Atalho bloqueado", feedback: "Ação HOTKEY bloqueada.", imageBytes: null);
            }
            await GuiAutomation.hotkey(a.arg);
            return (status: "⌨️ Atalho: ${a.arg}", feedback: "Ação HOTKEY executada.", imageBytes: null);
          }

        case 'SCROLL':
          {
            final parts = a.arg.split(',').map((s) => int.tryParse(s.trim()) ?? 0).toList();
            if (parts.length < 3) return (status: "❌ Formato: [SCROLL:x,y,amount]", feedback: "Formato SCROLL inválido.", imageBytes: null);
            await GuiAutomation.scroll(parts[0], parts[1], parts[2]);
            return (status: "🖱️ Scroll em (${parts[0]}, ${parts[1]}) amount=${parts[2]}", feedback: "Ação SCROLL executada.", imageBytes: null);
          }

        case 'FIND':
          {
            final elements = await UiFinder.findByName(a.arg);
            if (elements.isEmpty) {
              return (
                status: "🔍 Nenhum elemento encontrado: ${a.arg}",
                feedback: "Nenhum elemento de UI com o nome \"${a.arg}\" foi encontrado.",
                imageBytes: null
              );
            }
            final desc = elements.map((e) =>
              "• \"${e['name']}\" (${e['type']}) centro=(${e['centerX']}, ${e['centerY']}) tamanho=${e['width']}x${e['height']}"
            ).join('\n');
            return (
              status: "🔍 Encontrei ${elements.length} elemento(s) para \"${a.arg}\"",
              feedback: "Elementos encontrados:\n$desc\n\nUse [CLICK:centerX,centerY] pra clicar em um deles.",
              imageBytes: null
            );
          }

        case 'FOCUS':
          {
            await GuiAutomation.focusWindow(a.arg);
            return (status: "🪟 Focando janela: ${a.arg}", feedback: "Ação FOCUS executada.", imageBytes: null);
          }

        case 'WINDOWS':
          {
            final list = await GuiAutomation.listWindows();
            if (list.trim().isEmpty) {
              return (status: "🪟 Nenhuma janela aberta", feedback: "Nenhuma janela visível encontrada.", imageBytes: null);
            }
            final formatted = list.split('\n').map((line) {
              final parts = line.split('|');
              if (parts.length >= 3) return "• [PID ${parts[0]}] ${parts[1]} — \"${parts[2]}\"";
              return "• $line";
            }).join('\n');
            return (
              status: "🪟 Listei ${list.split('\n').length} janela(s)",
              feedback: "Janelas abertas:\n$formatted\n\nUse [FOCUS:título] pra trazer uma janela pra frente.",
              imageBytes: null
            );
          }

        case 'WAIT':
          {
            final secs = int.tryParse(a.arg) ?? 2;
            final clamped = secs.clamp(1, 10);
            await Future.delayed(Duration(seconds: clamped));
            return (status: "⏳ Esperei ${clamped}s", feedback: "Ação WAIT concluída. Pode continuar.", imageBytes: null);
          }
      }
    } catch (e) {
      return (status: "❌ Erro na ação: $e", feedback: "Erro ao executar: $e", imageBytes: null);
    }
    return (status: "Ação desconhecida", feedback: "Ação não reconhecida.", imageBytes: null);
  }

  /// Resolve um caminho relativo contra a pasta de trabalho atual (_cwd).
  String _resolvePath(String input) {
    final raw = input.trim();
    if (raw.isEmpty) return _cwd;
    final abs = p.isAbsolute(raw) ? raw : p.join(_cwd, raw);
    return p.normalize(abs);
  }

  (int, int)? _parseCoords(String s) {
    final parts = s.split(',');
    if (parts.length < 2) return null;
    final x = int.tryParse(parts[0].trim());
    final y = int.tryParse(parts[1].trim());
    if (x == null || y == null) return null;
    return (x, y);
  }

  Future<void> _openTarget(String target) async {
    final t = target.toLowerCase().trim();
    if (t == 'notepad' || t == 'bloco de notas') {
      await Process.run('notepad.exe', []);
    } else if (t == 'calc' || t == 'calculadora') {
      await Process.run('calc.exe', []);
    } else if (t == 'youtube') {
      await Process.run('cmd', ['/c', 'start', '', 'https://youtube.com'],
          runInShell: true);
    } else if (t.startsWith('http://') ||
        t.startsWith('https://') ||
        t.contains('.com') ||
        t.contains('.net') ||
        t.contains('.org')) {
      var url = target.trim();
      if (!url.startsWith('http')) url = 'https://$url';
      await Process.run('cmd', ['/c', 'start', '', url], runInShell: true);
    } else {
      await Process.run('cmd', ['/c', 'start', '', target], runInShell: true);
    }
  }

  Future<bool> _confirm(String title, String body) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(title),
        content: SingleChildScrollView(child: Text(body)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text("Negar",
                  style: TextStyle(color: Colors.white54))),
          ElevatedButton(
              onPressed: () => Navigator.pop(c, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurpleAccent),
              child: const Text("Permitir")),
        ],
      ),
    );
    return r ?? false;
  }

  // ================================================================
  // MENSAGENS / MEMÃ“RIA
  // ================================================================
  void _addUser(String t) {
    setState(() => _messages.add(ChatMessage(t, MsgKind.user)));
    _persistMemory();
    _scrollToBottom();
  }

  void _addAi(String t) {
    setState(() => _messages.add(ChatMessage(t, MsgKind.ai)));
    _persistMemory();
    _scrollToBottom();
  }

  void _addAction(String t) {
    if (!mounted) return;
    setState(() => _messages.add(ChatMessage(t, MsgKind.action)));
    _scrollToBottom();
  }

  Future<void> _persistMemory() async {
    final data = _messages
        .where((m) => m.kind == MsgKind.user || m.kind == MsgKind.ai)
        .map((m) => {
              'role': m.kind == MsgKind.user ? 'user' : 'model',
              'text': m.text,
              'ts': m.time.toIso8601String(),
            })
        .toList();
    await HubFiles.saveMemory(data);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  // ================================================================
  // UI
  // ================================================================
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
      child: _showSettings
          ? _buildSettings()
          : (_apiKeys.isEmpty ? _buildApiKeySetup() : _buildChatInterface()),
    );
  }

  // ---- setup inicial (primeira chave) ----
  Widget _buildApiKeySetup() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.psychology,
                size: 90, color: Colors.deepPurpleAccent),
            const SizedBox(height: 16),
            const Text("Ativar Hub AI",
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            const Text(
              "Cole sua prÃ³pria chave gratuita do Google Gemini. Ela fica salva sÃ³ no seu PC. VocÃª pode adicionar vÃ¡rias chaves depois â€” quando uma esgota a cota, eu troco pra prÃ³xima automaticamente.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.white54),
            ),
            const SizedBox(height: 28),
            TextField(
              controller: _newKeyController,
              obscureText: true,
              decoration: InputDecoration(
                hintText: "Cole sua API Key aqui...",
                filled: true,
                fillColor: Colors.white10,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: () async {
                final k = _newKeyController.text.trim();
                if (k.isEmpty) return;
                _newKeyController.clear();
                setState(() {
                  _apiKeys.add(k);
                  _activeKeyIndex = 0;
                });
                await _savePrefs();
                _chatSession = _buildSession();
                if (_messages.isEmpty) {
                  _addAi("Sistemas online. TÃ´ te ouvindo, chefe.");
                  _speak("Sistemas online. TÃ´ te ouvindo, chefe.");
                }
                setState(() {});
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurpleAccent,
                padding:
                    const EdgeInsets.symmetric(horizontal: 36, vertical: 18),
              ),
              child: const Text("CONECTAR CÃ‰REBRO",
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 18),
            TextButton.icon(
              onPressed: () async {
                await _openTarget('https://aistudio.google.com/app/apikey');
              },
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text("Pegar uma chave grÃ¡tis no Google AI Studio"),
            ),
          ],
        ),
      ),
    );
  }

  // ---- chat ----
  Widget _buildChatInterface() {
    return Column(
      children: [
        Row(
          children: [
            const Text("IA do Hub",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(width: 12),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                "$_model Â· chave ${_activeKeyIndex + 1}/${_apiKeys.length}${_freeMode ? ' Â· modo livre' : ''}",
                style:
                    const TextStyle(fontSize: 12, color: Colors.white54),
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: _muted ? "Ativar voz" : "Mutar voz",
              icon: Icon(_muted ? Icons.volume_off : Icons.volume_up,
                  color: _muted ? Colors.redAccent : Colors.white54),
              onPressed: _toggleMute,
            ),
            IconButton(
              tooltip: "Configurações",
              icon: const Icon(Icons.settings, color: Colors.white54),
              onPressed: () => setState(() => _showSettings = true),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            itemCount: _messages.length,
            itemBuilder: (context, index) => _buildBubble(_messages[index]),
          ),
        ),
        if (_isProcessing)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(color: Colors.deepPurpleAccent),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 6),
          child: Text(_listeningStatus,
              style: const TextStyle(
                  color: Colors.white54, fontStyle: FontStyle.italic)),
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _chatController,
                decoration: InputDecoration(
                  hintText: "Digite algo ou use o microfone...",
                  filled: true,
                  fillColor: Colors.white10,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.send,
                        color: Colors.deepPurpleAccent),
                    onPressed: () {
                      final v = _chatController.text.trim();
                      if (v.isNotEmpty) {
                        _processUserMessage(v);
                        _chatController.clear();
                      }
                    },
                  ),
                ),
                onSubmitted: (val) {
                  if (val.trim().isNotEmpty) {
                    _processUserMessage(val.trim());
                    _chatController.clear();
                  }
                },
              ),
            ),
            const SizedBox(width: 14),
            GestureDetector(
              onTapDown: (_) => _startListening(),
              onTapUp: (_) => _stopListening(),
              onTapCancel: () => _stopListening(),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: _speechToText.isListening ? 64 : 56,
                height: _speechToText.isListening ? 64 : 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _speechToText.isListening
                      ? Colors.redAccent
                      : Colors.deepPurpleAccent,
                  boxShadow: [
                    if (_speechToText.isListening)
                      BoxShadow(
                          color: Colors.redAccent.withOpacity(0.5),
                          blurRadius: 20,
                          spreadRadius: 8),
                  ],
                ),
                child: Icon(
                    _speechToText.isListening ? Icons.mic : Icons.mic_none,
                    size: 28,
                    color: Colors.white),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBubble(ChatMessage msg) {
    if (msg.kind == MsgKind.action) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.7),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.35),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.tealAccent.withOpacity(0.25)),
          ),
          child: Text(
            msg.text,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.tealAccent,
                fontSize: 12.5,
                fontFamily: 'monospace'),
          ),
        ),
      );
    }
    final isUser = msg.kind == MsgKind.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(14),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.6),
        decoration: BoxDecoration(
          color: isUser ? Colors.deepPurpleAccent : Colors.white10,
          borderRadius: BorderRadius.circular(16),
        ),
        child: SelectableText(msg.text,
            style: const TextStyle(fontSize: 15.5)),
      ),
    );
  }

  // ---- configuraÃ§Ãµes ----
  Widget _buildSettings() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white70),
                onPressed: () => setState(() => _showSettings = false),
              ),
              const Text("ConfiguraÃ§Ãµes da IA",
                  style:
                      TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),

          // ---- modelo ----
          const Text("Modelo do Gemini",
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(
              "2.0 Flash = mais cota grÃ¡tis (recomendado). 2.5 = mais inteligente, menos cota.",
              style: TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(12)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _model,
                isExpanded: true,
                dropdownColor: const Color(0xFF1A1A1A),
                items: _availableModels
                    .map((m) =>
                        DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: (v) async {
                  if (v == null) return;
                  setState(() {
                    _model = v;
                    _chatSession = null; // reconstrÃ³i na prÃ³xima mensagem
                  });
                  await _savePrefs();
                  _snack("Modelo trocado pra $v");
                },
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ---- chaves ----
          Row(
            children: [
              const Text("Chaves da API",
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Text("(${_apiKeys.length})",
                  style: const TextStyle(color: Colors.white38)),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
              "Adicione chaves de contas diferentes. Quando uma esgota, a IA pula pra prÃ³xima sozinha.",
              style: TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 10),
          ..._apiKeys.asMap().entries.map((entry) {
            final i = entry.key;
            final k = entry.value;
            final active = i == _activeKeyIndex;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: active
                    ? Colors.deepPurpleAccent.withOpacity(0.18)
                    : Colors.white10,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: active
                        ? Colors.deepPurpleAccent
                        : Colors.transparent),
              ),
              child: Row(
                children: [
                  Icon(active ? Icons.bolt : Icons.vpn_key,
                      size: 18,
                      color: active
                          ? Colors.deepPurpleAccent
                          : Colors.white38),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text("Conta ${i + 1}:  ${_maskKey(k)}",
                          style: const TextStyle(fontSize: 13))),
                  if (!active)
                    TextButton(
                      onPressed: () async {
                        setState(() => _activeKeyIndex = i);
                        _chatSession = null;
                        await _savePrefs();
                      },
                      child: const Text("Usar",
                          style: TextStyle(fontSize: 12)),
                    ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        size: 18, color: Colors.redAccent),
                    onPressed: () async {
                      setState(() {
                        _apiKeys.removeAt(i);
                        if (_activeKeyIndex >= _apiKeys.length) {
                          _activeKeyIndex = 0;
                        }
                        _chatSession = null;
                      });
                      await _savePrefs();
                    },
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newKeyController,
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: "Colar nova API Key...",
                    filled: true,
                    fillColor: Colors.white10,
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: () async {
                  final k = _newKeyController.text.trim();
                  if (k.isEmpty) return;
                  _newKeyController.clear();
                  setState(() {
                    _apiKeys.add(k);
                    if (_apiKeys.length == 1) _activeKeyIndex = 0;
                  });
                  await _savePrefs();
                  _chatSession ??= _buildSession();
                  _snack("Chave adicionada (${_apiKeys.length} no total)");
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurpleAccent),
                child: const Text("Adicionar"),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ---- modo livre ----
          Material(
            color: Colors.transparent,
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeColor: Colors.deepPurpleAccent,
              title: const Text("Modo livre (executar sem confirmar)"),
              subtitle: const Text(
                  "Se ligado, a IA escreve arquivos e roda comandos no PC sem pedir permissão. Cuidado.",
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              value: _freeMode,
              onChanged: (v) async {
                setState(() => _freeMode = v);
                await _savePrefs();
              },
            ),
          ),
          const Divider(color: Colors.white12, height: 32),

          // ---- memÃ³ria ----
          const Text("MemÃ³ria",
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text("Arquivo: $_memoryPath",
              style: const TextStyle(color: Colors.white38, fontSize: 12)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  if (_hubFolder.isNotEmpty) {
                    await Process.run('explorer.exe', [_hubFolder]);
                  }
                },
                icon: const Icon(Icons.folder_open, size: 16),
                label: const Text("Abrir pasta da memÃ³ria"),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final ok = await _confirm("Limpar memÃ³ria",
                      "Isso apaga TODA a conversa lembrada. NÃ£o dÃ¡ pra desfazer. Continuar?");
                  if (!ok) return;
                  await HubFiles.clearMemory();
                  setState(() {
                    _messages.clear();
                    _chatSession = null;
                  });
                  _snack("MemÃ³ria apagada.");
                },
                style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent),
                icon: const Icon(Icons.delete_forever, size: 16),
                label: const Text("Limpar memÃ³ria"),
              ),
            ],
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  String _maskKey(String k) {
    if (k.length <= 10) return "â€¢â€¢â€¢â€¢â€¢â€¢";
    return "${k.substring(0, 6)}â€¢â€¢â€¢â€¢${k.substring(k.length - 4)}";
  }
}


class _AiAction {
  final String type;
  final String arg;
  final String? content;
  final String preface;
  _AiAction(this.type, this.arg, this.content, this.preface);
}
