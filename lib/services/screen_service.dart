import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

/// Captura screenshots da tela do Windows usando PowerShell + .NET System.Drawing.
///
/// Retorna os bytes PNG da imagem capturada, prontos pra enviar ao Gemini Vision.
/// Redimensiona pra 1280x720 pra economizar cota da API.
class ScreenService {
  static String? _tempDir;

  static Future<String> _getTempDir() async {
    if (_tempDir != null) return _tempDir!;
    final dir = await getTemporaryDirectory();
    _tempDir = dir.path;
    return _tempDir!;
  }

  /// Captura a tela inteira e retorna bytes PNG (redimensionado pra 1280x720).
  static Future<Uint8List?> captureFullScreen() async {
    if (!Platform.isWindows) return null;
    final tmp = await _getTempDir();
    final path = '$tmp\\hub_screenshot.png';

    // PowerShell script que captura a tela e redimensiona
    final script = '''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
\$screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
\$bmp = New-Object System.Drawing.Bitmap(\$screen.Width, \$screen.Height)
\$g = [System.Drawing.Graphics]::FromImage(\$bmp)
\$g.CopyFromScreen(\$screen.Location, [System.Drawing.Point]::Empty, \$screen.Size)
\$g.Dispose()

# Redimensiona pra 854x480 pra economizar tokens
\$resized = New-Object System.Drawing.Bitmap(854, 480)
\$gr = [System.Drawing.Graphics]::FromImage(\$resized)
\$gr.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
\$gr.DrawImage(\$bmp, 0, 0, 854, 480)
\$gr.Dispose()
\$bmp.Dispose()

\$resized.Save("$path", [System.Drawing.Imaging.ImageFormat]::Png)
\$resized.Dispose()
Write-Output "OK"
''';

    final scriptFile = File('$tmp\\hub_screenshot.ps1');
    await scriptFile.writeAsString(script);

    try {
      final result = await Process.run(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', scriptFile.path],
      );
      if (result.stdout.toString().trim().contains('OK')) {
        final file = File(path);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          return bytes;
        }
      } else {
        print('ScreenService error out: ${result.stderr} / ${result.stdout}');
      }
      return null;
    } catch (e) {
      print('ScreenService error: $e');
      return null;
    }
  }

  /// Captura uma região específica da tela.
  static Future<Uint8List?> captureRegion(int x, int y, int w, int h) async {
    if (!Platform.isWindows) return null;
    final tmp = await _getTempDir();
    final path = '$tmp\\hub_region.png';

    final script = '''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
\$bmp = New-Object System.Drawing.Bitmap($w, $h)
\$g = [System.Drawing.Graphics]::FromImage(\$bmp)
\$g.CopyFromScreen($x, $y, 0, 0, (New-Object System.Drawing.Size($w, $h)))
\$g.Dispose()
\$bmp.Save("$path", [System.Drawing.Imaging.ImageFormat]::Png)
\$bmp.Dispose()
Write-Output "OK"
''';

    final scriptFile = File('$tmp\\hub_region.ps1');
    await scriptFile.writeAsString(script);

    try {
      final result = await Process.run(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', scriptFile.path],
      );
      if (result.stdout.toString().trim().contains('OK')) {
        final file = File(path);
        if (await file.exists()) return await file.readAsBytes();
      } else {
        print('ScreenService region error out: ${result.stderr} / ${result.stdout}');
      }
      return null;
    } catch (e) {
      print('ScreenService region error: $e');
      return null;
    }
  }

  /// Retorna a resolução da tela principal.
  static Future<(int, int)?> getScreenResolution() async {
    if (!Platform.isWindows) return null;
    try {
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile', '-NonInteractive', '-Command',
          r'Add-Type -AssemblyName System.Windows.Forms; $s = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds; "$($s.Width)x$($s.Height)"'
        ],
        runInShell: true,
      );
      final parts = result.stdout.toString().trim().split('x');
      if (parts.length == 2) {
        return (int.parse(parts[0]), int.parse(parts[1]));
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
