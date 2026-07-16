// Masking primitives for the session-replay capture path.
//
// Two modes (see [MaskMode]):
// - **blocklist** (default): a captured frame records in the clear EXCEPT the
//   always-on floor (obscured/password fields), anything wrapped in
//   [ScrywatchMask], and any configured [MaskRule] match. Record-everything
//   by default; you opt into masking specific things.
// - **strict**: the frame is fully occluded with solid `kMaskColor` blocks
//   EXCEPT subtrees wrapped in [ScrywatchReveal]. For HIPAA/PCI-grade projects.
//
// In BOTH modes, anything wrapped in [ScrywatchMask], and any `obscureText`
// (password) field, is force-masked and can never be revealed — even if it
// sits inside a [ScrywatchReveal] subtree.
//
// Masking is applied as a POST-CAPTURE pass over the captured bitmap (see
// [maskImage]) — the raw frame is captured first, then occlusion is painted
// onto the image before encode/upload. The live UI is never masked (a
// shipping SDK must not black out the customer's own screen). This is the
// approach Sentry/PostHog use.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Solid occlusion color painted over every non-revealed region of a
/// captured frame. Fully opaque so it is never blended with what's under
/// it — what you see is exactly this color, pixel for pixel.
const Color kMaskColor = Color(0xFF1A1A1A);

/// The 0xRRGGBB value of [kMaskColor] (alpha stripped), for pixel-level
/// assertions against `ByteData` read back from a captured image.
const int kMaskColorRgb = 0x1A1A1A;

/// Process-wide registry of the [GlobalKey]s that [ScrywatchReveal] and
/// [ScrywatchMask] attach to their child subtrees.
///
/// This is a single process-wide singleton because there is exactly one
/// [maskedRoot] active per app (see `ScrywatchReplay.wrap` in the public
/// entrypoint, which owns the sole boundary key). A host app with multiple
/// independent masked roots is out of scope for this preview release.
class MaskRegistry {
  MaskRegistry._();

  static final MaskRegistry instance = MaskRegistry._();

  final Set<GlobalKey> _revealKeys = <GlobalKey>{};
  final Set<GlobalKey> _maskKeys = <GlobalKey>{};

  /// tag -> the set of [GlobalKey]s currently registered under that tag.
  /// A single tag may be applied to multiple mounted subtrees at once (e.g.
  /// a repeated list item), so this is a set, not a single key.
  final Map<String, Set<GlobalKey>> _taggedKeys = <String, Set<GlobalKey>>{};

  MaskPolicy _policy = const MaskPolicy();

  void registerReveal(GlobalKey key) => _revealKeys.add(key);
  void unregisterReveal(GlobalKey key) => _revealKeys.remove(key);

  void registerMask(GlobalKey key) => _maskKeys.add(key);
  void unregisterMask(GlobalKey key) => _maskKeys.remove(key);

  Set<GlobalKey> get revealKeys => Set<GlobalKey>.unmodifiable(_revealKeys);
  Set<GlobalKey> get maskKeys => Set<GlobalKey>.unmodifiable(_maskKeys);

  /// Registers [key]'s subtree under the given developer-assigned [tag]
  /// (see [ScrywatchTag]). A tag is an opaque string chosen by the app; the
  /// mask policy later resolves it via a [MaskRule] with
  /// `match: MaskMatch.tag`.
  void registerTag(String tag, GlobalKey key) {
    _taggedKeys.putIfAbsent(tag, () => <GlobalKey>{}).add(key);
  }

  /// Unregisters [key] from whichever tag it was registered under. Cheap
  /// enough for the small number of tags a real app has; callers only pay
  /// this cost on widget dispose.
  void unregisterTag(GlobalKey key) {
    for (final Set<GlobalKey> keys in _taggedKeys.values) {
      keys.remove(key);
    }
  }

  /// tag -> currently-mounted keys registered under that tag. Read-only
  /// snapshot; the inner sets are unmodifiable.
  Map<String, Set<GlobalKey>> get taggedKeys => _taggedKeys.map(
        (String tag, Set<GlobalKey> keys) =>
            MapEntry<String, Set<GlobalKey>>(tag, Set<GlobalKey>.unmodifiable(keys)),
      );

  /// The mask policy the compositor resolves against each frame. Defaults to
  /// blocklist mode with no rules (record everything except the always-on
  /// floor). Set via [setPolicy] — in Phase A this is hard-coded by the app
  /// (see `main.dart`); Phase B replaces it with a fetched remote policy.
  MaskPolicy get policy => _policy;

  void setPolicy(MaskPolicy policy) => _policy = policy;
}

/// Per-project masking mode (see the design doc's "Masking model").
enum MaskMode {
  /// DEFAULT. Record everything; mask only elements matched by a
  /// [MaskRule] plus the always-on floor. Best fidelity/adoption.
  blocklist,

  /// Deny-by-default: everything is masked except [ScrywatchReveal]'d
  /// subtrees (and even then, the floor still wins). For HIPAA/PCI-grade
  /// customers.
  strict,
}

/// What a [MaskRule] matches against.
enum MaskMatch {
  /// A developer-assigned [ScrywatchTag] string.
  tag,

  /// A portable widget-type name resolved per-platform; on Flutter see
  /// [widgetTypeMatches] (`'image'`, `'textInput'`, `'webview'`, `'video'`).
  widgetType,

  /// A named PII kind (`'email'`, `'card'`, `'ssn'`, `'phone'`) or a custom
  /// regex matched against visible text content.
  textPattern,
}

/// A single masking rule: "mask everything matched by [match]/[value]".
///
/// Phase A only supports the `mask` action in rules — reveal is always a
/// code-level decision ([ScrywatchReveal]); the dashboard can never reveal
/// something the code didn't already mark eligible (see the design doc's
/// "double-key" direction rule).
class MaskRule {
  const MaskRule({required this.match, required this.value});

  final MaskMatch match;
  final String value;

  /// Tolerantly parses a single rule out of a decoded JSON value (an
  /// element of the remote policy's `rules` array — see
  /// [MaskPolicy.fromJson]). Returns null — rather than throwing — for
  /// anything that isn't a well-formed rule: [json] isn't a `Map`, its
  /// `match` isn't one of the known [MaskMatch] names, or its `value` isn't
  /// a non-empty `String`.
  ///
  /// This is deliberately permissive about DROPPING bad input: one
  /// malformed rule from the dashboard/backend must never take down the
  /// whole policy fetch (which would fall back to the safe default and
  /// could only ever mean MORE masking, never less — see
  /// [MaskPolicy.fromJson]).
  static MaskRule? fromJson(Object? json) {
    if (json is! Map) return null;
    final Object? matchRaw = json['match'];
    final Object? valueRaw = json['value'];
    if (valueRaw is! String || valueRaw.isEmpty) return null;
    final MaskMatch? match = switch (matchRaw) {
      'tag' => MaskMatch.tag,
      'widgetType' => MaskMatch.widgetType,
      'textPattern' => MaskMatch.textPattern,
      _ => null,
    };
    if (match == null) return null;
    return MaskRule(match: match, value: valueRaw);
  }
}

/// The active masking policy: a [mode] plus a list of [rules]. Defaults to
/// blocklist with no rules — i.e. "record everything except the always-on
/// floor" — which is the safe-and-permissive default for adoption.
class MaskPolicy {
  const MaskPolicy({
    this.mode = MaskMode.blocklist,
    this.rules = const <MaskRule>[],
    this.version = 0,
  });

  final MaskMode mode;
  final List<MaskRule> rules;

  /// The remote policy's version number (see the worker's
  /// `replay_mask_policies.version`), for logging/diagnostics. 0 for a
  /// policy that wasn't fetched (the built-in default).
  final int version;

  /// Tolerantly parses a policy out of a decoded JSON object (the body of
  /// `GET /api/replay/policy` — see `ReplayRecorder._fetchAndApplyPolicy`).
  ///
  /// SECURITY: this must never let bad/unexpected input escalate into
  /// *less* masking than the safe default.
  /// - An unknown or missing `mode` falls back to [MaskMode.blocklist] (the
  ///   safe default) rather than throwing.
  /// - Each element of `rules` is parsed independently via
  ///   [MaskRule.fromJson]; any element that fails to parse is DROPPED —
  ///   silently skipped, not substituted with a default — so one bad rule
  ///   can never invalidate the rest of a legitimately-configured policy.
  /// - A missing/non-list `rules` yields no rules (equivalent to the
  ///   built-in default's empty list).
  ///
  /// Never throws.
  factory MaskPolicy.fromJson(Map<String, dynamic> json) {
    final MaskMode mode = switch (json['mode']) {
      'strict' => MaskMode.strict,
      _ => MaskMode.blocklist, // covers 'blocklist', missing, and garbage.
    };

    final List<MaskRule> rules = <MaskRule>[];
    final Object? rawRules = json['rules'];
    if (rawRules is List) {
      for (final Object? rawRule in rawRules) {
        final MaskRule? rule = MaskRule.fromJson(rawRule);
        if (rule != null) rules.add(rule);
      }
    }

    final Object? rawVersion = json['version'];
    final int version = rawVersion is num ? rawVersion.toInt() : 0;

    return MaskPolicy(mode: mode, rules: rules, version: version);
  }
}

/// Marks [child] as eligible AND enabled to be shown through the mask
/// overlay.
///
/// In this release, eligible == enabled (no separate per-reveal policy
/// check). Nothing wrapped in [ScrywatchMask], and no `obscureText` field,
/// can ever be revealed even if it is nested inside a [ScrywatchReveal].
class ScrywatchReveal extends StatefulWidget {
  const ScrywatchReveal({super.key, required this.child});

  final Widget child;

  @override
  State<ScrywatchReveal> createState() => _ScrywatchRevealState();
}

class _ScrywatchRevealState extends State<ScrywatchReveal> {
  final GlobalKey _rectKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    MaskRegistry.instance.registerReveal(_rectKey);
  }

  @override
  void dispose() {
    MaskRegistry.instance.unregisterReveal(_rectKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(key: _rectKey, child: widget.child);
  }
}

/// Force-masks [child]: always occluded, even inside a [ScrywatchReveal].
class ScrywatchMask extends StatefulWidget {
  const ScrywatchMask({super.key, required this.child});

  final Widget child;

  @override
  State<ScrywatchMask> createState() => _ScrywatchMaskState();
}

class _ScrywatchMaskState extends State<ScrywatchMask> {
  final GlobalKey _rectKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    MaskRegistry.instance.registerMask(_rectKey);
  }

  @override
  void dispose() {
    MaskRegistry.instance.unregisterMask(_rectKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(key: _rectKey, child: widget.child);
  }
}

/// Attaches a stable, developer-assigned string [tag] to [child]'s subtree
/// WITHOUT deciding mask/reveal in code — the active [MaskPolicy] decides,
/// via a [MaskRule] with `match: MaskMatch.tag`. This is the primary
/// "selector" mechanism: it lets a dashboard/rule re-decide whether a tagged
/// region is masked without an app release (see the design doc's Layer 1).
///
/// A tag is opaque and flat (no hierarchy/combinators); the same tag may be
/// applied to multiple mounted subtrees at once.
class ScrywatchTag extends StatefulWidget {
  const ScrywatchTag(this.tag, {super.key, required this.child});

  final String tag;
  final Widget child;

  @override
  State<ScrywatchTag> createState() => _ScrywatchTagState();
}

class _ScrywatchTagState extends State<ScrywatchTag> {
  final GlobalKey _rectKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    MaskRegistry.instance.registerTag(widget.tag, _rectKey);
  }

  @override
  void didUpdateWidget(covariant ScrywatchTag oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tag != widget.tag) {
      MaskRegistry.instance.unregisterTag(_rectKey);
      MaskRegistry.instance.registerTag(widget.tag, _rectKey);
    }
  }

  @override
  void dispose() {
    MaskRegistry.instance.unregisterTag(_rectKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(key: _rectKey, child: widget.child);
  }
}

// ---------------------------------------------------------------------------
// PII/surface detectors. These are NO LONGER an always-on floor — the only
// always-on floor is obscured (password) fields (see computeMaskGeometry).
// They now back OPT-IN config rules: `textPattern: email|card|ssn|phone`
// (via [scrywatchIsPii] / the regexes below) and `widgetType: webview|video`
// (via [_isPlatformSurfaceWidget]). A project masks these only if it adds the
// corresponding rule; strict mode masks everything regardless.
// ---------------------------------------------------------------------------

/// Bounded (no nested/overlapping unbounded quantifiers — safe against
/// catastrophic backtracking) regex for a plain email address.
final RegExp _emailPattern = RegExp(
  r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}',
);

/// `123-45-6789`.
final RegExp _ssnPattern = RegExp(r'\b\d{3}-\d{2}-\d{4}\b');

/// A North-American-style phone number: optional country code, optional
/// parens around the area code, then 3+3+4 digits with a single optional
/// space/dash between each group. Bounded — every quantifier has a fixed
/// upper bound.
final RegExp _phonePattern = RegExp(
  r'(?:\+?\d{1,2}[ -]?)?\(?\d{3}\)?[ -]?\d{3}[ -]?\d{4}\b',
);

/// A run of 13-19 digits, optionally separated by single spaces/dashes
/// (typical card/PAN grouping). Candidate matches are Luhn-validated below
/// — this regex alone only bounds the search, it doesn't decide PII-ness.
final RegExp _digitRunPattern = RegExp(r'\d(?:[ -]?\d){12,18}');

/// Standard Luhn checksum. [digits] must be all-ASCII-digit characters.
bool _luhnValid(String digits) {
  if (digits.isEmpty) return false;
  int sum = 0;
  bool alternate = false;
  for (int i = digits.length - 1; i >= 0; i--) {
    int n = digits.codeUnitAt(i) - 0x30;
    if (alternate) {
      n *= 2;
      if (n > 9) n -= 9;
    }
    sum += n;
    alternate = !alternate;
  }
  return sum % 10 == 0;
}

/// True if [text] contains an email address, a Luhn-valid 13-19 digit
/// card/PAN, an SSN (`123-45-6789`), or a phone number. Backs the opt-in
/// `textPattern: card` rule (and, via the regexes above, `email`/`ssn`/
/// `phone`). This is NO LONGER an always-on floor: PII text is only masked in
/// a project that adds the corresponding `textPattern` rule, or in strict mode.
///
/// All patterns are bounded (fixed-width quantifiers, no nested unbounded
/// groups) so this is safe to run per-frame on arbitrary user-authored
/// strings without ReDoS risk.
bool scrywatchIsPii(String text) {
  if (text.isEmpty) return false;
  if (_emailPattern.hasMatch(text)) return true;
  if (_ssnPattern.hasMatch(text)) return true;
  if (_phonePattern.hasMatch(text)) return true;
  for (final RegExpMatch m in _digitRunPattern.allMatches(text)) {
    final String digits = m.group(0)!.replaceAll(RegExp(r'[ -]'), '');
    if (digits.length >= 13 && digits.length <= 19 && _luhnValid(digits)) {
      return true;
    }
  }
  return false;
}

/// True if [widget] is a platform-view or native-texture surface: a
/// WebView, camera/video preview, or any other embedded native view. Backs
/// the opt-in `widgetType: webview` / `video` rules — these are NOT masked by
/// default anymore; a project opts in via config (or wraps them in
/// [ScrywatchMask]) if it wants them occluded.
///
/// Matches the concrete `package:flutter` widgets that platform-view/texture
/// plugins (webview_flutter, camera, video_player, …) are built on, so this
/// is real structural detection, not a name-based heuristic:
/// [Texture] (video/camera frames), [AndroidView]/[AndroidViewSurface]
/// (Android platform views, incl. Android WebView), [UiKitView] (iOS
/// platform views, incl. iOS WKWebView), [PlatformViewSurface] (the
/// platform-agnostic base used by `PlatformViewLink`), and [HtmlElementView]
/// (Flutter web).
bool _isPlatformSurfaceWidget(Widget widget) {
  return widget is Texture ||
      widget is AndroidView ||
      widget is AndroidViewSurface ||
      widget is UiKitView ||
      widget is PlatformViewSurface ||
      widget is HtmlElementView;
}

/// Maps a portable `widgetType` rule value (see [MaskMatch.widgetType] /
/// the design doc's rule language) onto the concrete Flutter widget(s) it
/// selects, for [element]. Used to resolve `{ match: 'widgetType', value:
/// … }` rules — e.g. `'image'` masks every `Image`/`RawImage` with zero code
/// changes.
///
/// | `type`        | Matches                                              |
/// |----------------|-------------------------------------------------------|
/// | `'image'`      | `Image`, `RawImage`                                    |
/// | `'textInput'`  | `EditableText`                                          |
/// | `'webview'`    | any platform-view surface (see [_isPlatformSurfaceWidget]) |
/// | `'video'`      | `Texture`, or any platform-view surface                |
bool widgetTypeMatches(Element element, String type) {
  final Widget widget = element.widget;
  switch (type) {
    case 'image':
      return widget is Image || widget is RawImage;
    case 'textInput':
      return widget is EditableText;
    case 'webview':
      return _isPlatformSurfaceWidget(widget);
    case 'video':
      return widget is Texture || _isPlatformSurfaceWidget(widget);
    default:
      return false;
  }
}

/// The visible string content of [widget], if it's a text-bearing widget
/// this engine knows how to read (`Text`/`Text.rich`, `EditableText`,
/// `RichText`). Returns null for anything else.
///
/// `RichText` is the lower-level widget `Text.rich`/custom gesture-text
/// widgets build down to — without reading it here, text rendered through it
/// would be invisible to `textPattern` rules. [InlineSpan.toPlainText] is a single
/// bounded walk of the (already-built, in-memory) span tree, so this stays
/// cheap enough to run on every element during the per-frame tree walk.
String? _visibleTextOf(Widget widget) {
  if (widget is Text) {
    return widget.data ?? widget.textSpan?.toPlainText();
  }
  if (widget is EditableText) {
    return widget.controller.text;
  }
  if (widget is RichText) {
    return widget.text.toPlainText();
  }
  return null;
}

/// The mask geometry for a single frame, in the capture boundary's LOGICAL
/// coordinate space. Computed at capture time from the mode-aware resolver
/// ([computeMaskGeometry]), then consumed by [maskImage].
class MaskGeometry {
  const MaskGeometry({
    required this.mode,
    required this.revealRects,
    required this.hardMaskRects,
    this.resolutionIncomplete = false,
  });

  /// The policy mode this geometry was resolved under — [maskImage] branches
  /// its compositing strategy on this.
  final MaskMode mode;

  /// Regions explicitly wrapped in [ScrywatchReveal] — in strict mode, the
  /// only regions whose real pixels can survive the mask (still subject to
  /// [hardMaskRects] winning below).
  final List<Rect> revealRects;

  /// Every region that must be masked in EVERY mode and can NEVER be
  /// revealed: the always-on floor (obscured/password fields),
  /// [ScrywatchMask]-wrapped subtrees, and every [MaskRule] match
  /// (tag / widgetType / textPattern) from the active [MaskPolicy]. In
  /// blocklist mode this is the entire occlusion set; in strict mode it is
  /// re-covered after reveal holes are punched, so a reveal can never beat
  /// the floor or a rule.
  final List<Rect> hardMaskRects;

  /// True if ANY key that contributes to [hardMaskRects] — a floor match, a
  /// [ScrywatchMask]-wrapped element, a [ScrywatchTag]-tagged element, or a
  /// [MaskRule] match — was registered/present this frame but its rect could
  /// NOT be resolved (unmounted, mid-relayout, `currentContext == null`, or
  /// an unattached/unsized `RenderBox`). [ScrywatchReveal] resolution
  /// failures do NOT set this — a reveal that fails to resolve just means
  /// less is revealed, which is safe by construction.
  ///
  /// [maskImage] uses this in **blocklist** mode to fail safe: since
  /// blocklist's baseline is the raw frame with only [hardMaskRects]
  /// painted over, a hard-mask rect we failed to resolve would otherwise
  /// ship that region UNMASKED. When this is true, [maskImage] occludes the
  /// ENTIRE frame for the tick instead. Strict mode already masks
  /// everything as its baseline, so this flag doesn't change its behavior.
  final bool resolutionIncomplete;

  static const MaskGeometry empty = MaskGeometry(
    mode: MaskMode.strict,
    revealRects: <Rect>[],
    hardMaskRects: <Rect>[],
  );
}

/// Resolve this frame's mask geometry for the subtree under
/// [boundaryContext], expressed relative to [boundaryBox] — the same
/// coordinate space a `toImage()` capture of that boundary uses. Synchronous;
/// safe to call right before capturing.
///
/// Combines, in one tree walk: the always-on floor (obscured/password fields
/// — see the module doc), [ScrywatchMask] rects, and every
/// [MaskRule] in [MaskRegistry.instance]'s active [MaskPolicy] (`tag` rules
/// resolve via the tag registry; `widgetType`/`textPattern` rules resolve via
/// the same walk). [MaskMode] itself is NOT applied here — that's
/// [maskImage]'s job; this function just resolves rects.
///
/// Never throws: an individual element whose render box can't be resolved
/// this frame is simply skipped for that rect. It does NOT silently vanish
/// from the safety story, though — if the skipped key was contributing to
/// the floor / [ScrywatchMask] / tag / rule set (i.e. it could only ever
/// make the frame MORE masked), [MaskGeometry.resolutionIncomplete] is set
/// so [maskImage] can fail safe (see that flag's doc comment). Only
/// [ScrywatchReveal] resolution failures are exempt, since a missing reveal
/// is safe by construction (less is shown, never more).
MaskGeometry computeMaskGeometry(
  BuildContext boundaryContext,
  RenderBox boundaryBox,
) {
  final MaskPolicy policy = MaskRegistry.instance.policy;
  bool resolutionIncomplete = false;

  Rect rectRelativeTo(RenderBox box) {
    final Offset topLeft = box.localToGlobal(Offset.zero, ancestor: boundaryBox);
    return topLeft & box.size;
  }

  // [trackFailures] controls whether an unresolved key marks the geometry
  // as [resolutionIncomplete] — pass true for anything feeding
  // [MaskGeometry.hardMaskRects] (mask/tag/rule keys), false for reveal
  // keys (a missing reveal is safe on its own).
  List<Rect> rectsFor(Iterable<GlobalKey> keys, {bool trackFailures = false}) {
    final List<Rect> rects = <Rect>[];
    for (final GlobalKey key in keys) {
      final BuildContext? ctx = key.currentContext;
      if (ctx == null) {
        if (trackFailures) resolutionIncomplete = true;
        continue;
      }
      final RenderObject? ro = ctx.findRenderObject();
      if (ro is! RenderBox || !ro.attached || !ro.hasSize) {
        if (trackFailures) resolutionIncomplete = true;
        continue;
      }
      rects.add(rectRelativeTo(ro));
    }
    return rects;
  }

  final Set<String> widgetTypeRuleValues = <String>{
    for (final MaskRule rule in policy.rules)
      if (rule.match == MaskMatch.widgetType) rule.value,
  };
  final List<MaskRule> textPatternRules = <MaskRule>[
    for (final MaskRule rule in policy.rules)
      if (rule.match == MaskMatch.textPattern) rule,
  ];

  // Single tree walk collecting: the always-on floor (obscured/password
  // fields only) plus widgetType/textPattern rule matches.
  final List<Rect> floorRects = <Rect>[];
  final List<Rect> ruleRects = <Rect>[];

  // A hard-mask candidate (floor match or rule match) was identified for
  // this element, but its rect couldn't be resolved this frame — record
  // that as an incomplete resolution rather than silently dropping it.
  void addFloorRect(Rect? r) {
    if (r != null) {
      floorRects.add(r);
    } else {
      resolutionIncomplete = true;
    }
  }

  void addRuleRect(Rect? r) {
    if (r != null) {
      ruleRects.add(r);
    } else {
      resolutionIncomplete = true;
    }
  }

  void visit(Element element) {
    final Widget widget = element.widget;
    Rect? rect;
    Rect? rectOf() {
      if (rect != null) return rect;
      final RenderObject? ro = element.renderObject;
      if (ro is RenderBox && ro.attached && ro.hasSize) {
        rect = rectRelativeTo(ro);
      }
      return rect;
    }

    // --- Always-on floor: obscured (password) fields ONLY ---
    // Record-everything-by-default is the product default. The single thing
    // never captured without configuration is what a user types into an
    // obscured (`obscureText`) field — a secret that must never land in a
    // stored frame. WebViews/native surfaces and heuristic PII text are NO
    // LONGER floor-masked; opt into them per project via config rules
    // (`widgetType: webview` / `video`, `textPattern: email|card|ssn|phone`)
    // or in code via ScrywatchMask / ScrywatchTag. Strict mode still masks
    // everything by default for HIPAA/PCI-grade projects.
    if (widget is EditableText && widget.obscureText) {
      addFloorRect(rectOf());
    }

    // --- widgetType rules ---
    for (final String type in widgetTypeRuleValues) {
      if (widgetTypeMatches(element, type)) {
        addRuleRect(rectOf());
        break; // one matched rule is enough to mask this element.
      }
    }

    // --- textPattern rules ---
    if (textPatternRules.isNotEmpty) {
      final String? text = _visibleTextOf(widget);
      if (text != null) {
        for (final MaskRule rule in textPatternRules) {
          if (_matchesTextPatternRule(text, rule.value)) {
            addRuleRect(rectOf());
            break;
          }
        }
      }
    }

    element.visitChildren(visit);
  }

  boundaryContext.visitChildElements(visit);

  // `tag` rules resolve via the registry, not the tree walk. A rule with no
  // currently-registered keys at all (`keys == null`) is not a resolution
  // failure — it's a rule that simply has nothing tagged right now.
  for (final MaskRule rule in policy.rules) {
    if (rule.match != MaskMatch.tag) continue;
    final Set<GlobalKey>? keys = MaskRegistry.instance.taggedKeys[rule.value];
    if (keys == null) continue;
    ruleRects.addAll(rectsFor(keys, trackFailures: true));
  }

  return MaskGeometry(
    mode: policy.mode,
    revealRects: rectsFor(MaskRegistry.instance.revealKeys),
    hardMaskRects: <Rect>[
      ...floorRects,
      ...rectsFor(MaskRegistry.instance.maskKeys, trackFailures: true),
      ...ruleRects,
    ],
    resolutionIncomplete: resolutionIncomplete,
  );
}

/// Named PII kinds a `textPattern` rule's `value` may reference (per the
/// design doc's rule language), falling back to treating `value` as a
/// literal custom regex.
bool _matchesTextPatternRule(String text, String value) {
  switch (value) {
    case 'email':
      return _emailPattern.hasMatch(text);
    case 'ssn':
      return _ssnPattern.hasMatch(text);
    case 'phone':
      return _phonePattern.hasMatch(text);
    case 'card':
      return scrywatchIsPii(text);
    default:
      try {
        return RegExp(value).hasMatch(text);
      } catch (_) {
        // An invalid custom regex matches nothing rather than throwing —
        // computeMaskGeometry must never fail the whole frame over one bad
        // rule.
        return false;
      }
  }
}

/// Redact a captured [raw] frame by painting occlusion ONTO the bitmap
/// (post-capture), mode-aware:
///
/// - **blocklist** — baseline is the raw frame, UNCHANGED; only
///   [MaskGeometry.hardMaskRects] is painted over. Everything else records
///   in the clear. EXCEPTION: if [MaskGeometry.resolutionIncomplete] is
///   true — i.e. some floor/mask/tag/rule element couldn't be geometrically
///   resolved this frame — the ENTIRE frame is occluded instead (see the
///   fail-safe note below).
/// - **strict** — baseline is fully masked; [MaskGeometry.revealRects] are
///   punched back to real pixels, then [MaskGeometry.hardMaskRects] is
///   re-painted on top — so a reveal can never beat the floor or a rule.
///   Already mask-all at baseline, so `resolutionIncomplete` doesn't change
///   its behavior.
///
/// [scale] converts the logical geometry rects into [raw]'s pixel space
/// (image px per logical px, i.e. the capture `pixelRatio`).
///
/// Fail-safe: any error yields a FULLY-masked frame in both modes — never
/// fail open. Returns a NEW image; the caller owns disposing it and [raw].
Future<ui.Image> maskImage(
  ui.Image raw,
  MaskGeometry geometry, {
  double scale = 1.0,
}) {
  final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(pictureRecorder);
  final Rect full =
      Rect.fromLTWH(0, 0, raw.width.toDouble(), raw.height.toDouble());
  final Paint imagePaint = Paint()..filterQuality = FilterQuality.none;
  final Paint solid = Paint()..color = kMaskColor;
  Rect toPixels(Rect r) => Rect.fromLTWH(
        r.left * scale,
        r.top * scale,
        r.width * scale,
        r.height * scale,
      );
  try {
    if (geometry.mode == MaskMode.blocklist) {
      if (geometry.resolutionIncomplete) {
        // GUARANTEE: blocklist's baseline is the raw frame with only known
        // hard-mask rects painted over. If a floor/ScrywatchMask/tag/rule
        // element was present this frame but its rect could NOT be
        // resolved (mid-relayout, just-mounted, unmounting), we have no
        // rect to paint over — falling through to the normal path would
        // ship that (potentially sensitive) region UNMASKED. Instead we
        // occlude the WHOLE frame for this one tick. This makes
        // under-masking structurally impossible: every unresolved
        // sensitive element forces a full-frame mask rather than silently
        // dropping its region, at the cost of an occasional fully-masked
        // frame during transient layout churn.
        canvas.drawRect(full, solid);
      } else {
        // Baseline: the raw frame, untouched. Occlude ONLY the hard-mask
        // union (floor + ScrywatchMask + matched rules) — everything else
        // records in the clear.
        canvas.drawImageRect(raw, full, full, imagePaint);
        for (final Rect r in geometry.hardMaskRects) {
          final Rect dst = toPixels(r).intersect(full);
          if (dst.isEmpty) continue;
          canvas.drawRect(dst, solid);
        }
      }
    } else {
      // Baseline: everything masked. Punch reveal holes back to real
      // pixels, then re-cover the hard-mask union so it always wins.
      canvas.drawRect(full, solid);
      for (final Rect r in geometry.revealRects) {
        final Rect dst = toPixels(r).intersect(full);
        if (dst.isEmpty) continue;
        canvas.drawImageRect(raw, dst, dst, imagePaint);
      }
      for (final Rect r in geometry.hardMaskRects) {
        final Rect dst = toPixels(r).intersect(full);
        if (dst.isEmpty) continue;
        canvas.drawRect(dst, solid);
      }
    }
  } catch (_) {
    // Fail-safe: never emit a partially-masked frame.
    canvas.drawRect(full, solid);
  }
  final ui.Picture picture = pictureRecorder.endRecording();
  return picture.toImage(raw.width, raw.height);
}

/// The capture root: a [RepaintBoundary] (keyed by [boundaryKey]) wrapping the
/// app so the recorder can capture it.
///
/// This does NOT paint a mask onto the live UI — the live screen renders
/// normally and redaction is applied to the captured bitmap afterwards (see
/// [maskImage]), so the customer's own screen is never blacked out. The
/// reveal/mask registries + `obscureText` detection feed
/// [computeMaskGeometry] at capture time.
Widget maskedRoot({required GlobalKey boundaryKey, required Widget child}) {
  return RepaintBoundary(key: boundaryKey, child: child);
}
