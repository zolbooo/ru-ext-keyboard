# Keyboard startup benchmark

Run on a booted iOS simulator with Xcode installed:

```sh
xcrun simctl list devices booted
Tests/KeyboardStartup/run.sh SIMULATOR_UDID
```

The script builds an optimized, standalone UIKit harness containing the actual
keyboard source. It does not add test code or dependencies to the shipped app.
It installs `local.keyboard.startup-benchmark` on the selected simulator and leaves
its executable and per-launch logs in the printed temporary directory.
Each launch also writes light/dark preview PNGs in the simulator app's Documents
directory; the log prints their paths.

For a comparison, save the original controller before editing and supply it as
the second argument. Alternate baseline and changed versions on the same simulator;
first-use samples are noisy. Avoid concurrent simulator work during measurement.

```sh
Tests/KeyboardStartup/run.sh SIMULATOR_UDID /tmp/KeyboardViewController-baseline.swift
```

To collect seven fresh-process samples and enforce the 60 ms median budget:

```sh
Tests/KeyboardStartup/run.sh SIMULATOR_UDID RussianExtendedKeyboard/Keyboard/KeyboardViewController.swift 7
python3 Tests/KeyboardStartup/summarize.py /tmp/keyboard-startup.XXXXXX/sample-*.log --max-median-ms 60
```

Use the actual artifact directory printed by the runner. The summary includes
all supplied samples, their range, and the median. Budget enforcement requires at
least five successful launches and fails if any log lacks a successful benchmark.

Each run measures controller initialization, `loadViewIfNeeded`, and the first
layout at 393 × 216 points. It reports the first construction and the median of
30 subsequent constructions. These measurements exclude process launch, dyld,
extension hosting, and display presentation; they are not end-to-end device
keyboard activation measurements.

Assertions cover 37 letter-page keys, nonzero key dimensions, shift, all three
pages, touch routing at every key center after page changes, resizing through
320/393/430/852/1024/393-point widths, and opening/cancelling ө/ү/ё/ъ variants.
`GEOMETRY` records allow comparison of key order and frames between versions.
The outer view's Auto Layout fitting height is also checked at portrait and
landscape widths, starting from an oversized 500-point frame. This verifies the
216/169-point height requests; extension hosting on a device remains a separate
check.
The lightweight-control checks also cover accessibility activation callback order,
button accessibility traits, overlapping routed highlights, and light/dark text
colors. The harness does not simulate physical touches or verify haptic hardware.

## Recorded comparison

September 5, 2026, Xcode 26.6, iPhone 17 Pro simulator with iOS 26.5, optimized
compilation. Five alternating runs per version, each with 31 constructions:

| Metric | Original | Optimized | Reduction |
| --- | ---: | ---: | ---: |
| Median first construction/layout | 74.0 ms | 62.1 ms | 16% |
| Median of repeated-construction medians | 11.5 ms | 7.6 ms | 34% |

The unsigned arm64 Release extension executable decreased from 237,776 to
234,792 bytes (1.3%). The full app and extension Release build succeeded.

The expanded regression harness passed. Across the six resize samples, key order
matched and the largest frame-component difference was 0.304 points, within the
original stack layout's one-pixel rounding at 3× scale.

The optimization uses direct frames for the four fixed rows, initializes the word
tokenizer and haptic generators on demand, shares button appearance objects,
removes unused styles, caches the touch-routing key list, and skips unchanged
return-key updates. Tokenization behavior and all existing character variants
remain intact.

## Follow-up: 60 ms target

Seven alternating launches per version on the same simulator and toolchain as
above, comparing commit `e152f6a` with the lightweight key controls:

| Metric | e152f6a | Lightweight controls |
| --- | ---: | ---: |
| Median first construction/layout | 63.6 ms | **58.7 ms** |
| First-construction range | 57.3–76.6 ms | 55.3–64.7 ms |
| Median repeated construction | 7.4 ms | 4.0 ms |

The 60 ms **median** budget passes. Two of seven candidate samples exceeded 60 ms;
this is not a worst-case or end-to-end device launch guarantee. No samples were
removed. Individual readings are saved in `results/baseline-e152f6a.json` and
`results/lightweight-controls.json`.

Keys now use `UIControl` with only the label or template image each key needs.
The existing touch router still handles typing and long presses; the control
provides explicit accessibility activation. Redundant initial titles and return
icons were removed. The normal `UIInputViewController` root setup is retained.

Release build and regression checks passed. Light/dark rendering was compared
with the baseline in a hosted window; all six key-geometry records match exactly. The harness now reports separate
initialization, view-loading, and first-layout times, and calculates the repeated
median from both middle samples.
