# Native cursor investigation harness

A standalone Simulator app for inspecting Apple's keyboard, separate from all
production Xcode targets. It uses private runtime interfaces for investigation.
Do not link these files into the shipping app or keyboard extension.

## Repeat the native calculation checks

With Xcode and an already booted arm64 iPhone Simulator:

```sh
xcrun simctl list devices booted
bash Tests/NativeCursor/run.sh SIMULATOR_UDID
```

The runner builds and installs `local.keyboard.native-cursor-probe`, opens the
native keyboard, discovers its actual named Space recognizer, runs the tests,
and exits. It prints the directory containing `runtime.log` and
`measurements.json`. It fails if the measurement record is missing or any check
fails. If Apple's keyboard is unavailable, switch to it in that Simulator first.

The native math is compared with independent reconstruction formulas. Boundary
and floating-view tests use controlled collaborators. Text-position tests use
a real, unpresented UITextView. The two live acceleration-state properties used
by the probe are restored afterward; verification runs only while the gesture
is idle. The movement-history fixture checks its runtime layout before seeding
its C array and uses Apple's actual `CFAbsoluteTimeGetCurrent` clock source.

Recorded result: **iOS 26.5 (23F77), 894 checks passed**. See
[measurements](results/ios-26.5-measurements.json) and
[runtime identity](results/runtime-identity.json).

## Interactive inspection

```sh
xcrun simctl launch --terminate-running-process --console SIMULATOR_UDID \
  local.keyboard.native-cursor-probe --trace --dump-runtime
```

This leaves a sample editor open. Trace mode forwards native calls while logging
touches, pan state, trackpad presentation, and floating-cursor calls. It does not
synthesize touches. `--dump-runtime` lists relevant native methods and ivars.
LLDB can attach to the printed app PID; `inspect.lldb` contains additional
inspection commands. Trace output is diagnostic, not suitable for latency
benchmarking. Avoid recording real user text; this app uses a fixed sample.

## Inspect the Simulator binary

`inspect_macho.py` requires Python 3 and Capstone (5.0.7 was used). It reads the
installed thin arm64 Mach-O, maps symbols/import stubs, and annotates selected
instructions. Supply your installed runtime's UIKitCore path:

```sh
python3 Tests/NativeCursor/inspect_macho.py "$UIKITCORE_PATH" \
  'acceleratedTranslation:|floatingCursorPositionForPoint:|keyboardTrackpadCurve'
```

Annotations are aids to reading disassembly, not a decompiler. Runtime tests
verify the main reconstructed formulas. Raw generated disassembly belongs in
`.build/NativeCursor/`, not in the production targets.

For the recovered state machine, formulas, API constraints, and validation
limits, read [the investigation](../../SPACEBAR_CURSOR_RESEARCH.md).
