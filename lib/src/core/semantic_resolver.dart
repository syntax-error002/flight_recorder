// ignore_for_file: invalid_use_of_protected_member

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

// ---------------------------------------------------------------------------
// WidgetIdentity
// ---------------------------------------------------------------------------

/// Metadata describing the identity of a widget found via a hit-test.
///
/// Used by [SemanticResolver] to produce human-readable, finder-ready
/// descriptions that can be turned into Flutter widget-test finder
/// expressions.
class WidgetIdentity {
  /// String representation of the widget's [Key] (e.g. `'submit_btn'` from a
  /// `ValueKey<String>('submit_btn')`), or `null` if the widget had no key.
  final String? key;

  /// Runtime type name of the matched widget (e.g. `'ElevatedButton'`).
  final String? widgetType;

  /// Text content of the nearest descendant [Text] widget, if any.
  final String? text;

  /// The [Tooltip.message] string if the widget is wrapped in a [Tooltip].
  final String? tooltip;

  /// The [SemanticsNode.label] from the nearest semantics node, if any.
  final String? semanticLabel;

  /// Screen-space bounding box of the matched render object.
  final Rect? bounds;

  const WidgetIdentity({
    this.key,
    this.widgetType,
    this.text,
    this.tooltip,
    this.semanticLabel,
    this.bounds,
  });

  // -------------------------------------------------------------------------
  // Serialization
  // -------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
        'key': key,
        'widgetType': widgetType,
        'text': text,
        'tooltip': tooltip,
        'semanticLabel': semanticLabel,
        'bounds': bounds == null
            ? null
            : {
                'left': bounds!.left,
                'top': bounds!.top,
                'right': bounds!.right,
                'bottom': bounds!.bottom,
              },
      };

  factory WidgetIdentity.fromJson(Map<String, dynamic> json) {
    final b = json['bounds'] as Map<String, dynamic>?;
    return WidgetIdentity(
      key: json['key'] as String?,
      widgetType: json['widgetType'] as String?,
      text: json['text'] as String?,
      tooltip: json['tooltip'] as String?,
      semanticLabel: json['semanticLabel'] as String?,
      bounds: b == null
          ? null
          : Rect.fromLTRB(
              (b['left'] as num).toDouble(),
              (b['top'] as num).toDouble(),
              (b['right'] as num).toDouble(),
              (b['bottom'] as num).toDouble(),
            ),
    );
  }

  // -------------------------------------------------------------------------
  // Finder generation
  // -------------------------------------------------------------------------

  /// Whether there is enough information to generate a semantic finder
  /// (i.e. something other than a raw absolute-offset fallback).
  bool get isResolvable =>
      key != null || text != null || tooltip != null || semanticLabel != null;

  /// Returns the best Flutter test finder expression for this identity.
  ///
  /// Priority order:
  ///   1. `find.byKey(const Key('...'))`
  ///   2. `find.text('...')`
  ///   3. `find.byTooltip('...')`
  ///   4. `find.bySemanticsLabel('...')`
  ///   5. `find.byType(WidgetType)` — when only the type is known
  ///   6. `find.hitTestable()` offset fallback: `tester.tapAt(Offset(x, y))`
  ///
  /// The [fallbackDx] / [fallbackDy] are used only for case 6.
  String toFinderExpression(double fallbackDx, double fallbackDy) {
    if (key != null) {
      return "find.byKey(const Key('${_escapeSingleQuotes(key!)}'))";
    }
    if (text != null) {
      return "find.text('${_escapeSingleQuotes(text!)}')";
    }
    if (tooltip != null) {
      return "find.byTooltip('${_escapeSingleQuotes(tooltip!)}')";
    }
    if (semanticLabel != null) {
      return "find.bySemanticsLabel('${_escapeSingleQuotes(semanticLabel!)}')";
    }
    if (widgetType != null) {
      return 'find.byType($widgetType)';
    }
    // Last resort – raw coordinates
    return 'tester.tapAt(const Offset(${fallbackDx.toStringAsFixed(1)}, ${fallbackDy.toStringAsFixed(1)}))';
  }

  static String _escapeSingleQuotes(String s) => s.replaceAll("'", r"\'");

  @override
  String toString() => 'WidgetIdentity('
      'key: $key, '
      'type: $widgetType, '
      'text: $text, '
      'tooltip: $tooltip, '
      'semanticLabel: $semanticLabel, '
      'bounds: $bounds)';
}

// ---------------------------------------------------------------------------
// SemanticResolver
// ---------------------------------------------------------------------------

/// A production-grade hit-test resolver that, given an [Offset] on screen,
/// walks the Flutter render/element tree to find the best-matching widget
/// identity (Key, Type, Text, Tooltip, Semantic label).
///
/// ## Algorithm
///
/// 1. Starts from `WidgetsBinding.instance.renderViewElement` as the root.
/// 2. Walks the element tree depth-first collecting **all** elements whose
///    render-object paint bounds, transformed to global (screen) coordinates,
///    contain [offset].
/// 3. Scores each candidate:
///    - Leaves (no matching-child) get +2.
///    - Interactive widgets (GestureDetector, InkWell, ButtonStyleButton and
///      its subclasses, CupertinoButton, IconButton, TextButton, etc.) get +3.
///    - Widgets with an explicit [Key] get +1.
/// 4. The highest-scoring candidate (depth used as tiebreak) is selected.
/// 5. Identity metadata is extracted:
///    - [WidgetIdentity.key] from `element.widget.key`
///    - [WidgetIdentity.widgetType] from `element.widget.runtimeType`
///    - [WidgetIdentity.text] by walking descendants for a [Text] widget
///    - [WidgetIdentity.tooltip] by walking ancestors for a [Tooltip] widget
///    - [WidgetIdentity.semanticLabel] from `renderObject.debugSemantics`
class SemanticResolver {
  SemanticResolver._();

  // Widget runtime-type names considered "interactive".
  static const _interactiveTypes = <String>{
    'GestureDetector',
    'InkWell',
    'InkResponse',
    'RawGestureDetector',
    'ElevatedButton',
    'TextButton',
    'OutlinedButton',
    'FilledButton',
    'IconButton',
    'FloatingActionButton',
    'CupertinoButton',
    'PopupMenuButton',
    'DropdownButton',
    'Switch',
    'Checkbox',
    'Radio',
    'Slider',
    'RangeSlider',
    'ListTile',
    'CheckboxListTile',
    'SwitchListTile',
    'RadioListTile',
    'SelectableText',
    'TextField',
    'CupertinoTextField',
  };

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Performs a hit-test at [offset] in the given [BuildContext] render tree
  /// and returns the best-matching [WidgetIdentity], or `null` if nothing
  /// was found.
  ///
  /// [context] is optional; when omitted the resolver falls back to
  /// `WidgetsBinding.instance.renderViewElement` as the traversal root.
  static WidgetIdentity? resolve(Offset offset, BuildContext? context) {
    // Obtain the root element to start traversal from.
    Element? root;
    if (context != null && context is Element) {
      root = context;
    } else {
      root = WidgetsBinding.instance.rootElement;
    }
    if (root == null) return null;

    // Collect all candidates that contain the offset.
    final candidates = <_Candidate>[];
    _collectCandidates(root, offset, candidates, depth: 0);

    if (candidates.isEmpty) return null;

    // Pick the best candidate: highest score, then deepest depth.
    candidates.sort((a, b) {
      final scoreDiff = b.score.compareTo(a.score);
      if (scoreDiff != 0) return scoreDiff;
      return b.depth.compareTo(a.depth);
    });

    final best = candidates.first;
    return _extractIdentity(best.element);
  }

  // ---------------------------------------------------------------------------
  // Tree traversal
  // ---------------------------------------------------------------------------

  static void _collectCandidates(
    Element element,
    Offset globalOffset,
    List<_Candidate> out, {
    required int depth,
  }) {
    final globalRect = _globalPaintRect(element);

    // Check containment only when we have a valid, non-empty rect.
    if (globalRect != null && globalRect.contains(globalOffset)) {
      final score = _score(element);
      out.add(_Candidate(element: element, depth: depth, score: score));
    }

    // Always recurse: a child may be positioned outside its parent's clip.
    element.visitChildren((child) {
      _collectCandidates(child, globalOffset, out, depth: depth + 1);
    });
  }

  /// Transforms the render object's local paint bounds to global (screen)
  /// coordinates by walking the render-object ancestor chain.
  static Rect? _globalPaintRect(Element element) {
    final ro = element.renderObject;
    if (ro == null) return null;
    if (!ro.attached) return null;

    try {
      // Obtain the transform from this render object to the root coordinate
      // system (screen space).
      final matrix = ro.getTransformTo(null);
      final localRect = ro.paintBounds;
      if (localRect.isEmpty) return null;
      return MatrixUtils.transformRect(matrix, localRect);
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Scoring
  // ---------------------------------------------------------------------------

  static int _score(Element element) {
    int s = 0;
    final typeName = element.widget.runtimeType.toString();

    if (_interactiveTypes.contains(typeName)) s += 3;
    if (element.widget.key != null) s += 1;

    // Leaf elements (no children with matching bounds, but we score based on
    // whether this element has any child render-object at all – a cheap proxy).
    bool hasChildrenInTree = false;
    element.visitChildren((_) {
      hasChildrenInTree = true;
    });
    if (!hasChildrenInTree) s += 2;

    return s;
  }

  // ---------------------------------------------------------------------------
  // Identity extraction
  // ---------------------------------------------------------------------------

  static WidgetIdentity _extractIdentity(Element element) {
    final widget = element.widget;
    final typeName = widget.runtimeType.toString();

    // --- Key ---
    final String? keyStr = _extractKey(widget.key);

    // --- Text content ---
    final String? textContent = _findDescendantText(element);

    // --- Tooltip ---
    final String? tooltipMsg = _findAncestorTooltip(element);

    // --- Semantics label ---
    final String? semLabel = _extractSemanticsLabel(element);

    // --- Bounds ---
    final Rect? bounds = _globalPaintRect(element);

    return WidgetIdentity(
      key: keyStr,
      widgetType: typeName,
      text: textContent,
      tooltip: tooltipMsg,
      semanticLabel: semLabel,
      bounds: bounds,
    );
  }

  // -------------------------------------------------------------------------
  // Key extraction
  // -------------------------------------------------------------------------

  static String? _extractKey(Key? key) {
    if (key == null) return null;
    if (key is ValueKey<String>) return key.value;
    if (key is ValueKey<int>) return key.value.toString();
    if (key is ObjectKey) {
      final v = key.value;
      if (v != null) return v.toString();
      return null;
    }
    // LabeledGlobalKey / GlobalKey – strip the angle-bracket suffix that
    // appears in debugLabels like "[<'my_key'>]".
    final raw = key.toString();
    // ValueKey<dynamic>('value') → extract content between ( and )
    final paren = RegExp(r"\('(.+?)'\)$").firstMatch(raw);
    if (paren != null) return paren.group(1);
    // Fallback: return raw only when it looks meaningful.
    if (raw.contains("'") || raw.length < 64) return raw;
    return null;
  }

  // -------------------------------------------------------------------------
  // Descendant text search
  // -------------------------------------------------------------------------

  static String? _findDescendantText(Element element) {
    String? found;
    _visitDescendantsUntil(element, (child) {
      final w = child.widget;
      if (w is Text && (w.data?.isNotEmpty == true)) {
        found = w.data;
        return true; // stop
      }
      if (w is RichText) {
        final plain = w.text.toPlainText();
        if (plain.isNotEmpty) {
          found = plain;
          return true;
        }
      }
      return false;
    });
    return found;
  }

  /// Visits descendants depth-first; stops a branch when [visitor] returns
  /// `true`.
  static void _visitDescendantsUntil(
    Element element,
    bool Function(Element) visitor,
  ) {
    element.visitChildren((child) {
      if (!visitor(child)) {
        _visitDescendantsUntil(child, visitor);
      }
    });
  }

  // -------------------------------------------------------------------------
  // Ancestor tooltip search
  // -------------------------------------------------------------------------

  static String? _findAncestorTooltip(Element element) {
    String? found;
    // Walk up the ancestor chain looking for a Tooltip widget.
    element.visitAncestorElements((ancestor) {
      if (ancestor.widget is Tooltip) {
        found = (ancestor.widget as Tooltip).message;
        return false; // stop
      }
      return true; // continue
    });
    return found;
  }

  // -------------------------------------------------------------------------
  // Semantics label extraction
  // -------------------------------------------------------------------------

  static String? _extractSemanticsLabel(Element element) {
    final ro = element.renderObject;
    if (ro == null) return null;

    // debugSemantics is only populated in debug mode.
    if (!kDebugMode) {
      // In profile / release, try a quick SemanticsNode walk instead.
      return _extractSemanticsLabelFromOwner(ro);
    }

    try {
      final node = ro.debugSemantics;
      if (node == null) return null;
      final label = node.label;
      return label.isEmpty ? null : label;
    } catch (_) {
      return null;
    }
  }

  static String? _extractSemanticsLabelFromOwner(RenderObject ro) {
    // Best-effort in non-debug mode: walk the semantics owner's node map.
    try {
      final owner = ro.owner;
      if (owner == null) return null;
      final semanticsOwner = owner.semanticsOwner;
      if (semanticsOwner == null) return null;
      // We cannot easily map a RenderObject to its SemanticsNode without
      // debug helpers outside debug mode, so we return null gracefully.
      return null;
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

class _Candidate {
  final Element element;
  final int depth;
  final int score;

  const _Candidate({
    required this.element,
    required this.depth,
    required this.score,
  });
}
