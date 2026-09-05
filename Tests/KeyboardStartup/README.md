# Keyboard startup benchmark

Run on a booted iOS simulator with Xcode installed:

```sh
xcrun simctl list devices booted
Tests/KeyboardStartup/run.sh SIMULATOR_UDID
```

The script builds an optimized, standalone UIKit harness containing the actual
keyboard source. It does not add test code or dependencies to the shipped app.
It installs `local.keyboard.startup-benchmark` on the selected simulator and leaves
its executable and full log in the printed temporary directory.

For a comparison, save the original controller before editing and supply it as
the second argument. Alternate baseline and changed versions on the same simulator;
first-use samples are noisy. Avoid concurrent simulator work during measurement.

```sh
Tests/KeyboardStartup/run.sh SIMULATOR_UDID /tmp/KeyboardViewController-baseline.swift
```

Each run measures controller initialization, `loadViewIfNeeded`, and the first
layout at 393 × 216 points. It reports the first construction and the median of
30 subsequent constructions. These measurements exclude process launch, dyld,
extension hosting, and display presentation; they are not end-to-end device
keyboard activation measurements.

Assertions cover 37 letter-page keys, nonzero key dimensions, shift, all three
pages, touch routing at every key center after page changes, resizing through
320/393/430/852/1024/393-point widths, and opening/cancelling ө/ү/ё/ъ variants.
`GEOMETRY` records allow comparison of key order and frames between versions.
The harness does not simulate physical touches or verify haptic hardware.

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
