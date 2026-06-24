import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Modo SOS: usa o Gemini do NAVEGADOR (grátis, sem cota de API) automatizando
/// teclado/mouse via PowerShell. É um plano B — depende de você estar logado no
/// Gemini no navegador padrão. Não é 100% confiável (é "raspagem" de tela), mas
/// com polling adaptativo + foco correto na página ele consegue trazer a resposta
/// na maioria das vezes.
class WebGeminiService {
  static Future<String> askWebGemini(String prompt) async {
    final dir = await getTemporaryDirectory();
    final promptFile = File('${dir.path}\\hub_prompt.txt');
    final resultFile = File('${dir.path}\\hub_result.txt');
    final scriptFile = File('${dir.path}\\hub_sos.ps1');

    if (await resultFile.exists()) {
      await resultFile.delete();
    }
    await promptFile.writeAsString(prompt);

    final script = '''
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class U {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, int e);
}
"@

function Click(\$x, \$y) {
  [U]::SetCursorPos(\$x, \$y)
  Start-Sleep -Milliseconds 200
  [U]::mouse_event(0x0002,0,0,0,0)
  [U]::mouse_event(0x0004,0,0,0,0)
  Start-Sleep -Milliseconds 250
}

# 1) Coloca o prompt no clipboard
[System.Windows.Forms.Clipboard]::SetText( (Get-Content -Raw -Path "${promptFile.path}") )
Start-Sleep -Milliseconds 300

# 2) Acha (e maximiza) uma janela de navegador, ou abre o Gemini
\$proc = Get-Process | Where-Object {
  \$_.MainWindowTitle -like "*Gemini*" -or \$_.MainWindowTitle -like "*Chrome*" -or
  \$_.MainWindowTitle -like "*Edge*"   -or \$_.MainWindowTitle -like "*Firefox*" -or
  \$_.MainWindowTitle -like "*Brave*"
} | Select-Object -First 1

if (\$proc) {
  [U]::ShowWindow(\$proc.MainWindowHandle, 3)   # 3 = maximizar
  [U]::SetForegroundWindow(\$proc.MainWindowHandle)
  Start-Sleep -Seconds 2
} else {
  Start-Process "https://gemini.google.com/app"
  Start-Sleep -Seconds 12
}

\$scr = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
\$w = \$scr.Width
\$h = \$scr.Height

# 3) Clica no campo de input (parte de baixo, ao centro), cola e envia
Click ([int](\$w/2)) ([int](\$h-110))
[System.Windows.Forms.SendKeys]::SendWait("^v")
Start-Sleep -Milliseconds 600
[System.Windows.Forms.SendKeys]::SendWait("{ENTER}")

# 4) Espera a resposta ESTABILIZAR (polling adaptativo, ~até 50s)
\$last = ""
\$stable = 0
\$result = ""
for (\$i = 0; \$i -lt 25; \$i++) {
  Start-Sleep -Seconds 2
  # tira o foco do input clicando na área da conversa, senão Ctrl+A copia vazio
  Click ([int](\$w*0.35)) ([int](\$h*0.4))
  [System.Windows.Forms.SendKeys]::SendWait("^a")
  Start-Sleep -Milliseconds 300
  [System.Windows.Forms.SendKeys]::SendWait("^c")
  Start-Sleep -Milliseconds 300
  \$clip = [System.Windows.Forms.Clipboard]::GetText()
  if (\$clip -and \$clip.Length -gt 0) {
    \$result = \$clip
    if (\$clip.Length -eq \$last.Length) {
      \$stable++
      if (\$stable -ge 2) { break }   # estabilizou -> resposta terminou
    } else {
      \$stable = 0
    }
    \$last = \$clip
  }
}
Set-Content -Path "${resultFile.path}" -Value \$result -Encoding UTF8
''';

    await scriptFile.writeAsString(script);

    await Process.run(
      'powershell',
      ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', scriptFile.path],
    );

    if (!await resultFile.exists()) {
      return "Erro SOS: o PowerShell não gerou resultado. Verifique se o navegador abriu e se você está logado no Gemini.";
    }

    final fullText = await resultFile.readAsString();
    return _extractGeminiResponse(fullText, prompt);
  }

  /// Extrai a última resposta do Gemini do texto copiado da página inteira.
  static String _extractGeminiResponse(String clipboardText, String originalPrompt) {
    if (clipboardText.trim().isEmpty) {
      return "Erro SOS: não consegui capturar o texto da página. Confirme que o Gemini Web abriu, está logado e maximizado.";
    }

    final lines = clipboardText.split(RegExp(r'\r?\n'));

    // âncora: a última linha não-vazia do prompt enviado
    final promptLines =
        originalPrompt.split('\n').where((l) => l.trim().isNotEmpty).toList();
    final lastPromptLine = promptLines.isNotEmpty ? promptLines.last.trim() : "";

    // procura de trás pra frente o eco do prompt (ou a marca "Gemini")
    int startIndex = -1;
    for (int i = lines.length - 1; i >= 0; i--) {
      final line = lines[i].trim();
      if (lastPromptLine.isNotEmpty && line.contains(lastPromptLine)) {
        startIndex = i;
        break;
      }
      if (line.toLowerCase() == "gemini") {
        startIndex = i;
        break;
      }
    }

    if (startIndex == -1) {
      // não achou a âncora: devolve as últimas linhas "úteis" como aproximação
      final tail = lines.reversed
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !_isUiMarker(l))
          .take(40)
          .toList()
          .reversed
          .join('\n')
          .trim();
      if (tail.isEmpty) {
        return "Erro SOS: não encontrei a resposta no texto copiado. A página pode não ter carregado a tempo.";
      }
      return tail;
    }

    final buffer = StringBuffer();
    for (int i = startIndex + 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.toLowerCase() == "gemini") continue;
      if (_isUiMarker(line)) break;
      buffer.writeln(lines[i]);
    }

    final resposta = buffer.toString().trim();
    if (resposta.isEmpty) {
      return "Erro SOS: a resposta capturada veio vazia. Tenta de novo com a janela do Gemini em primeiro plano.";
    }
    return resposta;
  }

  /// Botões/rótulos do rodapé da resposta do Gemini (marca o FIM do texto útil).
  static bool _isUiMarker(String line) {
    final l = line.toLowerCase();
    const markers = [
      'share', 'compartilhar', 'export', 'exportar', 'show drafts',
      'mostrar rascunhos', 'volume', 'good response', 'bad response',
      'resposta boa', 'resposta ruim', 'reply', 'responder',
      'regenerate', 'gerar novamente', 'edit', 'editar',
    ];
    return markers.contains(l);
  }
}
