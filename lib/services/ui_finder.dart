import 'dart:convert';
import 'dart:io';

/// Busca elementos de UI na interface do Windows usando a API de UI Automation.
///
/// Permite encontrar botões, campos de texto, menus, etc. pela acessibilidade
/// e retorna nome, tipo e coordenadas (bounding rectangle) de cada elemento.
class UiFinder {
  /// Encontra elementos de UI pelo nome/texto (busca parcial, case-insensitive).
  /// Retorna lista de maps com: name, type, x, y, width, height, centerX, centerY.
  static Future<List<Map<String, dynamic>>> findByName(String name) async {
    if (!Platform.isWindows) return [];

    final script = '''
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

\$root = [System.Windows.Automation.AutomationElement]::RootElement
\$cond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::IsEnabledProperty, \$true
)

\$all = \$root.FindAll([System.Windows.Automation.TreeScope]::Descendants, \$cond)
\$results = @()
\$count = 0

foreach (\$el in \$all) {
    if (\$count -ge 20) { break }
    try {
        \$n = \$el.Current.Name
        if (\$n -and \$n -like "*${name.replaceAll('"', '`"')}*") {
            \$rect = \$el.Current.BoundingRectangle
            if (\$rect.Width -gt 0 -and \$rect.Height -gt 0) {
                \$results += [pscustomobject]@{
                    name = \$n
                    type = \$el.Current.ControlType.ProgrammaticName
                    x = [int]\$rect.X
                    y = [int]\$rect.Y
                    width = [int]\$rect.Width
                    height = [int]\$rect.Height
                    centerX = [int](\$rect.X + \$rect.Width / 2)
                    centerY = [int](\$rect.Y + \$rect.Height / 2)
                }
                \$count++
            }
        }
    } catch {}
}

\$results | ConvertTo-Json -Compress
''';

    try {
      final result = await Process.run(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-Command', script],
        runInShell: true,
      );
      final out = result.stdout.toString().trim();
      if (out.isEmpty || out == 'null') return [];

      final decoded = jsonDecode(out);
      if (decoded is List) {
        return decoded.cast<Map<String, dynamic>>();
      } else if (decoded is Map) {
        return [decoded.cast<String, dynamic>()];
      }
      return [];
    } catch (e) {
      print('UiFinder error: $e');
      return [];
    }
  }

  /// Encontra elementos por tipo de controle (Button, Edit, ComboBox, etc.)
  static Future<List<Map<String, dynamic>>> findByType(String controlType) async {
    if (!Platform.isWindows) return [];

    final script = '''
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

\$root = [System.Windows.Automation.AutomationElement]::RootElement

# Tenta usar o ControlType nativo
\$typeName = "ControlType.$controlType"
try {
    \$ctrlType = [System.Windows.Automation.ControlType]::\$controlType
} catch {
    Write-Output "[]"
    exit
}

\$cond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty, \$ctrlType
)

\$elements = \$root.FindAll([System.Windows.Automation.TreeScope]::Descendants, \$cond)
\$results = @()
\$count = 0

foreach (\$el in \$elements) {
    if (\$count -ge 20) { break }
    try {
        \$rect = \$el.Current.BoundingRectangle
        if (\$rect.Width -gt 0 -and \$rect.Height -gt 0) {
            \$results += [pscustomobject]@{
                name = \$el.Current.Name
                type = \$el.Current.ControlType.ProgrammaticName
                x = [int]\$rect.X
                y = [int]\$rect.Y
                width = [int]\$rect.Width
                height = [int]\$rect.Height
                centerX = [int](\$rect.X + \$rect.Width / 2)
                centerY = [int](\$rect.Y + \$rect.Height / 2)
            }
            \$count++
        }
    } catch {}
}

\$results | ConvertTo-Json -Compress
''';

    try {
      final result = await Process.run(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-Command', script],
        runInShell: true,
      );
      final out = result.stdout.toString().trim();
      if (out.isEmpty || out == 'null') return [];

      final decoded = jsonDecode(out);
      if (decoded is List) {
        return decoded.cast<Map<String, dynamic>>();
      } else if (decoded is Map) {
        return [decoded.cast<String, dynamic>()];
      }
      return [];
    } catch (e) {
      print('UiFinder findByType error: $e');
      return [];
    }
  }

  /// Retorna info sobre a janela no foreground (ativa).
  static Future<Map<String, dynamic>?> getForegroundWindow() async {
    if (!Platform.isWindows) return null;

    try {
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile', '-NonInteractive', '-Command',
          r'''
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class FgWin {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
$h = [FgWin]::GetForegroundWindow()
$sb = New-Object System.Text.StringBuilder(256)
[FgWin]::GetWindowText($h, $sb, 256) | Out-Null
$r = New-Object FgWin+RECT
[FgWin]::GetWindowRect($h, [ref]$r) | Out-Null
[pscustomobject]@{title=$sb.ToString(); x=$r.Left; y=$r.Top; width=$r.Right-$r.Left; height=$r.Bottom-$r.Top} | ConvertTo-Json -Compress
''',
        ],
        runInShell: true,
      );
      final out = result.stdout.toString().trim();
      if (out.isEmpty) return null;
      return Map<String, dynamic>.from(jsonDecode(out));
    } catch (e) {
      print('UiFinder getForegroundWindow error: $e');
      return null;
    }
  }
}
