import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_markdown_plus_latex/flutter_markdown_plus_latex.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

import 'agent_math_markdown_normalizer.dart';

/// Renders model output as GitHub-flavored Markdown inside an existing chat
/// bubble. MarkdownBody sizes to its content; only equations scroll horizontally.
class AgentMarkdownText extends StatelessWidget {
  const AgentMarkdownText({
    super.key,
    required this.data,
    this.style,
  });

  final String data;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ?? DefaultTextStyle.of(context).style;
    final normalized = AgentMathMarkdownNormalizer(data);
    return MarkdownBody(
      data: normalized.data,
      selectable: true,
      extensionSet: md.ExtensionSet(
        [
          _MathBlockSyntax(normalized),
          ...md.ExtensionSet.gitHubFlavored.blockSyntaxes,
        ],
        [
          _MathSpanSyntax(normalized),
          ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
        ],
      ),
      builders: {
        'latex': _SafeLatexBuilder(normalized, baseStyle),
        'agent-math-block':
            _SafeLatexBuilder(normalized, baseStyle, block: true),
      },
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: baseStyle,
        h1: baseStyle.copyWith(fontSize: 22, fontWeight: FontWeight.w700),
        h2: baseStyle.copyWith(fontSize: 19, fontWeight: FontWeight.w700),
        h3: baseStyle.copyWith(fontSize: 17, fontWeight: FontWeight.w600),
        code: baseStyle.copyWith(fontFamily: 'monospace'),
      ),
    );
  }
}

// Only markers emitted outside Markdown code by the normalizer can become math.
class _MathSpanSyntax extends md.InlineSyntax {
  _MathSpanSyntax(this.normalized)
      : super('${RegExp.escape(normalized.marker)}([0-9]+)'
            ':[0-9-]+${RegExp.escape(normalized.marker)}');

  final AgentMathMarkdownNormalizer normalized;

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final element = md.Element.text('latex', match[1]!);
    parser.addNode(element);
    return true;
  }
}

class _SafeLatexBuilder extends LatexElementBuilder {
  _SafeLatexBuilder(this.normalized, this.baseStyle, {this.block = false});

  final AgentMathMarkdownNormalizer normalized;
  final TextStyle baseStyle;
  final bool block;

  @override
  bool isBlockElement() => block;

  @override
  Widget visitElementAfterWithContext(BuildContext context, md.Element element,
      TextStyle? preferredStyle, TextStyle? parentStyle) {
    final span = normalized
        .spans[int.parse(element.attributes['span'] ?? element.textContent)];
    final effectiveStyle = baseStyle.merge(preferredStyle ?? parentStyle);
    final math = Math.tex(
      span.tex,
      settings:
          const TexParserSettings(throwOnError: true, strict: Strict.ignore),
      mathStyle: span.display ? MathStyle.display : MathStyle.text,
      textStyle: effectiveStyle,
      textScaleFactor: MediaQuery.textScalerOf(context)
              .scale(effectiveStyle.fontSize ?? 14) /
          (effectiveStyle.fontSize ?? 14),
      onErrorFallback: (_) => Text(span.source, style: effectiveStyle),
    );
    // Constrain just the equation: long formulas remain readable on phones.
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.hasBoundedWidth
          ? constraints.maxWidth
          : MediaQuery.sizeOf(context).width - 48;
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: span.display ? 8 : 0),
            child: math,
          ),
        ),
      );
    });
  }
}

class _MathBlockSyntax extends md.BlockSyntax {
  _MathBlockSyntax(this.normalized);
  final AgentMathMarkdownNormalizer normalized;

  @override
  RegExp get pattern => RegExp('^${RegExp.escape(normalized.marker)}'
      '([0-9]+):[0-9-]+${RegExp.escape(normalized.marker)}\\s*\$');

  @override
  bool canParse(md.BlockParser parser) {
    final match = pattern.firstMatch(parser.current.content);
    return match != null && normalized.spans[int.parse(match[1]!)].display;
  }

  @override
  md.Node parse(md.BlockParser parser) {
    final match = pattern.firstMatch(parser.current.content)!;
    parser.advance();
    return md.Element.empty('agent-math-block')..attributes['span'] = match[1]!;
  }
}
