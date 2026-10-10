/// Render-only math spans; the original message and clipboard stay untouched.
class AgentMathSpan {
  const AgentMathSpan(this.source, this.tex, this.display);

  final String source;
  final String tex;
  final bool display;
}

/// Protects Markdown code and only recognizes complete, conservative math.
class AgentMathMarkdownNormalizer {
  AgentMathMarkdownNormalizer(String source) {
    // Pick a marker absent from the input so model text cannot impersonate spans.
    var candidate = '\uE000';
    while (source.contains(candidate)) {
      candidate += '\uE000';
    }
    marker = candidate;
    final out = StringBuffer();
    var i = 0;
    String? fence;
    while (i < source.length) {
      if (i == 0 || source[i - 1] == '\n') {
        final end = source.indexOf('\n', i);
        final lineEnd = end < 0 ? source.length : end + 1;
        final line = source.substring(i, lineEnd);
        final match =
            RegExp(r'^\s*(?:>\s*)*(?:[-+*] )?(`{3,}|~{3,})').firstMatch(line);
        if (fence != null || match != null) {
          out.write(line);
          if (fence == null) {
            fence = match!.group(1);
          } else if (match != null &&
              match.group(1)![0] == fence[0] &&
              match.group(1)!.length >= fence.length &&
              line.substring(match.end).trim().isEmpty) {
            fence = null;
          }
          i = lineEnd;
          continue;
        }
        // Indented code is also a Markdown code block.
        if (line.startsWith('    ') || line.startsWith('\t')) {
          out.write(line);
          i = lineEnd;
          continue;
        }
      }
      if (source[i] == '`') {
        var endRun = i + 1;
        while (endRun < source.length && source[endRun] == '`') {
          endRun++;
        }
        final run = source.substring(i, endRun);
        var closing = source.indexOf(run, endRun);
        while (closing >= 0 &&
            ((closing > 0 && source[closing - 1] == '`') ||
                (closing + run.length < source.length &&
                    source[closing + run.length] == '`'))) {
          closing = source.indexOf(run, closing + run.length);
        }
        // An unfinished streaming code span remains literal until it closes.
        final end = closing < 0 ? source.length : closing + run.length;
        out.write(source.substring(i, end));
        i = end;
        continue;
      }
      String? open;
      String? close;
      if (source.startsWith(r'\(', i)) {
        open = r'\(';
        close = r'\)';
      } else if (source.startsWith(r'\[', i)) {
        open = r'\[';
        close = r'\]';
      } else if (source.startsWith(r'$$', i)) {
        open = close = r'$$';
      } else if (source[i] == r'$') {
        open = close = r'$';
      }
      if (open != null) {
        var end = source.indexOf(close!, i + open.length);
        while (end >= 0 && _escaped(source, end)) {
          end = source.indexOf(close, end + close.length);
        }
        if (end >= 0) {
          final tex = source.substring(i + open.length, end);
          if (open != r'$' || _isDollarMath(tex)) {
            final raw = source.substring(i, end + close.length);
            // MarkdownBody caches by data. Include the source so a growing
            // formula invalidates that cache even when its span index is stable.
            out.write(
                '$marker${spans.length}:${raw.codeUnits.join('-')}$marker');
            spans.add(
                AgentMathSpan(raw, tex.trim(), open != r'$' && open != r'\('));
            i = end + close.length;
            continue;
          }
        }
        if (open.startsWith('\\')) {
          // Markdown otherwise eats the slash of an unfinished explicit opener.
          out.write('\\');
        }
      } else if (source[i] == '\\' && i + 1 < source.length) {
        out.write(source.substring(i, i + 2));
        i += 2;
        continue;
      }
      out.write(source[i++]);
    }
    data = out.toString();
  }

  late final String marker;
  late final String data;
  final List<AgentMathSpan> spans = [];

  static bool _escaped(String source, int position) {
    var slashes = 0;
    while (position > 0 && source[--position] == '\\') {
      slashes++;
    }
    return slashes.isOdd;
  }

  static bool _isDollarMath(String tex) {
    tex = tex.trim();
    if (tex.isEmpty || tex.contains('\n') || tex.contains('`')) {
      return false;
    }
    // A number alone is currency. Numeric math must be a complete arithmetic
    // expression, never prose between two dollar amounts or an unfinished sum.
    if (RegExp(r'^[\d.,+-]').hasMatch(tex)) {
      return RegExp(
              r'^-?\d+(?:\.\d+)?(?:\s*[+*/=^-]\s*-?\d+(?:\.\d+)?)+(?:\\%)?$')
          .hasMatch(tex);
    }
    final hasCommand = RegExp(r'\\[a-zA-Z]+').hasMatch(tex);
    // TeX can contain Chinese labels (including \text{}), but ordinary Chinese
    // prose between amounts is not an equation.
    if (RegExp(r'[^\x00-\x7F]').hasMatch(tex) &&
        (!hasCommand || RegExp(r'[，。！？；]').hasMatch(tex))) {
      return false;
    }
    return hasCommand ||
        RegExp(r'[=^_+*/<>-]').hasMatch(tex) ||
        RegExp(r'^[a-zA-Z]$').hasMatch(tex);
  }
}
