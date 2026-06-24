import 'package:flutter/material.dart';
import 'dart:async';
import '../services/system_monitor.dart';

class MonitorPage extends StatefulWidget {
  const MonitorPage({super.key});

  @override
  State<MonitorPage> createState() => _MonitorPageState();
}

class _MonitorPageState extends State<MonitorPage> {
  final SystemMonitor _monitor = SystemMonitor();
  SystemSnapshot? _snap;
  bool _sampling = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh(); // primeira leitura imediata
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_sampling) return; // evita leituras sobrepostas
    _sampling = true;
    try {
      final s = await _monitor.sample();
      if (mounted) setState(() => _snap = s);
    } finally {
      _sampling = false;
    }
  }

  String _formatRate(double kbs) {
    if (kbs >= 1024) return "${(kbs / 1024).toStringAsFixed(1)} MB/s";
    return "${kbs.toStringAsFixed(0)} KB/s";
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snap;
    final failed = snap != null && !snap.ok;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 40.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Monitoramento",
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            failed
                ? "Não foi possível ler o sistema"
                : "Dados reais do seu PC (atualiza a cada 2s)",
            style: TextStyle(
              fontSize: 16,
              color: failed ? Colors.redAccent : Colors.white54,
            ),
          ),
          const SizedBox(height: 40),
          if (snap == null)
            const Expanded(
              child: Center(
                child: CircularProgressIndicator(
                    color: Colors.deepPurpleAccent),
              ),
            )
          else if (failed)
            Expanded(child: _buildError(snap.error ?? "Erro desconhecido"))
          else
            Expanded(child: _buildGrid(snap)),
        ],
      ),
    );
  }

  Widget _buildError(String error) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
          const SizedBox(height: 16),
          const Text("Falha ao ler o sistema",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Text(error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 13)),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text("Tentar de novo"),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(SystemSnapshot snap) {
    final width = MediaQuery.of(context).size.width;
    final cols = width > 800 ? 3 : (width > 500 ? 2 : 1);
    return GridView.count(
      crossAxisCount: cols,
      crossAxisSpacing: 20,
      mainAxisSpacing: 20,
      childAspectRatio: 1.0,
      children: [
        _buildGaugeCard(
          title: "CPU",
          percentage: snap.cpu,
          color: snap.cpu > 0.8 ? Colors.redAccent : Colors.tealAccent,
          icon: Icons.memory,
        ),
        _buildGaugeCard(
          title: "RAM",
          percentage: snap.ram,
          color: snap.ram > 0.85 ? Colors.redAccent : Colors.deepPurpleAccent,
          icon: Icons.storage,
          subtitle:
              "${_gb(snap.ramUsedMb)} / ${_gb(snap.ramTotalMb)} GB",
        ),
        _buildNetworkCard(snap),
      ],
    );
  }

  String _gb(int mb) => (mb / 1024).toStringAsFixed(1);

  Widget _buildGaugeCard({
    required String title,
    required double percentage,
    required Color color,
    required IconData icon,
    String? subtitle,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white54, size: 32),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white70)),
          const SizedBox(height: 24),
          SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              fit: StackFit.expand,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: percentage),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOut,
                  builder: (context, value, _) => CircularProgressIndicator(
                    value: value,
                    strokeWidth: 12,
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
                Center(
                  child: Text(
                    "${(percentage * 100).toInt()}%",
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                )
              ],
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 16),
            Text(subtitle,
                style: const TextStyle(fontSize: 13, color: Colors.white54)),
          ],
        ],
      ),
    );
  }

  Widget _buildNetworkCard(SystemSnapshot snap) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi, color: Colors.blueAccent, size: 40),
          const SizedBox(height: 16),
          const Text("Rede",
              style: TextStyle(fontSize: 18, color: Colors.white54)),
          const SizedBox(height: 20),
          _netRow(Icons.south, Colors.tealAccent, "Download",
              _formatRate(snap.netDownKbs)),
          const SizedBox(height: 12),
          _netRow(Icons.north, Colors.deepPurpleAccent, "Upload",
              _formatRate(snap.netUpKbs)),
        ],
      ),
    );
  }

  Widget _netRow(IconData icon, Color color, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Text(value,
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontSize: 13, color: color)),
      ],
    );
  }
}
