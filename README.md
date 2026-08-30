# Русская+ keyboard

An iOS custom keyboard with the standard Russian letter layout and Mongolian
Cyrillic variants:

- Long-press **о** for **ө**
- Long-press **у** for **ү**
- Long-press **₽** for **₮**

## Run

1. Open `RussianExtendedKeyboard.xcodeproj` in Xcode.
2. Select the **RussianExtendedKeyboard** scheme and an iPhone simulator or device.
3. Run the app.
4. Open **Settings → General → Keyboard → Keyboards → Add New Keyboard**.
5. Choose **Русская+**, then switch to it using the globe key.

Full Access is optional and is used only to enable keyboard haptic feedback.
The app and keyboard contain no networking code and do not collect or transmit
typed text.

## Distribution

`main` is the TestFlight branch and `production` is the App Store release
branch. See [the Xcode Cloud workflow guide](docs/XCODE_CLOUD.md) for setup,
versioning, promotion, and branch-protection details.
