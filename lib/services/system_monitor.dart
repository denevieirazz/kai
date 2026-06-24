import 'dart:convert';
import 'dart:io';

/// Uma leitura instantânea do sistema.
class SystemSnapshot {
  final double cpu; // 0..1
  final double ram; // 0..1
  final int ramUsedMb;
  final int ramTotalMb;
  final double netDownKbs; // KB/s (download)
  final double netUpKbs; // KB/s (upload)
  final bool ok; // false se não deu pra ler (ex.: não-Windows ou erro)
  final String? error;

  const SystemSnapshot({
    required this.cpu,
    required this.ram,
    required this.ramUsedMb,
    required this.ramTotalMb,
    required this.netDownKbs,
    required this.netUpKbs,
    required this.ok,
    this.error,
  });

  factory SystemSnapshot.unavailable(String error) => SystemSnapshot(
        cpu: 0,
        ram: 0,
        ramUsedMb: 0,
        ramTotalMb: 0,
        netDownKbs: 0,
        netUpKbs: 0,
        ok: false,
        error: error,
      );
}

/// Lê CPU, RAM e rede reais do Windows via PowerShell.
///
/// Usa classes CIM (Win32_OperatingSystem / Win32_Processor) e
/// Get-NetAdapterStatistics — nada de contadores de performance, que têm
/// nomes traduzidos e quebram em Windows não-inglês.
///
/// A taxa de rede (KB/s) é calculada pela diferença dos bytes acumulados
/// entre duas leituras, dividida pelo tempo decorrido.
class SystemMonitor {
  int? _lastRx;
  int? _lastTx;
  DateTime? _lastTime;

  static const String _script =
      r'$os = Get-CimInstance Win32_OperatingSystem;'
      r'$cpu = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average;'
      r'$rx = (Get-NetAdapterStatistics | Measure-Object -Property ReceivedBytes -Sum).Sum;'
      r'$tx = (Get-NetAdapterStatistics | Measure-Object -Property SentBytes -Sum).Sum;'
      r'[pscustomobject]@{ cpu = $cpu; ramTotalKb = $os.TotalVisibleMemorySize; ramFreeKb = $os.FreePhysicalMemory; rxBytes = $rx; txBytes = $tx } | ConvertTo-Json -Compress';

  Future<SystemSnapshot> sample() async {
    if (!Platform.isWindows) {
      return SystemSnapshot.unavailable('Monitor real só roda no Windows.');
    }
    try {
      final res = await Process.run(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-Command', _script],
        runInShell: true,
      );
      final out = (res.stdout?.toString() ?? '').trim();
      if (out.isEmpty) {
        return SystemSnapshot.unavailable(
            (res.stderr?.toString() ?? 'Sem saída do PowerShell.').trim());
      }
      final data = jsonDecode(out) as Map<String, dynamic>;

      final cpu = ((data['cpu'] as num?)?.toDouble() ?? 0).clamp(0.0, 100.0);
      final totalKb = (data['ramTotalKb'] as num?)?.toDouble() ?? 0;
      final freeKb = (data['ramFreeKb'] as num?)?.toDouble() ?? 0;
      final usedKb = (totalKb - freeKb).clamp(0.0, totalKb);
      final ram = totalKb > 0 ? (usedKb / totalKb).clamp(0.0, 1.0) : 0.0;

      final rx = (data['rxBytes'] as num?)?.toInt() ?? 0;
      final tx = (data['txBytes'] as num?)?.toInt() ?? 0;
      final now = DateTime.now();

      double down = 0;
      double up = 0;
      if (_lastRx != null && _lastTx != null && _lastTime != null) {
        final secs = now.difference(_lastTime!).inMilliseconds / 1000.0;
        if (secs > 0) {
          // counters podem resetar (adaptador reconectou) -> ignora negativo
          final dRx = rx - _lastRx!;
          final dTx = tx - _lastTx!;
          if (dRx >= 0) down = dRx / secs / 1024.0;
          if (dTx >= 0) up = dTx / secs / 1024.0;
        }
      }
      _lastRx = rx;
      _lastTx = tx;
      _lastTime = now;

      return SystemSnapshot(
        cpu: cpu / 100.0,
        ram: ram,
        ramUsedMb: (usedKb / 1024).round(),
        ramTotalMb: (totalKb / 1024).round(),
        netDownKbs: down,
        netUpKbs: up,
        ok: true,
      );
    } catch (e) {
      return SystemSnapshot.unavailable(e.toString().split('\n').first);
    }
  }
}
