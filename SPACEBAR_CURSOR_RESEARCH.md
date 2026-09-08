# Native Space trackpad: Simulator implementation

Reverse-engineered on September 8, 2026 in the **iPhone 17 Pro Simulator,
iOS 26.5 (23F77), arm64**. This replaces the earlier public-API-only analysis.

Evidence comes from live Objective-C objects, LLDB, the installed UIKitCore
Mach-O, and direct calls to Apple's unmodified calculation methods. The
[repeatable probe](Tests/NativeCursor/README.md) passed **894 checks**.
[Measurements](Tests/NativeCursor/results/ios-26.5-measurements.json) and the
[binary identity](Tests/NativeCursor/results/runtime-identity.json) are retained.
The keyboard now implements a public-API horizontal approximation; see the
[implementation checks](Tests/SpaceCursor/README.md).

## What Apple actually does

The native Space recognizer is `_UIPanOrFlickGestureRecognizer`, named
`_UIKeyboardTextSelectionGestureLongPress`, attached to `UIKeyboardLayoutStar`.
Its target is `_UIKeyboardTextSelectionInteraction.panningGesture:`; its owner
is `_UIKeyboardTextSelectionGestureController`.

The flow is:

```text
Space long press
  → panningGesture:
  → reset gesture origin; clear pending keyboard touches; disable typing
  → accelerate translation and accumulate boundary corrections
  → cursorLocationForTranslation: (original caret center + translation)
  → _UIKeyboardTextSelectionController
      → updateFloatingCursorAtPoint:       [continuous visual cursor]
      → selectPositionAtPoint:…            [actual insertion position]
          → editor.closestPositionToPoint:
          → editor selection update
```

Apple moves a **point in the editor's coordinate system**, then asks the editor
for a valid text position. It does not implement this path as a fixed number of
pixels per character. The visual floating cursor and the actual insertion caret
are distinct, which explains why movement can look continuous while insertion
positions still fall between characters.

## Activation

The actual live Space recognizer reported:

| Property | Native value |
| --- | --- |
| Minimum press duration | **0.375 s** |
| Allowable movement before recognition | **16 pt** |
| Minimum / maximum touches | **1 / 1** |
| Long-press-only | Enabled |

`additionalPressDurationForTypingCadence:` can return another **0.4 s** when
`lastTouchesEnded + minimumPressDuration >= systemUptime`. This is a separate
cadence-dependent delay, not a universal 0.775-second hold requirement.

`UIKeyboardLayoutStar._keyboardLongPressInteractionRegions` takes the cached
key frames and multiplies their **height by 1.5**, preserving the top edge. The
live portrait Space region was `{103.333, 169, 197.333, 81}` in keyboard-layout
coordinates. The effective activation region therefore extends downward beyond
the ordinary key frame.

At recognition, the recognizer's translation is reset. The controller clears
pending key touches, resets accumulated acceleration/bounding, and starts the
trackpad presentation. `setTrackpadMode:animated:` disables ordinary typing and
deactivates active keys. The gesture path also invokes a native feedback state;
haptic strength was not measured in Simulator.

## Recovered movement curve

Let `t` be the current raw translation and `previous` the previous raw translation.
For each active update:

```text
delta = t - previous
s = length(delta)
extra += delta * g(s)
acceleratedTranslation = t + extra
previous = t
```

The native defaults are `gain = 0.2`, `linear = 2`, `parabolic = 5`, with
acceleration enabled. Their resulting extra-gain curve is:

```text
g(s) = 0.04*s*s                  for 0 ≤ s ≤ 2
       0.16*s - 0.16            for 2 < s ≤ 5
       sqrt(0.2048*s - 0.6144)   for s > 5
```

Thus a 1-point movement sample has total gain 1.04; 4 points → 1.48;
8 points → approximately 2.012. The length includes **both axes**.

Despite the selector `acceleratedTranslation:velocity:isActive:`, this build's
implementation uses the change in translation, **not the velocity argument**.
Consequently the sampling cadence matters. Terminal updates retain accumulated
acceleration but add no new acceleration.

The reconstructed curve matched **321 native calls**, with maximum absolute
error `8.88e-16`. A 12-step sequence also matched, including diagonals, reversal,
small movements, unrelated velocity arguments, and an inactive final update.

## Boundaries and vertical “magnetism”

`boundedTranslation:` gets a geometric clipping correction from the selection
controller, accumulates it separately from acceleration, then adds it to the
translation. The accumulation preserves an extreme correction when a smaller
correction has the same sign; a correction of the opposite sign is added to the
previous correction. Nine controlled two-axis cases matched the reconstruction.
This is stateful boundary compensation, not merely clamping every finger sample.

`_UITextFloatingCursorSession.floatingCursorPositionForPoint:lineSnapping:`:

1. Gets the editor's selection clip rectangle, falling back to its view bounds.
2. Insets it by half the floating cursor's width/height and clamps the point.
3. With line snapping enabled, applies:

   `visualY = actualCaretCenterY + 0.3 * (clampedY - actualCaretCenterY)`

The x coordinate remains the clamped requested x. The actual insertion position
is resolved separately using editor geometry; **0.3 is visual vertical tethering,
not “move one line every N pixels.”** Sixteen native calls against a fixed
geometry fixture matched this formula, with snapping both enabled and disabled.
The floating cursor's spring behavior uses damping ratio **1** and response
**0.18 s**; response is not a promise of an exact animation completion time.

## Release, re-grab, and selection

The controller records a 16-entry movement history. `isPlacedCarefully` requires
history covering **0.2 s**, with distance covered in that interval **below 15 pt**.
On a careful release, it substitutes `weightedPoint` for the final touch position.
In this build that helper looks back about **0.15 s** when enough history exists;
it is not a straightforward average. Two seeded native-history cases verify the
look-back result and the short-history fallback. This helps explain resistance
to small lift-off movements.

Release does not always restore the ordinary keyboard immediately. Space has a
conditional **0.5 s** continuation timer and a temporary recognizer with **zero
minimum press duration**. The code considers careful placement, maximum Space
pan distance (a **16 pt** threshold), whether release is inside the special
region, and an existing continuation callback. This permits re-grabbing the
trackpad in those cases. It is not unconditional inertia or always-on edge scroll.

A second touch sets `hadAddedTouch`. The pan path can then restart selection,
switch to a ranged selection, and update its extent through the editor's
selection controller. This is the same two-finger selection feature described
in [Apple's iPhone guide](https://support.apple.com/en-ie/guide/iphone/iph3c50f96e/ios).

## Can Русская+ replicate it?

**We can reproduce the recognition, appearance, acceleration, and gesture-state
behavior. Full native placement requires editor capabilities our public keyboard
proxy does not expose.**

The installed `UITextDocumentProxy` protocol provides character-offset movement
and read-only selected text. It does not provide `closestPositionToPoint:`, caret
rectangles, the host's floating-cursor control, or a writable selected range.
Those are the exact capabilities used in the native path above. See Apple's
[proxy API](https://developer.apple.com/documentation/uikit/uitextdocumentproxy).

For an editor we own, this investigation supplies the core math for a much closer
two-dimensional implementation. For the systemwide extension, a horizontal scrub
can use the recovered gesture behavior and acceleration, but must translate it
into character offsets. It cannot faithfully reproduce native visual line
movement and floating-cursor magnetism in arbitrary host apps through that proxy.

The touch router now has a separate Space cursor state. It activates after
0.375 seconds with a 16-point pre-activation tolerance, blanks the key legends,
cancels competing touches/backspace/variants, and captures movement across the
keyboard. It uses the recovered per-sample acceleration with an **8-point
character spacing chosen for this extension**, retaining fractional movement.
Available proxy context maps grapheme steps to UTF-16 offsets, protecting emoji
and combining marks in the tested UIKit editor. When context is unavailable,
movement falls back to the proxy's raw offset units.

A careful lift keeps the last delivered position instead of attempting to rewind
historical proxy calls. A careful release inside the extended Space region allows
a 0.5-second immediate re-grab; another key resumes ordinary typing immediately.
This uses the recovered timing with a simplified continuation policy, not a copy
of every native continuation branch. Closing the keyboard, rebuilding/changing
its layout, or detecting another document cancels the session. Native cadence
adjustment, floating-cursor animations, and two-finger selection are not included.

## Evidence and limits

Key UIKitCore offsets (relative to the recorded binary's image base):

| Method | Offset |
| --- | --- |
| `_configureLongPressRecognizer:` | `0x1084064` |
| `additionalPressDurationForTypingCadence:` | `0x1084918` |
| `acceleratedTranslation:velocity:isActive:` | `0x1084cc0` |
| `boundedTranslation:` | `0x1084f10` |
| `panningGesture:` | `0x10885f4` |
| `_startTouchPadTimerWithCompletion:` | `0x108928c` |
| `UIKeyboardLayoutStar._keyboardLongPressInteractionRegions` | `0xed8820` |
| `_UITextFloatingCursorSession.floatingCursorPositionForPoint:lineSnapping:` | `0xa4a264` |
| `_UITextFloatingCursorSession._springAnimation` | `0xa4a154` |
| `UITextMagnifierTimeWeightedPoint.weightedPoint` | `0x155ad90` |
| `UITextMagnifierTimeWeightedPoint.isPlacedCarefully` | `0x155b0ac` |

The 894 checks comprise 321 curve samples, 12 acceleration steps, 9 boundary
steps, 16 floating-position cases, 10 native selection-position cases, 524
Unicode boundary checks, and 2 history cases. Selection tests use a real
`UITextView` containing wrapped text, Cyrillic, a family emoji, a flag, and a
combining mark. They do not establish behavior in every host app.

These are runtime-inspected settings, reconstructed machine-code paths, and
direct native-method tests. A CUA drag produced a short touch rather than a
sustained hold, so it is **not** evidence of end-to-end activation latency or
physical finger trajectories. Timing constants and the re-grab branches above
come from code inspection. No claim is made that every iOS version or a physical
iPhone has identical tuning. Raw debugger output remains under
`.build/NativeCursor/investigation-raw/`; no Apple binary is included in the repo.
