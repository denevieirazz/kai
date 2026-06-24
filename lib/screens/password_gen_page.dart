import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';

class PasswordGenPage extends StatefulWidget {
  const PasswordGenPage({super.key});

  @override
  State<PasswordGenPage> createState() => _PasswordGenPageState();
}

class _PasswordGenPageState extends State<PasswordGenPage> {
  double _length = 16;
  bool _useUppercase = true;
  bool _useLowercase = true;
  bool _useNumbers = true;
  bool _useSymbols = true;
  String _generatedPassword = "Clique para gerar";

  void _generatePassword() {
    const uppercase = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    const lowercase = 'abcdefghijklmnopqrstuvwxyz';
    const numbers = '0123456789';
    const symbols = '!@#\$%^&*()_+~`|}{[]:;?><,./-=';

    String chars = '';
    if (_useUppercase) chars += uppercase;
    if (_useLowercase) chars += lowercase;
    if (_useNumbers) chars += numbers;
    if (_useSymbols) chars += symbols;

    if (chars.isEmpty) {
      setState(() {
        _generatedPassword = "Selecione pelo menos uma opção!";
      });
      return;
    }

    final random = Random.secure();
    final password = List.generate(
      _length.toInt(),
      (index) => chars[random.nextInt(chars.length)],
    ).join();

    setState(() {
      _generatedPassword = password;
    });
  }

  void _copyToClipboard() {
    if (_generatedPassword != "Clique para gerar" && _generatedPassword != "Selecione pelo menos uma opção!") {
      Clipboard.setData(ClipboardData(text: _generatedPassword));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Senha copiada para a área de transferência!"),
          backgroundColor: Colors.tealAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 40.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Gerador de Senhas",
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            "Crie senhas fortes e seguras",
            style: TextStyle(fontSize: 16, color: Colors.white54),
          ),
          const SizedBox(height: 40),
          
          // Password Display
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.deepPurpleAccent.withOpacity(0.5), width: 2),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _generatedPassword,
                    style: TextStyle(
                      fontSize: 24,
                      fontFamily: 'monospace',
                      color: _generatedPassword.contains("Selecione") ? Colors.redAccent : Colors.tealAccent,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, color: Colors.white70),
                  onPressed: _copyToClipboard,
                  tooltip: "Copiar",
                )
              ],
            ),
          ),
          
          const SizedBox(height: 40),
          
          // Controls
          Text("Tamanho: ${_length.toInt()}", style: const TextStyle(fontSize: 18)),
          Slider(
            value: _length,
            min: 6,
            max: 64,
            divisions: 58,
            activeColor: Colors.deepPurpleAccent,
            onChanged: (val) {
              setState(() => _length = val);
            },
          ),
          
          const SizedBox(height: 20),
          
          Wrap(
            spacing: 20,
            runSpacing: 20,
            children: [
              _buildCheckbox("Maiúsculas", _useUppercase, (val) => setState(() => _useUppercase = val!)),
              _buildCheckbox("Minúsculas", _useLowercase, (val) => setState(() => _useLowercase = val!)),
              _buildCheckbox("Números", _useNumbers, (val) => setState(() => _useNumbers = val!)),
              _buildCheckbox("Símbolos", _useSymbols, (val) => setState(() => _useSymbols = val!)),
            ],
          ),
          
          const SizedBox(height: 40),
          
          Center(
            child: ElevatedButton.icon(
              onPressed: _generatePassword,
              icon: const Icon(Icons.refresh, size: 28),
              label: const Text("GERAR SENHA", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurpleAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildCheckbox(String title, bool value, Function(bool?) onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(
          value: value,
          onChanged: onChanged,
          activeColor: Colors.deepPurpleAccent,
        ),
        Text(title, style: const TextStyle(fontSize: 16)),
      ],
    );
  }
}
