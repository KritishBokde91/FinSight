import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/ollama_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  String _selectedModel = 'gemma3:1b';
  List<String> _availableModels = [];
  String _status = '';
  bool _testing = false;

  final List<String> _defaultModels = [
    'gemma3:270m',
    'gemma3:1b',
    'llama3.1:8b',
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _hostController.text = prefs.getString('ollama_host') ?? '10.0.2.2';
    _portController.text = prefs.getString('ollama_port') ?? '11434';
    _selectedModel = prefs.getString('ollama_model') ?? 'gemma3:1b';
    setState(() {});
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ollama_host', _hostController.text.trim());
    await prefs.setString('ollama_port', _portController.text.trim());
    await prefs.setString('ollama_model', _selectedModel);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved.')),
      );
    }
  }

  Future<void> _testConnection() async {
    setState(() { _testing = true; _status = 'Testing...'; });
    try {
      final models = await OllamaService.testConnection();
      setState(() {
        _availableModels = models;
        _status = 'Connected! ${models.length} models found.';
      });
    } catch (e) {
      setState(() { _status = 'Failed: $e'; });
    } finally {
      setState(() { _testing = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final allModels = {..._defaultModels, ..._availableModels}.toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ollama Host (LAN IP of your PC)', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text(
              'Run Ollama on your PC with: OLLAMA_HOST=0.0.0.0 ollama serve\n'
              'Then enter your PC\'s local IP (e.g. 192.168.1.100).',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _hostController,
              decoration: const InputDecoration(labelText: 'Host IP', border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _portController,
              decoration: const InputDecoration(labelText: 'Port (default 11434)', border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            const Text('Model', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: allModels.contains(_selectedModel) ? _selectedModel : allModels.first,
              items: allModels.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
              onChanged: (v) => setState(() => _selectedModel = v!),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                ElevatedButton(
                  onPressed: _testing ? null : _testConnection,
                  child: Text(_testing ? 'Testing...' : 'Test Connection'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _saveSettings,
                  child: const Text('Save'),
                ),
              ],
            ),
            if (_status.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(_status, style: TextStyle(
                color: _status.startsWith('Connected') ? Colors.green : Colors.red,
              )),
            ],
            if (_availableModels.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Models on your Ollama:', style: TextStyle(fontWeight: FontWeight.bold)),
              ..._availableModels.map((m) => Text('• $m')),
            ],
          ],
        ),
      ),
    );
  }
}
