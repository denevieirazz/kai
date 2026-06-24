import 'package:flutter/material.dart';
import '../services/hub_files.dart';

class TodoPage extends StatefulWidget {
  const TodoPage({super.key});

  @override
  State<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends State<TodoPage> {
  final List<Map<String, dynamic>> _todos = [];
  final TextEditingController _controller = TextEditingController();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final saved = await HubFiles.loadTodos();
    if (!mounted) return;
    setState(() {
      _todos
        ..clear()
        ..addAll(saved.map((t) => {
              "title": (t["title"] ?? "").toString(),
              "done": t["done"] == true,
            }));
      _loaded = true;
    });
  }

  Future<void> _persist() async {
    await HubFiles.saveTodos(List<Map<String, dynamic>>.from(_todos));
  }

  void _addTodo() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      setState(() {
        _todos.add({"title": text, "done": false});
        _controller.clear();
      });
      _persist();
    }
  }

  void _toggleTodo(int index) {
    setState(() {
      _todos[index]["done"] = !_todos[index]["done"];
    });
    _persist();
  }

  void _deleteTodo(int index) {
    setState(() {
      _todos.removeAt(index);
    });
    _persist();
  }

  @override
  Widget build(BuildContext context) {
    final int pending = _todos.where((t) => t["done"] != true).length;
    final int done = _todos.length - pending;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 40.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Tarefas",
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            _todos.isEmpty
                ? "Organize seu dia"
                : "$pending pendente(s) · $done concluída(s)",
            style: const TextStyle(fontSize: 16, color: Colors.white54),
          ),
          const SizedBox(height: 40),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  style: const TextStyle(fontSize: 16),
                  decoration: InputDecoration(
                    hintText: "Adicionar nova tarefa...",
                    filled: true,
                    fillColor: Colors.white10,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (_) => _addTodo(),
                ),
              ),
              const SizedBox(width: 16),
              InkWell(
                onTap: _addTodo,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.deepPurpleAccent,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.deepPurpleAccent.withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      )
                    ]
                  ),
                  child: const Icon(Icons.add, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),
          Expanded(
            child: !_loaded
                ? const Center(
                    child: CircularProgressIndicator(
                        color: Colors.deepPurpleAccent),
                  )
                : _todos.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.task_alt,
                                size: 64, color: Colors.white24),
                            SizedBox(height: 16),
                            Text(
                              "Nenhuma tarefa ainda.\nAdicione a primeira acima.",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.white38, fontSize: 15),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _todos.length,
                        itemBuilder: (context, index) {
                          final todo = _todos[index];
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: todo["done"] ? Colors.white.withOpacity(0.05) : Colors.white10,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: todo["done"] ? Colors.transparent : Colors.white24,
                                width: 1,
                              )
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                leading: Checkbox(
                                  value: todo["done"],
                                  onChanged: (_) => _toggleTodo(index),
                                  activeColor: Colors.deepPurpleAccent,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                ),
                                title: Text(
                                  todo["title"],
                                  style: TextStyle(
                                    fontSize: 16,
                                    decoration: todo["done"]
                                        ? TextDecoration.lineThrough
                                        : TextDecoration.none,
                                    color: todo["done"] ? Colors.white38 : Colors.white,
                                  ),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.white38),
                                  hoverColor: Colors.redAccent.withOpacity(0.2),
                                  onPressed: () => _deleteTodo(index),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
