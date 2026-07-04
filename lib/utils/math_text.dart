/// Converts LaTeX-ish math notation from AI-generated text into plain
/// readable Unicode.
///
/// The lecture summary (and occasionally narration) comes from an LLM that
/// tends to write formulas as LaTeX — `\( f(x) = 0 \)`, `\frac{a}{b}`,
/// `x^{2}` — which the app shows verbatim and unreadable. There is no LaTeX
/// renderer in the app (and pulling one in for a summary screen is overkill),
/// so instead we degrade the notation gracefully: `x²`, `a/b`, `√x`, `π`.
/// Anything unrecognized is left untouched.
library;

const Map<String, String> _symbols = {
  'cdot': '·', 'times': '×', 'div': '÷', 'pm': '±', 'mp': '∓',
  'le': '≤', 'leq': '≤', 'ge': '≥', 'geq': '≥', 'ne': '≠', 'neq': '≠',
  'approx': '≈', 'equiv': '≡', 'propto': '∝',
  'infty': '∞', 'partial': '∂', 'nabla': '∇', 'degree': '°',
  'sum': 'Σ', 'prod': 'Π', 'int': '∫',
  'rightarrow': '→', 'to': '→', 'leftarrow': '←',
  'Rightarrow': '⇒', 'Leftarrow': '⇐', 'Leftrightarrow': '⇔',
  'in': '∈', 'notin': '∉', 'subset': '⊂', 'subseteq': '⊆',
  'cup': '∪', 'cap': '∩', 'emptyset': '∅', 'varnothing': '∅',
  'forall': '∀', 'exists': '∃', 'neg': '¬', 'land': '∧', 'lor': '∨',
  'alpha': 'α', 'beta': 'β', 'gamma': 'γ', 'delta': 'δ',
  'epsilon': 'ε', 'varepsilon': 'ε', 'zeta': 'ζ', 'eta': 'η',
  'theta': 'θ', 'vartheta': 'θ', 'iota': 'ι', 'kappa': 'κ',
  'lambda': 'λ', 'mu': 'μ', 'nu': 'ν', 'xi': 'ξ', 'pi': 'π',
  'rho': 'ρ', 'sigma': 'σ', 'tau': 'τ', 'upsilon': 'υ',
  'phi': 'φ', 'varphi': 'φ', 'chi': 'χ', 'psi': 'ψ', 'omega': 'ω',
  'Gamma': 'Γ', 'Delta': 'Δ', 'Theta': 'Θ', 'Lambda': 'Λ',
  'Xi': 'Ξ', 'Pi': 'Π', 'Sigma': 'Σ', 'Upsilon': 'Υ',
  'Phi': 'Φ', 'Psi': 'Ψ', 'Omega': 'Ω',
};

const Map<String, String> _superscript = {
  '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴',
  '5': '⁵', '6': '⁶', '7': '⁷', '8': '⁸', '9': '⁹',
  '+': '⁺', '-': '⁻', '=': '⁼', '(': '⁽', ')': '⁾', 'n': 'ⁿ', 'i': 'ⁱ',
};

const Map<String, String> _subscript = {
  '0': '₀', '1': '₁', '2': '₂', '3': '₃', '4': '₄',
  '5': '₅', '6': '₆', '7': '₇', '8': '₈', '9': '₉',
  '+': '₊', '-': '₋', '=': '₌', '(': '₍', ')': '₎',
  'n': 'ₙ', 'i': 'ᵢ', 'k': 'ₖ', 'm': 'ₘ', 'x': 'ₓ',
};

/// Maps every char of [v] through [table]; returns null if any char is not
/// mappable, so the caller can fall back instead of producing a half-converted
/// mess like "lecture₁0".
String? _mapAll(String v, Map<String, String> table) {
  final out = StringBuffer();
  for (final c in v.split('')) {
    final mapped = table[c];
    if (mapped == null) return null;
    out.write(mapped);
  }
  return out.toString();
}

bool _looksLikeMath(String s) =>
    RegExp(r'[=^_\\<>≤≥]|[a-zA-Z]\s*[+\-*/]\s*[a-zA-Z0-9]').hasMatch(s);

String cleanMathText(String text) {
  var s = text;

  // Delimiters: \( ... \), \[ ... \], $$ ... $$ — always math, unwrap.
  s = s.replaceAllMapped(
      RegExp(r'\\[\(\[]\s*(.*?)\s*\\[\)\]]', dotAll: true), (m) => m.group(1)!);
  s = s.replaceAllMapped(
      RegExp(r'\$\$\s*(.*?)\s*\$\$', dotAll: true), (m) => m.group(1)!);
  // Single $...$ only when the content looks like a formula — keeps literal
  // dollar amounts ("$100 и $200") intact.
  s = s.replaceAllMapped(RegExp(r'\$([^\$\n]{1,80}?)\$'), (m) {
    final inner = m.group(1)!;
    return _looksLikeMath(inner) ? inner : m.group(0)!;
  });

  // \frac{a}{b} → a/b; repeat a few times so nested fractions unwrap
  // inside-out (inner groups contain no braces on the first pass).
  final frac = RegExp(r'\\[dt]?frac\{([^{}]*)\}\{([^{}]*)\}');
  for (var i = 0; i < 3 && s.contains(frac); i++) {
    s = s.replaceAllMapped(frac, (m) {
      String wrap(String x) =>
          RegExp(r'^[\w.,²³⁴⁻⁺]+$').hasMatch(x) ? x : '($x)';
      return '${wrap(m.group(1)!.trim())}/${wrap(m.group(2)!.trim())}';
    });
  }

  s = s.replaceAllMapped(RegExp(r'\\sqrt\s*\{([^{}]*)\}'), (m) {
    final v = m.group(1)!.trim();
    return RegExp(r'^\w+$').hasMatch(v) ? '√$v' : '√($v)';
  });

  // Wrappers that only change styling — keep the content.
  s = s.replaceAllMapped(
      RegExp(r'\\(?:text|textbf|textit|mathrm|mathbf|mathit|operatorname)\{([^{}]*)\}'),
      (m) => m.group(1)!);
  s = s.replaceAll(RegExp(r'\\left\s*'), '').replaceAll(RegExp(r'\\right\s*'), '');

  // Symbol commands (\pi, \le, …). Unknown commands are left as-is.
  s = s.replaceAllMapped(
      RegExp(r'\\([a-zA-Z]+)'), (m) => _symbols[m.group(1)!] ?? m.group(0)!);

  // Superscripts/subscripts. Fully mappable → Unicode; otherwise a readable
  // ^(…)/_(…) fallback for braced groups, untouched for bare ones (so
  // ordinary snake_case words never get mangled).
  s = s.replaceAllMapped(RegExp(r'\^\{([^{}]*)\}'),
      (m) => _mapAll(m.group(1)!, _superscript) ?? '^(${m.group(1)!})');
  s = s.replaceAllMapped(RegExp(r'\^(\w+)'),
      (m) => _mapAll(m.group(1)!, _superscript) ?? m.group(0)!);
  s = s.replaceAllMapped(RegExp(r'_\{([^{}]*)\}'),
      (m) => _mapAll(m.group(1)!, _subscript) ?? '_(${m.group(1)!})');
  s = s.replaceAllMapped(RegExp(r'_(\w+)'),
      (m) => _mapAll(m.group(1)!, _subscript) ?? m.group(0)!);

  // LaTeX spacing commands → plain space.
  s = s.replaceAll(RegExp(r'\\[,;:!]'), ' ');

  return s;
}
