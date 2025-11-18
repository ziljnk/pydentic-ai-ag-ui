import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class Message {
  final String id;
  final String text;
  final Sender sender;
  final DateTime timestamp;

  Message({
    required this.id,
    required this.text,
    required this.sender,
    required this.timestamp,
  });
}

enum Sender { user, bot }

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  // Toggle verbose logging for streaming/SSE parsing
  static const bool _logEnabled = true;
  void _log(String msg) {
    if (_logEnabled) debugPrint('[Chat] $msg');
  }

  final List<Message> _messages = [
    Message(
      id: 'welcome',
      text: 'Hello! How can I help you today?',
      sender: Sender.bot,
      timestamp: DateTime.now(),
    ),
  ];

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isSending = false;
  late final String _threadId;

  // IMPORTANT: If running on a physical device/emulator, set this to your machine's LAN IP
  // Example: 'http://192.168.1.5:8000/ag-ui'
  // For iOS simulator, http to localhost may be blocked by ATS unless configured.
  // Consider using a LAN address and enabling "App Transport Security" exceptions on iOS for development.
  String baseUrl = 'http://localhost:8000/ag-ui';

  @override
  void initState() {
    super.initState();
    _threadId = 'thread-${DateTime.now().millisecondsSinceEpoch}-${_rand()}';
    // Rebuild when the user types so the send button enable/disable updates.
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  String _rand() =>
      (DateTime.now().microsecondsSinceEpoch % 1000000).toRadixString(36);

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _handleSend() async {
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty || _isSending) return;

    // Push user message instantly
    final userId = 'user-${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      _messages.add(
        Message(
          id: userId,
          text: trimmed,
          sender: Sender.user,
          timestamp: DateTime.now(),
        ),
      );
      _isSending = true;
      _controller.clear();
    });
    _scrollToBottom();

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
    };

    final runInput = <String, dynamic>{
      'threadId': _threadId,
      'runId': 'run-${DateTime.now().millisecondsSinceEpoch}',
      'messages': [
        {
          'id': 'msg-${DateTime.now().millisecondsSinceEpoch}',
          'role': 'user',
          'content': [
            {'type': 'text', 'text': trimmed},
          ],
        },
      ],
      'state': {'document': ''},
      'tools': [],
      'context': [],
      'forwardedProps': {},
    };

    try {
      final client = http.Client();
      try {
        final requestBody = jsonEncode(runInput);
        _log('Sending POST to $baseUrl');
        _log('Headers: ${headers.toString()}');
        _log(
          'Body: ${requestBody.length > 600 ? requestBody.substring(0, 600) + '…' : requestBody}',
        );

        final req = http.Request('POST', Uri.parse(baseUrl))
          ..headers.addAll(headers)
          ..body = requestBody;

        final streamed = await client.send(req);
        _log('Response status: ${streamed.statusCode}');
        _log('Response headers: ${streamed.headers.toString()}');

        // If backend returns a non-200, surface the error text once and stop.
        if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
          final body = await streamed.stream.bytesToString();
          setState(() {
            _messages.add(
              Message(
                id: 'http-${DateTime.now().millisecondsSinceEpoch}',
                text:
                    'Request failed (${streamed.statusCode}).\n${body.isEmpty ? 'No response body' : body}',
                sender: Sender.bot,
                timestamp: DateTime.now(),
              ),
            );
          });
          return;
        }

        // Parse SSE stream per chunk using the "data: {...}\n\n" framing
        final completer = Completer<void>();
        final decoder = utf8.decoder.bind(streamed.stream);
        String sseBuffer = '';
        final sub = decoder.listen(
          (chunk) {
            _log(
              'Chunk (${chunk.length} bytes):\n${chunk.length > 800 ? chunk.substring(0, 800) + '…' : chunk}',
            );
            sseBuffer += chunk;
            final events = sseBuffer.split('\n\n');
            sseBuffer = events.removeLast(); // keep trailing partial event
            for (final evt in events) {
              _log('Event block:<<<\n$evt\n>>>');
              _handleSseEvent(evt);
            }
            _scrollToBottom();
          },
          onError: (err, st) {
            _log('Stream error: $err');
            completer.completeError(err, st);
          },
          onDone: () {
            final remainder = sseBuffer.trim();
            if (remainder.isNotEmpty) {
              _log('Final remainder block:<<<\n$remainder\n>>>');
              _handleSseEvent(remainder);
            }
            completer.complete();
          },
          cancelOnError: true,
        );
        await completer.future;
        await sub.cancel();
      } finally {
        client.close();
      }
    } catch (e) {
      _log('Request exception: $e');
      setState(() {
        _messages.add(
          Message(
            id: 'err-${DateTime.now().millisecondsSinceEpoch}',
            text: 'Error: $e',
            sender: Sender.bot,
            timestamp: DateTime.now(),
          ),
        );
      });
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
      _scrollToBottom();
    }
  }

  // Parse a single JSONL line and update UI state accordingly
  void _handleEventLine(
    String jsonl,
    void Function(String id, String text) track,
  ) {
    try {
      // Support both JSONL and SSE (data: {json}) formats
      String line = jsonl.trim();
      if (line.isEmpty) return;
      if (line.startsWith(':') ||
          line.startsWith('event:') ||
          line.startsWith('id:')) {
        // Ignore SSE comments/control fields
        return;
      }
      if (line.startsWith('data:')) {
        line = line.substring(5).trim();
      }

      final event = jsonDecode(line) as Map<String, dynamic>;
      final type = event['type'] as String?;
      _log('Parsed event type: $type');
      switch (type) {
        case 'TEXT_MESSAGE_START':
          final id = (event['messageId'] as String?) ?? 'assistant-message';
          _log('TEXT_MESSAGE_START id=$id');
          track(id, '');
          setState(() {
            _messages.add(
              Message(
                id: id,
                text: '',
                sender: Sender.bot,
                timestamp: DateTime.now(),
              ),
            );
          });
          break;
        case 'TEXT_MESSAGE_CONTENT':
          final id = (event['messageId'] as String?) ?? 'assistant-message';
          final delta = (event['delta'] as String?) ?? '';
          _log(
            'TEXT_MESSAGE_CONTENT id=$id deltaLen=${delta.length} preview="${delta.length > 120 ? delta.substring(0, 120) + '…' : delta}"',
          );
          // Accumulate
          final idx = _messages.indexWhere(
            (m) => m.id == id && m.sender == Sender.bot,
          );
          if (idx == -1) {
            setState(() {
              _messages.add(
                Message(
                  id: id,
                  text: delta,
                  sender: Sender.bot,
                  timestamp: DateTime.now(),
                ),
              );
            });
            track(id, delta);
          } else {
            setState(() {
              final old = _messages[idx];
              final updated = Message(
                id: old.id,
                text: old.text + delta,
                sender: old.sender,
                timestamp: old.timestamp,
              );
              _messages[idx] = updated;
            });
            track(id, _messages[idx].text);
          }
          break;
        case 'TEXT_MESSAGE_END':
          _log('TEXT_MESSAGE_END');
          // no-op for now
          break;
        default:
          _log('Unknown/ignored event: $line');
          break;
      }
    } catch (error) {
      _log('Malformed event line, ignoring. Error=$error line="$jsonl"');
    }
  }

  // Handle a single SSE event block (may have multiple lines, including multiple data: lines)
  void _handleSseEvent(String eventBlock) {
    final lines = eventBlock.split('\n');
    final dataLines = <String>[];
    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.isEmpty) continue;
      if (line.startsWith(':') ||
          line.startsWith('event:') ||
          line.startsWith('id:')) {
        // ignore control/comment lines
        continue;
      }
      if (line.startsWith('data:')) {
        dataLines.add(line.substring(5).trimLeft());
      }
    }

    if (dataLines.isEmpty) {
      // Fallback: some servers may not prefix with data:, try as raw JSONL
      final raw = eventBlock.trim();
      if (raw.isNotEmpty) {
        _log('No data: lines, treating as JSONL: "$raw"');
        _handleEventLine(raw, (id, text) {});
      }
      return;
    }

    // Concatenate multiple data: lines per SSE spec (joined by newlines)
    final payload = dataLines.join('\n');
    _log(
      'SSE data payload: ${payload.length > 800 ? payload.substring(0, 800) + '…' : payload}',
    );
    _handleEventLine(payload, (id, text) {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Chat'), centerTitle: false),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final m = _messages[index];
                final isUser = m.sender == Sender.user;
                final bubbleColor = isUser
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surface;
                final textColor = isUser
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface;
                final align = isUser
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start;

                return Column(
                  crossAxisAlignment: align,
                  children: [
                    Container(
                      constraints: const BoxConstraints(maxWidth: 500),
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: bubbleColor,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(16),
                          topRight: const Radius.circular(16),
                          bottomLeft: Radius.circular(isUser ? 16 : 4),
                          bottomRight: Radius.circular(isUser ? 4 : 16),
                        ),
                        border: Border.all(
                          color: theme.dividerColor.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: isUser
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.text,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: textColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatTime(m.timestamp),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: textColor.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) {
                        if (_controller.text.trim().isNotEmpty && !_isSending) {
                          _handleSend();
                        }
                      },
                      decoration: InputDecoration(
                        hintText: 'Type a message…',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: ElevatedButton(
                      onPressed: (_controller.text.trim().isEmpty || _isSending)
                          ? null
                          : _handleSend,
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        shape: const CircleBorder(),
                      ),
                      child: const Icon(Icons.send),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime ts) {
    final h = ts.hour.toString().padLeft(2, '0');
    final m = ts.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
