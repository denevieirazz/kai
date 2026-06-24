import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../services/hub_files.dart';

// ===================================================================
// MODELOS
// ===================================================================
class MapNode {
  final String id;
  String label;
  double x;
  double y;
  double vx = 0;
  double vy = 0;
  bool pinned = false;

  MapNode({required this.id, required this.label, required this.x, required this.y});

  Map<String, dynamic> toJson() => {'id': id, 'label': label, 'x': x, 'y': y};

  factory MapNode.fromJson(Map j) => MapNode(
        id: j['id'].toString(),
        label: (j['label'] ?? '').toString(),
        x: (j['x'] as num?)?.toDouble() ?? 0,
        y: (j['y'] as num?)?.toDouble() ?? 0,
      );
}

class MapEdge {
  final String a;
  final String b;
  MapEdge(this.a, this.b);

  Map<String, dynamic> toJson() => {'a': a, 'b': b};

  factory MapEdge.fromJson(Map j) =>
      MapEdge(j['a'].toString(), j['b'].toString());
}

// ===================================================================
// PÁGINA
// ===================================================================
class MindMapPage extends StatefulWidget {
  const MindMapPage({super.key});

  @override
  State<MindMapPage> createState() => _MindMapPageState();
}

class _MindMapPageState extends State<MindMapPage>
    with SingleTickerProviderStateMixin {
  static const double _canvasSize = 4000.0;

  List<MapNode> _nodes = [];
  List<MapEdge> _edges = [];

  late final Ticker _ticker;
  double _alpha = 1.0; // "temperatura" da simulação

  final TransformationController _tc = TransformationController();
  bool _centered = false;
  Size _lastViewport = const Size(800, 600);

  String? _selectedId;
  String? _hoverId;
  bool _linkMode = false;
  String _search = '';

  Timer? _saveDebounce;
  final Random _rnd = Random();

  // ---------------------------------------------------------------
  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    _ticker.start();
    _load();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _saveDebounce?.cancel();
    HubFiles.saveMindMap({
      'nodes': _nodes.map((n) => n.toJson()).toList(),
      'edges': _edges.map((e) => e.toJson()).toList(),
    });
    _tc.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final data = await HubFiles.loadMindMap();
    if (data != null &&
        data['nodes'] is List &&
        (data['nodes'] as List).isNotEmpty) {
      _nodes =
          (data['nodes'] as List).map((e) => MapNode.fromJson(e)).toList();
      _edges = ((data['edges'] as List?) ?? [])
          .map((e) => MapEdge.fromJson(e))
          .toList();
      _alpha = 0.06; // mantém o layout salvo, só relaxa de leve
    } else {
      _seedDefault();
      _alpha = 1.0;
    }
    if (mounted) setState(() {});
  }

  void _seedDefault() {
    final cx = _canvasSize / 2;
    final cy = _canvasSize / 2;
    MapNode core = MapNode(id: _newId(), label: "Hub Core", x: cx, y: cy);
    final labels = [
      "Tarefas",
      "Monitoramento",
      "Senhas",
      "Mapa Mental",
      "IA do Hub",
      "Ideias Futuras",
    ];
    _nodes = [core];
    for (int i = 0; i < labels.length; i++) {
      final ang = (i / labels.length) * 2 * pi;
      _nodes.add(MapNode(
        id: _newId(),
        label: labels[i],
        x: cx + cos(ang) * 200,
        y: cy + sin(ang) * 200,
      ));
    }
    _edges = [
      for (int i = 1; i <= labels.length; i++) MapEdge(core.id, _nodes[i].id),
    ];
    // vínculo extra: IA do Hub -> Ideias Futuras
    _edges.add(MapEdge(_nodes[5].id, _nodes[6].id));
  }

  String _newId() =>
      "${DateTime.now().microsecondsSinceEpoch}_${_rnd.nextInt(9999)}";

  // ---------------------------------------------------------------
  // FÍSICA (force-directed)
  // ---------------------------------------------------------------
  void _tick(Duration _) {
    if (_alpha > 0.01) {
      _simulateStep();
      if (mounted) setState(() {});
    }
  }

  void _simulateStep() {
    const double repulsion = 14000.0;
    const double spring = 0.015;
    const double springLen = 160.0;
    const double center = 0.012;
    const double damping = 0.9;
    final double cx = _canvasSize / 2;
    final double cy = _canvasSize / 2;

    final int n = _nodes.length;
    if (n == 0) return;
    final fx = List<double>.filled(n, 0);
    final fy = List<double>.filled(n, 0);

    // repulsão entre todos os pares
    for (int i = 0; i < n; i++) {
      for (int j = i + 1; j < n; j++) {
        double dx = _nodes[i].x - _nodes[j].x;
        double dy = _nodes[i].y - _nodes[j].y;
        double d2 = dx * dx + dy * dy;
        if (d2 < 0.01) {
          dx = (i - j) + 0.1;
          dy = 0.1;
          d2 = dx * dx + dy * dy;
        }
        final double dist = sqrt(d2);
        final double force = repulsion / d2;
        final double ux = dx / dist;
        final double uy = dy / dist;
        fx[i] += ux * force;
        fy[i] += uy * force;
        fx[j] -= ux * force;
        fy[j] -= uy * force;
      }
    }

    // molas (arestas)
    final idx = <String, int>{for (int i = 0; i < n; i++) _nodes[i].id: i};
    for (final e in _edges) {
      final ia = idx[e.a];
      final ib = idx[e.b];
      if (ia == null || ib == null) continue;
      double dx = _nodes[ib].x - _nodes[ia].x;
      double dy = _nodes[ib].y - _nodes[ia].y;
      double dist = sqrt(dx * dx + dy * dy);
      if (dist < 0.01) dist = 0.01;
      final double f = (dist - springLen) * spring;
      final double ux = dx / dist;
      final double uy = dy / dist;
      fx[ia] += ux * f;
      fy[ia] += uy * f;
      fx[ib] -= ux * f;
      fy[ib] -= uy * f;
    }

    // centralização + integração
    for (int i = 0; i < n; i++) {
      final node = _nodes[i];
      if (node.pinned) {
        node.vx = 0;
        node.vy = 0;
        continue;
      }
      fx[i] += (cx - node.x) * center;
      fy[i] += (cy - node.y) * center;
      node.vx = ((node.vx + fx[i]) * damping).clamp(-40.0, 40.0);
      node.vy = ((node.vy + fy[i]) * damping).clamp(-40.0, 40.0);
      node.x += node.vx * _alpha;
      node.y += node.vy * _alpha;
    }

    _alpha *= 0.992;
  }

  void _reheat({bool small = false}) {
    if (small) {
      if (_alpha < 0.35) _alpha = 0.35;
    } else {
      _alpha = 1.0;
    }
  }

  // ---------------------------------------------------------------
  // HELPERS DE GRAFO
  // ---------------------------------------------------------------
  MapNode? _nodeById(String? id) {
    if (id == null) return null;
    for (final n in _nodes) {
      if (n.id == id) return n;
    }
    return null;
  }

  int _degreeOf(String id) {
    int c = 0;
    for (final e in _edges) {
      if (e.a == id || e.b == id) c++;
    }
    return c;
  }

  Set<String> _neighborsOf(String id) {
    final s = <String>{};
    for (final e in _edges) {
      if (e.a == id) s.add(e.b);
      if (e.b == id) s.add(e.a);
    }
    return s;
  }

  void _addEdge(String a, String b) {
    if (a == b) return;
    final exists =
        _edges.any((e) => (e.a == a && e.b == b) || (e.a == b && e.b == a));
    if (!exists) _edges.add(MapEdge(a, b));
  }

  void _save() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 500), () async {
      await HubFiles.saveMindMap({
        'nodes': _nodes.map((n) => n.toJson()).toList(),
        'edges': _edges.map((e) => e.toJson()).toList(),
      });
    });
  }

  // ---------------------------------------------------------------
  // AÇÕES DE EDIÇÃO
  // ---------------------------------------------------------------
  Future<void> _promptAddNode({String? connectTo}) async {
    final label = await _promptText(
        connectTo == null ? "Novo nó" : "Novo nó conectado", "");
    if (label == null || label.trim().isEmpty) return;
    final base = _nodeById(connectTo);
    final cx = base?.x ?? _canvasSize / 2;
    final cy = base?.y ?? _canvasSize / 2;
    final node = MapNode(
      id: _newId(),
      label: label.trim(),
      x: cx + _rnd.nextDouble() * 80 - 40,
      y: cy + _rnd.nextDouble() * 80 - 40,
    );
    setState(() {
      _nodes.add(node);
      if (connectTo != null) _addEdge(connectTo, node.id);
      _selectedId = node.id;
    });
    _reheat();
    _save();
  }

  Future<void> _renameSelected() async {
    final n = _nodeById(_selectedId);
    if (n == null) return;
    final label = await _promptText("Renomear", n.label);
    if (label == null || label.trim().isEmpty) return;
    setState(() => n.label = label.trim());
    _save();
  }

  void _deleteSelected() {
    final id = _selectedId;
    if (id == null) return;
    setState(() {
      _nodes.removeWhere((n) => n.id == id);
      _edges.removeWhere((e) => e.a == id || e.b == id);
      _selectedId = null;
      _linkMode = false;
    });
    _reheat();
    _save();
  }

  Future<String?> _promptText(String title, String initial) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: "Nome do nó"),
          onSubmitted: (v) => Navigator.pop(c, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, null),
              child: const Text("Cancelar",
                  style: TextStyle(color: Colors.white54))),
          ElevatedButton(
              onPressed: () => Navigator.pop(c, ctrl.text),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurpleAccent),
              child: const Text("OK")),
        ],
      ),
    );
  }

  void _recenter(Size viewport) {
    final tx = viewport.width / 2 - _canvasSize / 2;
    final ty = viewport.height / 2 - _canvasSize / 2;
    _tc.value = Matrix4.identity()..translate(tx, ty);
  }

  // ---------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final active = _hoverId ?? _selectedId;
    final neighbors = active != null ? _neighborsOf(active) : <String>{};
    final hasActive = active != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(),
        if (_selectedId != null) _buildSelectionBar(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0A0A),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white10),
                ),
                child: LayoutBuilder(builder: (context, cons) {
                  _lastViewport = Size(cons.maxWidth, cons.maxHeight);
                  if (!_centered) {
                    _centered = true;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _recenter(_lastViewport);
                    });
                  }
                  return InteractiveViewer(
                    transformationController: _tc,
                    constrained: false,
                    panEnabled: true,
                    scaleEnabled: true,
                    minScale: 0.2,
                    maxScale: 3.0,
                    boundaryMargin: const EdgeInsets.all(1200),
                    child: SizedBox(
                      width: _canvasSize,
                      height: _canvasSize,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // fundo: clicar pra desselecionar
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onTap: () => setState(() {
                                _selectedId = null;
                                _linkMode = false;
                              }),
                            ),
                          ),
                          // arestas
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _EdgePainter(
                                _nodes,
                                _edges,
                                active,
                                hasActive,
                              ),
                            ),
                          ),
                          // nós
                          ..._nodes.map((n) =>
                              _buildNode(n, active, neighbors, hasActive)),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.only(left: 24, top: 28, right: 24, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text("Mapa Mental",
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
          const SizedBox(width: 16),
          if (_linkMode)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.tealAccent.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text("Toque em outro nó pra conectar",
                  style:
                      TextStyle(color: Colors.tealAccent, fontSize: 12)),
            ),
          const Spacer(),
          SizedBox(
            width: 180,
            height: 38,
            child: TextField(
              decoration: InputDecoration(
                hintText: "Buscar...",
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                filled: true,
                fillColor: Colors.white10,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            tooltip: "Recentralizar",
            onPressed: () => _recenter(_lastViewport),
            icon: const Icon(Icons.center_focus_strong,
                color: Colors.white54),
          ),
          IconButton(
            tooltip: "Reorganizar",
            onPressed: () => _reheat(),
            icon: const Icon(Icons.auto_awesome, color: Colors.white54),
          ),
          const SizedBox(width: 4),
          ElevatedButton.icon(
            onPressed: () => _promptAddNode(),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurpleAccent),
            icon: const Icon(Icons.add, size: 18),
            label: const Text("Nó"),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionBar() {
    final n = _nodeById(_selectedId);
    if (n == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.deepPurpleAccent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.deepPurpleAccent.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.circle, size: 12, color: Colors.deepPurpleAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(n.label,
                style: const TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis),
          ),
          _barButton(Icons.edit, "Renomear", _renameSelected),
          _barButton(
            _linkMode ? Icons.link_off : Icons.link,
            _linkMode ? "Cancelar" : "Conectar",
            () => setState(() => _linkMode = !_linkMode),
            color: _linkMode ? Colors.tealAccent : Colors.white70,
          ),
          _barButton(Icons.account_tree, "Filho +",
              () => _promptAddNode(connectTo: n.id)),
          _barButton(Icons.delete_outline, "Excluir", _deleteSelected,
              color: Colors.redAccent),
        ],
      ),
    );
  }

  Widget _barButton(IconData icon, String tip, VoidCallback onTap,
      {Color color = Colors.white70}) {
    return IconButton(
      tooltip: tip,
      iconSize: 20,
      icon: Icon(icon, color: color),
      onPressed: onTap,
    );
  }

  Widget _buildNode(
      MapNode n, String? active, Set<String> neighbors, bool hasActive) {
    final deg = _degreeOf(n.id);
    final double r = (14.0 + deg * 3.0).clamp(14.0, 38.0);
    final isActive = n.id == active;
    final isNeighbor = neighbors.contains(n.id);
    final isSel = n.id == _selectedId;
    final dim = hasActive && !isActive && !isNeighbor;

    final matchSearch = _search.trim().isNotEmpty &&
        n.label.toLowerCase().contains(_search.trim().toLowerCase());

    Color c;
    if (matchSearch) {
      c = Colors.amberAccent;
    } else if (isSel) {
      c = Colors.deepPurpleAccent;
    } else if (isActive || isNeighbor) {
      c = Colors.tealAccent;
    } else {
      c = const Color(0xFF4DD0C4);
    }

    final widget = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hoverId = n.id),
      onExit: (_) => setState(() {
        if (_hoverId == n.id) _hoverId = null;
      }),
      child: GestureDetector(
        onTap: () {
          if (_linkMode && _selectedId != null && _selectedId != n.id) {
            setState(() {
              _addEdge(_selectedId!, n.id);
              _linkMode = false;
            });
            _reheat(small: true);
            _save();
          } else {
            setState(() => _selectedId = _selectedId == n.id ? null : n.id);
          }
        },
        onPanStart: (_) => setState(() {
          n.pinned = true;
          _selectedId = n.id;
        }),
        onPanUpdate: (d) {
          final scale = _tc.value.getMaxScaleOnAxis();
          setState(() {
            n.x += d.delta.dx / scale;
            n.y += d.delta.dy / scale;
            n.vx = 0;
            n.vy = 0;
          });
        },
        onPanEnd: (_) {
          setState(() => n.pinned = false);
          _reheat(small: true);
          _save();
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: r * 2,
              height: r * 2,
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
                border: isSel
                    ? Border.all(color: Colors.white, width: 2)
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: c.withOpacity(dim ? 0.15 : 0.55),
                    blurRadius: isActive || isSel ? 22 : 12,
                    spreadRadius: isActive || isSel ? 4 : 1,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 130),
              child: Text(
                n.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withOpacity(dim ? 0.3 : 0.85),
                  fontSize: r > 24 ? 14 : 12.5,
                  fontWeight:
                      (isSel || isActive) ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return Positioned(
      left: n.x,
      top: n.y,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: Opacity(opacity: dim ? 0.55 : 1.0, child: widget),
      ),
    );
  }
}

// ===================================================================
// PINTOR DAS ARESTAS
// ===================================================================
class _EdgePainter extends CustomPainter {
  final List<MapNode> nodes;
  final List<MapEdge> edges;
  final String? activeId;
  final bool dimOthers;

  _EdgePainter(this.nodes, this.edges, this.activeId, this.dimOthers);

  @override
  void paint(Canvas canvas, Size size) {
    final pos = <String, Offset>{
      for (final n in nodes) n.id: Offset(n.x, n.y)
    };

    for (final e in edges) {
      final a = pos[e.a];
      final b = pos[e.b];
      if (a == null || b == null) continue;

      final highlighted =
          activeId != null && (e.a == activeId || e.b == activeId);

      if (highlighted) {
        final glow = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..color = Colors.tealAccent.withOpacity(0.30)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
        canvas.drawLine(a, b, glow);
      }

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = highlighted ? 2.2 : 1.0
        ..color = highlighted
            ? Colors.tealAccent.withOpacity(0.9)
            : (dimOthers ? Colors.white12 : Colors.white24);
      canvas.drawLine(a, b, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _EdgePainter oldDelegate) => true;
}
