import 'dart:io';

/// Automação de GUI do Windows: mouse, teclado, janelas.
///
/// Usa PowerShell com .NET pra simular input de forma confiável,
/// sem depender de FFI complexo que pode quebrar entre versões do win32.
class GuiAutomation {
  /// Move o cursor do mouse pra posição absoluta (x, y) na tela.
  static Future<bool> moveMouse(int x, int y) async {
    return _runPs('''
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
''');
  }

  /// Clique esquerdo na posição (x, y).
  static Future<bool> click(int x, int y) async {
    return _runPs('''
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class MouseInput {
    [DllImport("user32.dll")] public static extern void mouse_event(int dwFlags, int dx, int dy, int dwData, int dwExtraInfo);
    public const int LEFTDOWN = 0x02;
    public const int LEFTUP = 0x04;
}
"@
Start-Sleep -Milliseconds 50
[MouseInput]::mouse_event([MouseInput]::LEFTDOWN, 0, 0, 0, 0)
Start-Sleep -Milliseconds 30
[MouseInput]::mouse_event([MouseInput]::LEFTUP, 0, 0, 0, 0)
''');
  }

  /// Duplo clique na posição (x, y).
  static Future<bool> doubleClick(int x, int y) async {
    return _runPs('''
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class MouseInput2 {
    [DllImport("user32.dll")] public static extern void mouse_event(int dwFlags, int dx, int dy, int dwData, int dwExtraInfo);
    public const int LEFTDOWN = 0x02;
    public const int LEFTUP = 0x04;
}
"@
Start-Sleep -Milliseconds 50
[MouseInput2]::mouse_event([MouseInput2]::LEFTDOWN, 0, 0, 0, 0)
Start-Sleep -Milliseconds 30
[MouseInput2]::mouse_event([MouseInput2]::LEFTUP, 0, 0, 0, 0)
Start-Sleep -Milliseconds 80
[MouseInput2]::mouse_event([MouseInput2]::LEFTDOWN, 0, 0, 0, 0)
Start-Sleep -Milliseconds 30
[MouseInput2]::mouse_event([MouseInput2]::LEFTUP, 0, 0, 0, 0)
''');
  }

  /// Clique direito na posição (x, y).
  static Future<bool> rightClick(int x, int y) async {
    return _runPs('''
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class MouseInputR {
    [DllImport("user32.dll")] public static extern void mouse_event(int dwFlags, int dx, int dy, int dwData, int dwExtraInfo);
    public const int RIGHTDOWN = 0x08;
    public const int RIGHTUP = 0x10;
}
"@
Start-Sleep -Milliseconds 50
[MouseInputR]::mouse_event([MouseInputR]::RIGHTDOWN, 0, 0, 0, 0)
Start-Sleep -Milliseconds 30
[MouseInputR]::mouse_event([MouseInputR]::RIGHTUP, 0, 0, 0, 0)
''');
  }

  /// Digita texto no campo ativo usando SendKeys.
  static Future<bool> typeText(String text) async {
    // Escapa caracteres especiais do SendKeys
    final escaped = text
        .replaceAll('{', '{{')
        .replaceAll('}', '}}')
        .replaceAll('+', '{+}')
        .replaceAll('^', '{^}')
        .replaceAll('%', '{%}')
        .replaceAll('~', '{~}')
        .replaceAll('(', '{(}')
        .replaceAll(')', '{)}');
    return _runPs('''
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.SendKeys]::SendWait("$escaped")
''');
  }

  /// Pressiona uma tecla especial (enter, tab, escape, backspace, delete, etc.)
  static Future<bool> pressKey(String key) async {
    final mapped = _mapKey(key.toLowerCase().trim());
    return _runPs('''
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.SendKeys]::SendWait("$mapped")
''');
  }

  /// Executa um atalho de teclado (ctrl+c, alt+f4, ctrl+shift+s, etc.)
  static Future<bool> hotkey(String combo) async {
    final keys = combo.toLowerCase().split('+').map((s) => s.trim()).toList();
    String sendKeys = '';
    String suffix = '';
    
    for (final k in keys) {
      switch (k) {
        case 'ctrl':
        case 'control':
          sendKeys += '^';
          break;
        case 'alt':
          sendKeys += '%';
          break;
        case 'shift':
          sendKeys += '+';
          break;
        case 'win':
        case 'windows':
          // SendKeys não suporta Win key, usar método alternativo
          return _runWinHotkey(keys);
        default:
          suffix = _mapKey(k);
      }
    }
    
    sendKeys += suffix;
    return _runPs('''
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.SendKeys]::SendWait("$sendKeys")
''');
  }

  /// Scroll do mouse na posição (x, y). amount positivo = pra cima, negativo = pra baixo.
  static Future<bool> scroll(int x, int y, int amount) async {
    final wheelDelta = amount * 120; // 120 = um "notch" do scroll
    return _runPs('''
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class MouseScroll {
    [DllImport("user32.dll")] public static extern void mouse_event(int dwFlags, int dx, int dy, int dwData, int dwExtraInfo);
    public const int WHEEL = 0x0800;
}
"@
Start-Sleep -Milliseconds 50
[MouseScroll]::mouse_event([MouseScroll]::WHEEL, 0, 0, $wheelDelta, 0)
''');
  }

  /// Foca (traz pra frente) uma janela pelo título.
  static Future<bool> focusWindow(String title) async {
    return _runPs('''
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinFocus {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
\$proc = Get-Process | Where-Object { \$_.MainWindowTitle -like "*${title.replaceAll('"', '`"')}*" } | Select-Object -First 1
if (\$proc) {
    [WinFocus]::ShowWindow(\$proc.MainWindowHandle, 9)
    [WinFocus]::SetForegroundWindow(\$proc.MainWindowHandle)
    Write-Output "OK"
} else {
    Write-Output "NOTFOUND"
}
''');
  }

  /// Lista todas as janelas visíveis com título.
  static Future<String> listWindows() async {
    try {
      final script = '''
Get-Process | Where-Object {\$_.MainWindowTitle -ne ""} | Select-Object ProcessName, MainWindowTitle, Id | ForEach-Object { \$_.Id.ToString() + "|" + \$_.ProcessName + "|" + \$_.MainWindowTitle }
''';
      final result = await Process.run(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-Command', script],
        runInShell: true,
      );
      return result.stdout.toString().trim();
    } catch (e) {
      return 'Erro ao listar janelas: \$e';
    }
  }

  // ---- helpers ----

  static Future<bool> _runPs(String script) async {
    if (!Platform.isWindows) return false;
    try {
      final result = await Process.run(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-Command', script],
        runInShell: true,
      );
      return result.exitCode == 0;
    } catch (e) {
      print('GuiAutomation error: $e');
      return false;
    }
  }

  static Future<bool> _runWinHotkey(List<String> keys) async {
    // Para Win key, usa keybd_event via PowerShell
    final otherKeys = keys.where((k) => k != 'win' && k != 'windows').toList();
    final vk = otherKeys.isNotEmpty ? _vkCode(otherKeys.last) : '';
    if (vk.isEmpty) return false;
    
    return _runPs('''
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinKey {
    [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, int dwFlags, int dwExtraInfo);
    public const int KEYUP = 0x0002;
}
"@
[WinKey]::keybd_event(0x5B, 0, 0, 0)
Start-Sleep -Milliseconds 50
[WinKey]::keybd_event($vk, 0, 0, 0)
Start-Sleep -Milliseconds 50
[WinKey]::keybd_event($vk, 0, [WinKey]::KEYUP, 0)
[WinKey]::keybd_event(0x5B, 0, [WinKey]::KEYUP, 0)
''');
  }

  static String _mapKey(String key) {
    switch (key) {
      case 'enter': case 'return': return '{ENTER}';
      case 'tab': return '{TAB}';
      case 'esc': case 'escape': return '{ESC}';
      case 'backspace': case 'bs': return '{BACKSPACE}';
      case 'delete': case 'del': return '{DELETE}';
      case 'space': case ' ': return ' ';
      case 'up': return '{UP}';
      case 'down': return '{DOWN}';
      case 'left': return '{LEFT}';
      case 'right': return '{RIGHT}';
      case 'home': return '{HOME}';
      case 'end': return '{END}';
      case 'pageup': case 'pgup': return '{PGUP}';
      case 'pagedown': case 'pgdn': return '{PGDN}';
      case 'f1': return '{F1}';
      case 'f2': return '{F2}';
      case 'f3': return '{F3}';
      case 'f4': return '{F4}';
      case 'f5': return '{F5}';
      case 'f6': return '{F6}';
      case 'f7': return '{F7}';
      case 'f8': return '{F8}';
      case 'f9': return '{F9}';
      case 'f10': return '{F10}';
      case 'f11': return '{F11}';
      case 'f12': return '{F12}';
      case 'printscreen': case 'prtsc': return '{PRTSC}';
      case 'insert': case 'ins': return '{INSERT}';
      default:
        if (key.length == 1) return key;
        return '{$key}';
    }
  }

  static String _vkCode(String key) {
    switch (key.toLowerCase()) {
      case 'r': return '0x52';
      case 'd': return '0x44';
      case 'e': return '0x45';
      case 'l': return '0x4C';
      case 's': return '0x53';
      case 'i': return '0x49';
      case 'tab': return '0x09';
      default: return '0x${key.codeUnitAt(0).toRadixString(16).toUpperCase()}';
    }
  }
}
