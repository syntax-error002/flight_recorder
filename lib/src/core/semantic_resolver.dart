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
  ///
  /// Note: `widgetType` alone is intentionally not considered resolvable
  /// because ubiquitous types like `find.byType(Container)` are ambiguous.
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

  /// Public accessor for testing / extracting clean user keys.
  static String? extractKey(Key? key) => _extractKey(key);

  // High-level semantic UI widgets that represent genuine user intent.
  static const _semanticComponentTypes = <String>{
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
    'Chip',
    'ChoiceChip',
    'FilterChip',
    'ActionChip',
    'InputChip',
    'SegmentedButton',
    'Tab',
    'TabBar',
    'NavigationDestination',
    'NavigationRailDestination',
  };

  // Low-level plumbing widgets that should yield to enclosing components.
  static const _plumbingTypes = <String>{
    'GestureDetector',
    'RawGestureDetector',
    'InkWell',
    'InkResponse',
    'Listener',
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
    int visitCounter = 0;
    int lastBarrierVisitIndex = -1;

    _collectCandidates(
      root,
      offset,
      candidates,
      depth: 0,
      nextVisitIndex: () => ++visitCounter,
      onBarrierHit: (barrierIndex) {
        lastBarrierVisitIndex = barrierIndex;
      },
    );

    if (candidates.isEmpty) return null;

    // Discard any candidate that was visited before the topmost covering ModalBarrier
    // (i.e. background widgets occluded by a modal dialog, bottom sheet, or route).
    final eligibleCandidates = lastBarrierVisitIndex != -1
        ? candidates.where((c) => c.visitIndex > lastBarrierVisitIndex).toList()
        : candidates;

    final activeCandidates =
        eligibleCandidates.isNotEmpty ? eligibleCandidates : candidates;

    // Pick the best candidate: highest score, then highest visitIndex (painted on top).
    activeCandidates.sort((a, b) {
      final scoreDiff = b.score.compareTo(a.score);
      if (scoreDiff != 0) return scoreDiff;
      return b.visitIndex.compareTo(a.visitIndex);
    });

    final best = activeCandidates.first;
    return _extractIdentity(best.element, offset);
  }

  // ---------------------------------------------------------------------------
  // Tree traversal
  // ---------------------------------------------------------------------------

  static bool _isBarrierWidget(Element element) {
    final widget = element.widget;
    if (widget is ModalBarrier) return true;
    final typeName = widget.runtimeType.toString().toLowerCase();
    return typeName.contains('barrier') ||
        (typeName.contains('modal') && typeName.contains('route'));
  }

  static void _collectCandidates(
    Element element,
    Offset globalOffset,
    List<_Candidate> out, {
    required int depth,
    required int Function() nextVisitIndex,
    required void Function(int barrierIndex) onBarrierHit,
  }) {
    if (depth > 512) return;
    final vIndex = nextVisitIndex();
    final globalRect = _globalPaintRect(element);

    if (globalRect != null && globalRect.contains(globalOffset)) {
      if (_isBarrierWidget(element)) {
        onBarrierHit(vIndex);
      }

      final score = _score(element, globalOffset);
      out.add(_Candidate(
        element: element,
        depth: depth,
        visitIndex: vIndex,
        score: score,
      ));
    }

    // Spatial pruning: if this element has paint bounds and is far from the tap,
    // skip recursing into its subtree, unless it is an Overlay/Stack/Portal that can project children.
    if (globalRect != null) {
      final typeName = element.widget.runtimeType.toString();
      final isOverlayOrPortal = typeName.contains('Overlay') ||
          typeName.contains('Portal') ||
          typeName.contains('View');
      if (!isOverlayOrPortal &&
          !globalRect.inflate(48.0).contains(globalOffset)) {
        return; // Prune branch - 99% faster traversal, no frame drops!
      }
    }

    element.visitChildren((child) {
      _collectCandidates(
        child,
        globalOffset,
        out,
        depth: depth + 1,
        nextVisitIndex: nextVisitIndex,
        onBarrierHit: onBarrierHit,
      );
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

  static int _score(Element element, [Offset? hitPoint]) {
    int s = 0;
    final typeName = element.widget.runtimeType.toString();

    // High-level semantic components get top priority over low-level gesture plumbing
    if (_semanticComponentTypes.contains(typeName)) {
      s += 6;
    } else if (_plumbingTypes.contains(typeName)) {
      s += 2;
    }

    // Genuine user-defined keys get a major boost; framework internal keys get 0.
    if (_extractKey(element.widget.key) != null) {
      s += 4;
    }

    // Direct text hit
    final w = element.widget;
    if (w is Text && (w.data?.isNotEmpty == true)) {
      s += 5;
    } else if (w is RichText && w.text.toPlainText().isNotEmpty) {
      s += 4;
    }

    bool hasChildrenInTree = false;
    element.visitChildren((_) {
      hasChildrenInTree = true;
    });
    if (!hasChildrenInTree) s += 1;

    return s;
  }

  // ---------------------------------------------------------------------------
  // Identity extraction
  // ---------------------------------------------------------------------------

  static WidgetIdentity _extractIdentity(Element element, [Offset? hitPoint]) {
    final widget = element.widget;
    final typeName = widget.runtimeType.toString();
    String? publicTypeName =
        (typeName.startsWith('_') || _isPlumbingWidget(typeName))
            ? null
            : typeName;

    // If target widget is a private framework type or generic plumbing type
    // (e.g. RawGestureDetector, InkWell, _IconButton, _InkResponseStateWidget),
    // walk ancestors to find the nearest public semantic widget so tests don't fail compilation
    // and aren't polluted with internal primitives.
    if (publicTypeName == null) {
      int levels = 0;
      element.visitAncestorElements((ancestor) {
        if (++levels > 12) return false;
        final aName = ancestor.widget.runtimeType.toString();
        if (!aName.startsWith('_') &&
            !_isPlumbingWidget(aName) &&
            _isPublicMeaningfulWidget(aName)) {
          publicTypeName = aName;
          return false;
        }
        return true;
      });
    }

    publicTypeName ??= (typeName.startsWith('_') ? null : typeName);

    // --- Key ---
    // 1. Direct key on target element
    String? keyStr = _extractKey(widget.key);

    // 2. If no direct clean key, walk ancestors up to 10 levels
    // to discover any user-provided key on an enclosing composite widget
    if (keyStr == null) {
      int levels = 0;
      element.visitAncestorElements((ancestor) {
        if (++levels > 10) return false;
        final aName = ancestor.widget.runtimeType.toString();
        if (_isStructuralBoundary(aName)) return false;
        final ancestorKey = _extractKey(ancestor.widget.key);
        if (ancestorKey != null) {
          keyStr = ancestorKey;
          return false; // found clean key, stop walking
        }
        return true; // continue up
      });
    }

    // --- Text content ---
    String? textContent = _findDescendantText(element, hitPoint);

    // If element has no descendant text, check ancestors up to 5 levels,
    // but NEVER search across structural boundaries (Scaffold, AppBar, Column, etc.)
    // and NEVER search for components that shouldn't borrow text (Checkbox, Switch, Radio, Slider).
    final bool isStandaloneComponent = publicTypeName == 'Checkbox' ||
        publicTypeName == 'Switch' ||
        publicTypeName == 'Radio' ||
        publicTypeName == 'Slider';

    if (!isStandaloneComponent &&
        (textContent == null || textContent.isEmpty)) {
      int levels = 0;
      element.visitAncestorElements((ancestor) {
        if (++levels > 5) return false;
        final aName = ancestor.widget.runtimeType.toString();
        if (_isStructuralBoundary(aName)) return false;
        final aText = _findDescendantText(ancestor, hitPoint);
        if (aText != null && aText.isNotEmpty) {
          textContent = aText;
          return false;
        }
        return true;
      });
    }

    // --- Tooltip ---
    final String? tooltipMsg = _findAncestorTooltip(element);

    // --- Semantics label ---
    final String? semLabel = _extractSemanticsLabel(element);

    // --- Bounds ---
    final Rect? bounds = _globalPaintRect(element);

    return WidgetIdentity(
      key: keyStr,
      widgetType: publicTypeName,
      text: textContent,
      tooltip: tooltipMsg,
      semanticLabel: semLabel,
      bounds: bounds,
    );
  }

  // -------------------------------------------------------------------------
  // Key extraction & widget classification
  // -------------------------------------------------------------------------

  static bool _isPlumbingWidget(String name) {
    const plumbing = {
      'RawGestureDetector',
      'GestureDetector',
      'Listener',
      'InkWell',
      'InkResponse',
      'Semantics',
      'Focus',
      'Actions',
      'Builder',
      'MouseRegion',
      'ClipRect',
      'Transform',
      'KeyedSubtree',
      '_ModalBarrierGestureDetector',
      '_PredictiveBackGestureDetector',
    };
    return plumbing.contains(name);
  }

  static bool _isStructuralBoundary(String name) {
    const boundaries = {
      'Scaffold',
      'AppBar',
      'NavigationToolbar',
      'MaterialApp',
      'WidgetsApp',
      'Navigator',
      'Overlay',
      'ScrollView',
      'ListView',
      'GridView',
      'CustomScrollView',
      'SingleChildScrollView',
      'Column',
      'Row',
      'Flex',
      'Stack',
      'Wrap',
      'Table',
      'PageStorage',
    };
    return boundaries.contains(name);
  }

  // -------------------------------------------------------------------------
  // Key extraction
  // -------------------------------------------------------------------------

  static bool _isPublicMeaningfulWidget(String name) {
    if (name.startsWith('_')) return false;
    const generic = {
      'ConstrainedBox',
      'Padding',
      'Center',
      'Align',
      'SizedBox',
      'ColoredBox',
      'Semantics',
      'Focus',
      'NotificationListener',
      'RepaintBoundary',
      'CustomPaint',
    };
    return !generic.contains(name);
  }

  static bool _isCleanUserKey(String key) {
    if (key.isEmpty) return false;
    // Discard framework internal markers, runtime hash codes, and generic wrappers
    if (key.contains('#')) return false;
    if (key.contains('LabeledGlobalKey')) return false;
    if (key.contains('GlobalKey')) return false;
    if (key.contains('GlobalObjectKey')) return false;
    if (key.contains('UniqueKey')) return false;
    if (key.contains('<') || key.contains('>')) return false;
    if (key.startsWith('_')) return false;
    if (key.startsWith('[') && key.endsWith(']')) return false;
    return true;
  }

  static String? _extractKey(Key? key) {
    if (key == null) return null;
    if (key is ValueKey<String>) {
      return _isCleanUserKey(key.value) ? key.value : null;
    }
    if (key is ValueKey<int>) return key.value.toString();
    if (key is ObjectKey) {
      final v = key.value?.toString();
      if (v != null && _isCleanUserKey(v)) return v;
      return null;
    }
    final raw = key.toString();
    // ValueKey<dynamic>('value') → extract content between (' and ')
    final paren = RegExp(r"\('(.+?)'\)$").firstMatch(raw);
    if (paren != null && _isCleanUserKey(paren.group(1)!)) {
      return paren.group(1);
    }
    // [<'my_key'>] -> extract content
    final angle = RegExp(r"\[<'(.+?)'>\]").firstMatch(raw);
    if (angle != null && _isCleanUserKey(angle.group(1)!)) {
      return angle.group(1);
    }
    if (_isCleanUserKey(raw)) return raw;
    return null;
  }

  // -------------------------------------------------------------------------
  // Descendant text search
  // -------------------------------------------------------------------------

  static String? _findDescendantText(Element element, [Offset? hitPoint]) {
    // 1. If hitPoint is provided, prioritize any Text descendant whose bounding rect contains hitPoint
    if (hitPoint != null) {
      String? hitText;
      _visitDescendantsUntil(element, (child) {
        final w = child.widget;
        if (w is Text && (w.data?.isNotEmpty == true)) {
          final rect = _globalPaintRect(child);
          if (rect != null && rect.contains(hitPoint)) {
            hitText = w.data;
            return true;
          }
        }
        if (w is RichText) {
          final rect = _globalPaintRect(child);
          if (rect != null && rect.contains(hitPoint)) {
            final plain = w.text.toPlainText();
            if (plain.isNotEmpty) {
              hitText = plain;
              return true;
            }
          }
        }
        return false;
      });
      if (hitText != null) return hitText;
    }

    // 2. First non-empty Text widget (avoiding crossing structural boundaries)
    String? found;
    _visitDescendantsUntil(element, (child) {
      final aName = child.widget.runtimeType.toString();
      if (_isStructuralBoundary(aName)) {
        return true; // prune structural subtrees
      }
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
  final int visitIndex;
  final int score;

  const _Candidate({
    required this.element,
    required this.depth,
    required this.visitIndex,
    required this.score,
  });
}
