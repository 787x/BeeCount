import 'dart:convert';

import 'package:agentcore/agentcore.dart';
import 'package:test/test.dart';

void main() {
  for (final field in ['reasoning_content', 'reasoning']) {
    test('$field fragments survive tools and subsequent model rounds',
        () async {
      var turn = 0;
      final requests = <List<Map<String, dynamic>>>[];
      final events = <AgentNativeStreamEvent>[];
      final logs = <String>[];
      final transport = OpenAiCompatibleNativeToolTransport(
        systemPrompt: 'system',
        toolDefinitions: const [
          AgentNativeToolDefinition(
              name: 'read', description: 'Read', parameters: {'type': 'object'})
        ],
        logSink: (_, data) => logs.add(jsonEncode(data)),
        toolStream: ({required messages, required tools, logTag}) async* {
          requests.add((jsonDecode(jsonEncode(messages)) as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList());
          turn++;
          for (final delta in [
            {field: 'private-A'},
            {field: 'private-B'},
            if (turn <= 2) ...[
              {
                'tool_calls': [
                  {
                    'index': 0,
                    'id': 'call-$turn',
                    'function': {'name': 'read', 'arguments': '{"value":'}
                  }
                ]
              },
              {
                'tool_calls': [
                  {
                    'index': 0,
                    'function': {'arguments': '1}'}
                  }
                ]
              },
            ] else
              {'content': 'answer'},
          ]) {
            yield {
              'choices': [
                {'delta': delta}
              ]
            };
          }
          yield {
            'choices': [
              {'delta': {}, 'finish_reason': turn <= 2 ? 'tool_calls' : 'stop'}
            ]
          };
        },
      );
      for (var index = 0; index < 3; index++) {
        final response = await transport.complete(
            AgentNativeToolRequest(
                runId: 'run',
                userPrompt: 'read',
                toolResults: [
                  if (index > 0)
                    AgentNativeToolResult(
                        toolCallId: 'call-$index', content: '{"ok":true}'),
                ]),
            onEvent: events.add);
        if (index < 2) {
          expect(
              (response as AgentNativeToolCallsResponse).calls.single.arguments,
              {'value': 1});
        } else {
          expect((response as AgentNativeFinalTextResponse).text, 'answer');
        }
      }
      for (final request in requests.skip(1)) {
        final assistants = request.where((e) => e['role'] == 'assistant');
        for (final assistant in assistants) {
          expect(assistant['reasoning_content'], 'private-Aprivate-B');
          expect(assistant['content'], isNull);
          expect(
              (assistant['tool_calls'] as List).single['function']['arguments'],
              '{"value":1}');
          final result = request[request.indexOf(assistant) + 1];
          expect(result['role'], 'tool');
          expect(result['content'], '{"ok":true}');
        }
      }
      expect(events.whereType<AgentNativeReasoningDelta>().map((e) => e.text), [
        'private-A',
        'private-B',
        'private-A',
        'private-B',
        'private-A',
        'private-B'
      ]);
      expect(logs.join(), isNot(contains('private-A')));
    });
  }

  test('reasoning text resembling tools cannot execute a tool', () async {
    final transport = OpenAiCompatibleNativeToolTransport(
        systemPrompt: '',
        toolDefinitions: const [],
        toolStream: ({required messages, required tools, logTag}) async* {
          yield {
            'choices': [
              {
                'delta': {
                  'reasoning_content':
                      '{"tool_calls":[{"function":{"name":"write"}}]}',
                  'content': 'safe'
                },
                'finish_reason': 'stop'
              }
            ]
          };
        });
    final response = await transport.complete(AgentNativeToolRequest(
        runId: 'safe', userPrompt: 'test', toolResults: []));
    expect((response as AgentNativeFinalTextResponse).text, 'safe');
  });
}
