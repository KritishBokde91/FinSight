import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:http/http.dart' as http;
import '../core/theme.dart';
import '../core/constants.dart';

class AiInsightsScreen extends StatefulWidget {
  const AiInsightsScreen({super.key});

  @override
  State<AiInsightsScreen> createState() => _AiInsightsScreenState();
}

class _AiInsightsScreenState extends State<AiInsightsScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _isLoading = false;
  String _statusText = '';
  bool _isCrawling = false;

  final List<String> _quickPrompts = [
    '📊 Analyze my spending',
    '💰 Investment suggestions',
    '📈 Monthly summary',
    '🏦 Savings tips',
    '🔮 Spending predictions',
    '📉 Where can I cut costs?',
  ];

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty || _isLoading) return;

    _controller.clear();
    setState(() {
      _messages.add(_ChatMessage(role: 'user', content: text));
      _isLoading = true;
      _statusText = 'Thinking...';
      _isCrawling = false;
    });
    _scrollToBottom();

    // Add a placeholder assistant message that we'll stream into
    final assistantMsg = _ChatMessage(role: 'assistant', content: '');
    setState(() => _messages.add(assistantMsg));

    try {
      final request = http.Request(
        'POST',
        Uri.parse('${AppConstants.apiBaseUrl}/api/ai/chat'),
      );
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode({
        'prompt': text,
        'system_prompt': null,
        'user_id': null,
      });

      final client = http.Client();
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 120));

      if (response.statusCode == 200) {
        // Process SSE stream
        String buffer = '';
        await for (final chunk in response.stream.transform(utf8.decoder)) {
          buffer += chunk;

          // Process complete SSE events (separated by double newlines)
          while (buffer.contains('\n\n')) {
            final eventEnd = buffer.indexOf('\n\n');
            final eventStr = buffer.substring(0, eventEnd);
            buffer = buffer.substring(eventEnd + 2);

            _processSSEEvent(eventStr, assistantMsg);
          }
        }

        // Process any remaining buffer
        if (buffer.trim().isNotEmpty) {
          _processSSEEvent(buffer.trim(), assistantMsg);
        }
      } else {
        setState(() {
          assistantMsg.content =
              '⚠️ Error: ${response.statusCode}. Make sure the backend is running.';
        });
      }
      client.close();
    } catch (e) {
      setState(() {
        assistantMsg.content =
            '⚠️ Connection error. Make sure the backend and Ollama are running.\n\nDetails: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
        _isCrawling = false;
        _statusText = '';
      });
      _scrollToBottom();
    }
  }

  void _processSSEEvent(String eventStr, _ChatMessage assistantMsg) {
    String eventType = '';
    String eventData = '';

    for (final line in eventStr.split('\n')) {
      if (line.startsWith('event: ')) {
        eventType = line.substring(7).trim();
      } else if (line.startsWith('data: ')) {
        eventData = line.substring(6);
      }
    }

    if (eventData.isEmpty) return;

    try {
      final data = jsonDecode(eventData);

      switch (eventType) {
        case 'status':
          final phase = data['phase'] as String? ?? '';
          final message = data['message'] as String? ?? '';
          setState(() {
            _statusText = message;
            _isCrawling = phase == 'searching' || phase == 'crawling';
          });
          break;

        case 'sources':
          // data is a list of sources
          final sourcesList = data as List;
          final sources = sourcesList
              .map(
                (s) => _WebSource(
                  title: s['title'] ?? '',
                  url: s['url'] ?? '',
                  extracted: s['extracted'] ?? false,
                ),
              )
              .toList();
          setState(() {
            assistantMsg.sources = sources;
          });
          break;

        case 'token':
          final tokenText = data['text'] as String? ?? '';
          setState(() {
            assistantMsg.content += tokenText;
            _isCrawling = false;
          });
          _scrollToBottom();
          break;

        case 'done':
          setState(() {
            _isLoading = false;
            _isCrawling = false;
            _statusText = '';
          });
          break;
      }
    } catch (_) {
      // If JSON parse fails, treat as raw text token
      setState(() {
        assistantMsg.content += eventData;
      });
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI Insights',
                        style: GoogleFonts.outfit(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        'Powered by Vicuna 13B',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.cyan.withAlpha(15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      color: AppTheme.cyan,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 400.ms),

            const SizedBox(height: 8),

            // ── Chat Area ──
            Expanded(
              child: _messages.isEmpty
                  ? _buildWelcome()
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        return _buildMessage(_messages[index]);
                      },
                    ),
            ),

            // ── Streaming Status Indicator ──
            if (_isLoading && _statusText.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _isCrawling ? AppTheme.cyan : AppTheme.gold,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _isCrawling ? '🌐 $_statusText' : '✨ $_statusText',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: _isCrawling ? AppTheme.cyan : AppTheme.gold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 300.ms),

            // ── Input Area ──
            _buildInputArea(),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcome() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.cyan.withAlpha(12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  size: 48,
                  color: AppTheme.cyan.withAlpha(180),
                ),
              )
              .animate()
              .fadeIn(duration: 600.ms)
              .scale(begin: const Offset(0.8, 0.8)),
          const SizedBox(height: 20),
          Text(
            'Your AI Financial Advisor',
            style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ).animate().fadeIn(duration: 600.ms, delay: 200.ms),
          const SizedBox(height: 8),
          Text(
            'Ask about your finances, get investment ideas,\nor analyze your spending patterns.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppTheme.textMuted,
              height: 1.5,
            ),
          ).animate().fadeIn(duration: 600.ms, delay: 300.ms),
          const SizedBox(height: 24),
          // Quick prompts
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: _quickPrompts.asMap().entries.map((entry) {
              return GestureDetector(
                    onTap: () => _sendMessage(
                      entry.value.replaceAll(RegExp(r'[^\w\s]'), '').trim(),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceLight,
                        borderRadius: AppTheme.chipRadius,
                        border: Border.all(color: AppTheme.surfaceBorder),
                      ),
                      child: Text(
                        entry.value,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  )
                  .animate()
                  .fadeIn(
                    duration: 400.ms,
                    delay: Duration(milliseconds: 400 + entry.key * 80),
                  )
                  .slideY(begin: 0.1);
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(_ChatMessage msg) {
    final isUser = msg.role == 'user';
    final isEmpty = !isUser && msg.content.isEmpty && _isLoading;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          // Role label
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isUser) ...[
                  Icon(
                    Icons.auto_awesome_rounded,
                    size: 14,
                    color: AppTheme.cyan,
                  ),
                  const SizedBox(width: 4),
                ],
                Text(
                  isUser ? 'You' : 'FinSight AI',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          // Message bubble
          if (!isEmpty)
            Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.82,
              ),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isUser
                    ? AppTheme.gold.withAlpha(15)
                    : AppTheme.surfaceLight,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
                border: Border.all(
                  color: isUser
                      ? AppTheme.gold.withAlpha(40)
                      : AppTheme.surfaceBorder,
                ),
              ),
              child: Text(
                msg.content,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: AppTheme.textPrimary,
                  height: 1.5,
                ),
              ),
            ),
          // Typing indicator for empty assistant message
          if (isEmpty) _buildTypingIndicator(),
          // Web sources
          if (msg.sources.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.82,
              ),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.surfaceLight.withAlpha(100),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.cyan.withAlpha(30)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.language_rounded,
                        size: 12,
                        color: AppTheme.cyan,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Web Sources',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AppTheme.cyan,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ...msg.sources.map(
                    (s) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Icon(
                            s.extracted
                                ? Icons.check_circle_rounded
                                : Icons.open_in_new_rounded,
                            size: 12,
                            color: s.extracted
                                ? AppTheme.success
                                : AppTheme.textMuted,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              s.title.isNotEmpty ? s.title : s.url,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.05);
  }

  Widget _buildTypingIndicator() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          return Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: AppTheme.cyan.withAlpha(180),
                  shape: BoxShape.circle,
                ),
              )
              .animate(onPlay: (c) => c.repeat())
              .fadeIn(
                duration: 600.ms,
                delay: Duration(milliseconds: i * 200),
              )
              .then()
              .fadeOut(duration: 600.ms);
        }),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          top: BorderSide(color: AppTheme.surfaceBorder.withAlpha(100)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceLight,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppTheme.surfaceBorder),
              ),
              child: TextField(
                controller: _controller,
                style: GoogleFonts.inter(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: 'Ask about your finances...',
                  hintStyle: GoogleFonts.inter(
                    color: AppTheme.textMuted,
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
                maxLines: null,
                textInputAction: TextInputAction.send,
                onSubmitted: _sendMessage,
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => _sendMessage(_controller.text),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: AppTheme.goldGradient,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.gold.withAlpha(40),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.send_rounded,
                color: AppTheme.background,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatMessage {
  final String role;
  String content;
  List<_WebSource> sources;

  _ChatMessage({
    required this.role,
    required this.content,
    List<_WebSource>? sources,
  }) : sources = sources ?? [];
}

class _WebSource {
  final String title;
  final String url;
  final bool extracted;

  _WebSource({required this.title, required this.url, this.extracted = false});
}
