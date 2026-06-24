import 'package:flutter/material.dart';
import 'todo_page.dart';
import 'monitor_page.dart';
import 'password_gen_page.dart';
import 'mind_map_page.dart';
import 'voice_command_page.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    const TodoPage(),
    const MonitorPage(),
    const PasswordGenPage(),
    const MindMapPage(),
    const VoiceCommandPage(),
  ];

  @override
  Widget build(BuildContext context) {
    // This makes the UI responsive to screen width
    final bool isDesktop = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      appBar: isDesktop ? null : AppBar(
        title: const Text('Hub Arsenal', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.black45,
        elevation: 0,
      ),
      drawer: isDesktop ? null : _buildDrawer(),
      body: Row(
        children: [
          if (isDesktop) _buildSidebar(),
          Expanded(
            child: _pages[_selectedIndex],
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF1A1A1A),
      child: _buildSidebarContent(),
    );
  }

  Widget _buildSidebar() {
    return Material(
      color: const Color(0xFF1A1A1A),
      child: SizedBox(
        width: 250,
        child: _buildSidebarContent(),
      ),
    );
  }

  Widget _buildSidebarContent() {
    return Column(
      children: [
        const SizedBox(height: 50),
        const Text(
          "HUB",
          style: TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w900,
            letterSpacing: 6,
            color: Colors.deepPurpleAccent,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          "SEU ARSENAL",
          style: TextStyle(
            fontSize: 12,
            letterSpacing: 2,
            color: Colors.white54,
          ),
        ),
        const SizedBox(height: 50),
        ListTile(
          leading: Icon(Icons.check_box, color: _selectedIndex == 0 ? Colors.deepPurpleAccent : Colors.white54),
          title: Text(
            "Tarefas",
            style: TextStyle(
              color: _selectedIndex == 0 ? Colors.white : Colors.white54,
              fontWeight: _selectedIndex == 0 ? FontWeight.bold : FontWeight.normal,
            )
          ),
          selected: _selectedIndex == 0,
          onTap: () {
            setState(() => _selectedIndex = 0);
            if (MediaQuery.of(context).size.width <= 600) {
              Navigator.pop(context); // Close drawer on mobile
            }
          },
        ),
        ListTile(
          leading: Icon(Icons.memory, color: _selectedIndex == 1 ? Colors.deepPurpleAccent : Colors.white54),
          title: Text(
            "Monitoramento",
            style: TextStyle(
              color: _selectedIndex == 1 ? Colors.white : Colors.white54,
              fontWeight: _selectedIndex == 1 ? FontWeight.bold : FontWeight.normal,
            )
          ),
          selected: _selectedIndex == 1,
          onTap: () {
            setState(() => _selectedIndex = 1);
            if (MediaQuery.of(context).size.width <= 600) {
              Navigator.pop(context); // Close drawer on mobile
            }
          },
        ),
        ListTile(
          leading: Icon(Icons.password, color: _selectedIndex == 2 ? Colors.deepPurpleAccent : Colors.white54),
          title: Text(
            "Gerador de Senhas",
            style: TextStyle(
              color: _selectedIndex == 2 ? Colors.white : Colors.white54,
              fontWeight: _selectedIndex == 2 ? FontWeight.bold : FontWeight.normal,
            )
          ),
          selected: _selectedIndex == 2,
          onTap: () {
            setState(() => _selectedIndex = 2);
            if (MediaQuery.of(context).size.width <= 600) {
              Navigator.pop(context); // Close drawer on mobile
            }
          },
        ),
        ListTile(
          leading: Icon(Icons.account_tree, color: _selectedIndex == 3 ? Colors.deepPurpleAccent : Colors.white54),
          title: Text(
            "Mapa Mental",
            style: TextStyle(
              color: _selectedIndex == 3 ? Colors.white : Colors.white54,
              fontWeight: _selectedIndex == 3 ? FontWeight.bold : FontWeight.normal,
            )
          ),
          selected: _selectedIndex == 3,
          onTap: () {
            setState(() => _selectedIndex = 3);
            if (MediaQuery.of(context).size.width <= 600) {
              Navigator.pop(context); // Close drawer on mobile
            }
          },
        ),
        ListTile(
          leading: Icon(Icons.mic, color: _selectedIndex == 4 ? Colors.deepPurpleAccent : Colors.white54),
          title: Text(
            "Comando de Voz",
            style: TextStyle(
              color: _selectedIndex == 4 ? Colors.white : Colors.white54,
              fontWeight: _selectedIndex == 4 ? FontWeight.bold : FontWeight.normal,
            )
          ),
          selected: _selectedIndex == 4,
          onTap: () {
            setState(() => _selectedIndex = 4);
            if (MediaQuery.of(context).size.width <= 600) {
              Navigator.pop(context); // Close drawer on mobile
            }
          },
        ),
      ],
    );
  }
}
