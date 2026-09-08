# Horizontal Space cursor checks

Run with an already booted arm64 iPhone Simulator:

```sh
bash Tests/SpaceCursor/run.sh SIMULATOR_UDID
```

The standalone app compiles the shipping keyboard source together with the
fixture, without changing the production targets. It drives the same routing
methods called by UIKit with deterministic points and timestamps; touch objects
serve only as identities. It does not synthesize physical gestures. Timers are
fired directly so tests do not depend on wall-clock hold accuracy.

Coverage includes short taps, hold cancellation, origin reset, acceleration,
reversal, vertical-only movement, competing fingers, backspace and variant
cancellation, careful release, continuation expiry/re-grab, layout changes,
dismissal, accessibility, and key-legend presentation. A detached-editor case
checks that a nil document identifier cancels cursor activation without crashing. A real `UITextView` hosts
the keyboard as its input view controller to check the public document proxy,
including Cyrillic, family emoji, flags, combining marks, and text boundaries.

Artifacts are printed under `.build/SpaceCursor/`: the combined source, test app,
and runtime log. Preview paths in the log show the keyboard during cursor mode
and after it exits. Simulator checks cannot establish physical-device gesture
feel or compatibility with every third-party editor.

## Product behavior and tuning

- Hold Space for 0.375 seconds, staying within 16 points before activation.
- With Full Access enabled, activation/re-grab gives a light impact and cursor
  steps give selection ticks, limited to 20 per second. Simulator checks cannot
  verify physical haptic output.
- After the key legends disappear, slide left/right. Vertical motion alone does
  not move the cursor. Recovered two-dimensional sample length sets acceleration.
- Eight accelerated points produce one character step. This is extension tuning,
  not a native editor measurement. Fractional movement is retained.
- Available surrounding text converts grapheme steps to UTF-16 proxy offsets.
  A host that supplies no context falls back to raw proxy units; Unicode boundary
  protection cannot be guaranteed in that case.
- A careful lift (less than 15 points of recent movement over 0.2 seconds) keeps
  the last delivered position. It does not rewind earlier proxy calls.
- A careful release in the Space region leaves a 0.5-second re-grab window.
  Touch Space again to continue immediately, or another key to type normally.
- Cursor mode never inserts Space, and extra fingers cannot type while it is
  active. Ordinary short Space taps retain their existing behavior.

All shipping code uses public UIKit APIs. The native investigation harness is
separate; see [the findings](../../SPACEBAR_CURSOR_RESEARCH.md).
