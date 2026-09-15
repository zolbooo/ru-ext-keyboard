# Native punctuation page switching

Investigated 2026-09-15 using the installed arm64 iOS 26.5 (23F77)
Simulator UIKitCore. **Static reverse engineering completed; live per-key
verification is blocked.** Simulator installation/launch requests stalled;
the console launch eventually reported NSMachErrorDomain -308 (server died).
Restarting the iPhone 17 Pro and trying an iPhone 17 did not resolve this.
Do not treat the per-symbol table as measured: no such table was recovered yet.

## Recovered rule

The native keyboard does not simply return to letters after every punctuation
character. Its normal automatic return is driven by key metadata and text-edit
state:

1. `upActionFlagsForKey:` reads `UIKBAttributeNameMoreAfter`. If true, it sets
   action bit 8 (`0x100`). Hidden or disabled keys return no actions.
2. In the touch-up continuation, bit 8 enables the automatic-page branch.
3. If the current keyplane `supportsType:` the text field's `keyboardType`,
   this branch does nothing. This distinguishes a preferred page from an
   alternate page; behavior must be checked separately for specialized fields.
4. A key whose **represented string is exactly ASCII `-`** bypasses this branch.
   This is not a Unicode punctuation-category test or a test of surrounding text.
5. For a represented string satisfying `_isSpaceOrReturn`, UIKit increments
   `_preferredTrackingChangeCount` before comparing it with the keyboard's
   current `changeCount`.
6. Only if `changeCount > _preferredTrackingChangeCount` does it load the
   current page's `alternateKeyplaneName`, select that page, and synchronize
   Shift with its `isShiftKeyplane` value.

The preferred tracking count is captured when the user switches pages.
Consequently, Space/Return discount their own edit: opening a symbols page
and immediately inserting a space can differ from inserting a symbol and
then a space. This is a reconstruction of the counter logic, not yet an
end-to-end typing measurement. The counter tracks edits, not a literal count
of punctuation characters; deletion and other edit paths need separate checks.

The switch occurs in the **touch-up processing path**, not a punctuation timer.
The exact rendered-frame timing and text-insertion scheduling have not been
measured.

## Separate temporary-page gesture

Pressing a page chooser saves `preTouchKeyplaneName`. The keyboard has a
separate `_revertKeyplaneAfterTouch` path, with checks involving the released
key and `slidOffKey`. This restores the saved page during touch-up and explains
why the hold-123/slide-to-symbol gesture must be investigated independently
from tapping 123 and subsequently tapping a symbol. `keyplaneNameForRevertAfterTouch`
can normalize a shifted alternate to its shift alternate before saving it.
The gesture's complete eligibility conditions are not reconstructed here.

## Binary evidence

Image identity is recorded in [the earlier investigation](Tests/NativeCursor/results/runtime-identity.json).
Offsets below are relative to that UIKitCore image:

| Method / location | Evidence |
| --- | --- |
| `upActionFlagsForKey:` `0xeec240` | MoreAfter property at +96; produces `0x100` at +120 |
| `continueFromInternationalActionForTouchUp:withActions:timestamp:interval:didLongPress:prevActions:executionContext:` `0xee9bd0` | bit 8 check at +456; supportsType at +500; string comparison at +552 |
| `0xeea1d8`–`0xeea270` | Space/Return adjustment, strict counter comparison, alternate-page selection |
| CFString at `0x239f118` | Decoded payload is the single ASCII byte `-` |
| `completeSendStringActionForTouchUp:withActions:timestamp:interval:didLongPress:prevActions:executionContext:` `0xee8dbc` | saves current changeCount after page change at +196–212 |
| `0xee9ed4`–`0xeea0bc` | separate saved-page reversion path |
| `keyplaneNameForRevertAfterTouch` `0xee1c38` | chooses saved page, accounting for shifted alternate |
| `triggerSpaceKeyplaneSwitchIfNecessary` `0xeef344` | a separate programmatic route checks Space's bit 8 and supportsType, then changes page without the counter test |

`incrementPunctuationIfNeeded:` is a statistics path. It does not implement
page switching despite its name.

Raw disassembly is generated under `.build/NativePunctuation/layout.asm` using
[the existing reader](Tests/NativeCursor/inspect_macho.py). Apple binaries are
not copied into the repository.

## Project behavior

[KeyboardViewController.swift](RussianExtendedKeyboard/Keyboard/KeyboardViewController.swift)
now applies a public-API approximation on insertion from either symbols page:

- Apostrophe (`'` or `’`) returns immediately to letters.
- Other symbols/digits remain; a following Space or Return returns to letters.
- Space/Return alone after opening 123 does not return.
- Numeric field types suppress automatic return.
- Explicit page toggles and document changes reset the insertion history;
  switching between 123 and #+= preserves it.

Apostrophe membership is an explicit product policy, **not measured native
metadata**. History records non-separator insertions rather than UIKit's private
edit counter; deletion does not undo that history. The temporary hold-123 gesture
is not implemented by this change. The existing release callbacks also cover
variant selection; cursor-mode release does not insert a Space.

Policy sequence tests pass via `bash Tests/PageReturn/run.sh`, and the complete
keyboard source passes iOS Simulator SDK typechecking. End-to-end Simulator
verification remains outstanding.

## Remaining verification

Run [the metadata probe](Tests/NativePunctuation/README.md) once Simulator app
launching works. Record the actual input language and field type. Check both
Russian and English, 123 and #+= pages, and these cases:

- Each visible punctuation key by itself, especially apostrophe and hyphen.
- 123 → Space with no intervening edit, and symbol/digit → Space.
- Return, repeated spaces, deletion, smart-punctuation variants.
- Hold 123 → slide to symbol → release versus separate taps.
- Default text, URL, email, and numbers-and-punctuation field types.

The `MoreAfter` membership of individual punctuation keys is still unknown;
the binary control flow alone does not establish whether e.g. apostrophe or
period requests an immediate return on the current language/layout.
