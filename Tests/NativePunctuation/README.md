# Native punctuation metadata probe

Standalone Simulator-only app using private runtime selectors; it is not part
of the shipping Xcode targets. It dumps represented strings and native touch-up
action flags from the current page, its alternate, and its shifted alternate.
`flags & 0x100` is the automatic-page action; it is not sufficient by itself to
prove a page will switch. See [the investigation](../../PUNCTUATION_PAGE_RESEARCH.md).

Status: builds successfully; execution has not been verified because Simulator
app launch/install services stalled during this investigation. No measured
per-key results are included.

With a booted arm64 iPhone Simulator and Apple's keyboard selected:

```sh
bash Tests/NativePunctuation/build.sh
xcrun simctl install DEVICE_UDID .build/NativePunctuation/NativePunctuation.app
xcrun simctl launch DEVICE_UDID local.keyboard.native-punctuation-probe
xcrun simctl get_app_container DEVICE_UDID local.keyboard.native-punctuation-probe data
```

Read `Documents/results.txt` inside the returned data container. The app exits
after collecting metadata. It does not synthesize touches or verify full typing
sequences. Language is the simulator's selected keyboard; the text view uses
the default field type with autocorrection disabled.
