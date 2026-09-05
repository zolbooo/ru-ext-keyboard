import UIKit

private final class Delegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        setbuf(stdout, nil)
        let window = UIWindow(frame: UIScreen.main.bounds)
        self.window = window
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        DispatchQueue.main.async {
            var times: [Double] = []
            for _ in 0..<31 {
                autoreleasepool {
                    let start = CACurrentMediaTime()
                    let keyboard = KeyboardViewController()
                    let initialized = CACurrentMediaTime()
                    keyboard.loadViewIfNeeded()
                    let loaded = CACurrentMediaTime()
                    keyboard.view.frame = CGRect(x: 0, y: 0, width: 393, height: 216)
                    keyboard.view.setNeedsLayout()
                    keyboard.view.layoutIfNeeded()
                    let laidOut = CACurrentMediaTime()
                    times.append((laidOut - start) * 1000)
                    if times.count == 1 {
                        print("PHASES init_ms=\((initialized-start)*1000) load_ms=\((loaded-initialized)*1000) layout_ms=\((laidOut-loaded)*1000)")
                    }
                    let buttons = self.buttons(in: keyboard.view)
                    precondition(buttons.count == 37, "Expected 37 keys, got \(buttons.count)")
                    self.checkRouting(in: keyboard.view)
                    precondition(buttons.allSatisfy { $0.bounds.width > 0 && $0.bounds.height > 0 })
                    buttons.first { $0.accessibilityLabel == "Сдвиг" }!.sendActions(for: .touchUpInside)
                    precondition(self.buttons(in: keyboard.view).contains { $0.title(for: .normal) == "Й" })
                    self.buttons(in: keyboard.view).first { $0.accessibilityLabel == "Цифры" }!.sendActions(for: .touchUpInside)
                    keyboard.view.layoutIfNeeded()
                    self.checkRouting(in: keyboard.view)
                    precondition(self.buttons(in: keyboard.view).contains { $0.title(for: .normal) == "₽" })
                    self.buttons(in: keyboard.view).first { $0.accessibilityLabel == "Дополнительные символы" }!.sendActions(for: .touchUpInside)
                    keyboard.view.layoutIfNeeded()
                    self.checkRouting(in: keyboard.view)
                    precondition(self.buttons(in: keyboard.view).contains { $0.title(for: .normal) == "=" })
                    self.buttons(in: keyboard.view).first { $0.accessibilityLabel == "Буквы" }!.sendActions(for: .touchUpInside)
                    keyboard.view.layoutIfNeeded()
                    self.checkRouting(in: keyboard.view)
                    precondition(self.buttons(in: keyboard.view).contains { $0.title(for: .normal) == "й" })
                }
            }
            let control = KeyboardButton()
            var actions: [String] = []
            control.pressBeganAction = { actions.append("began") }
            control.tapAction = { actions.append("tap") }
            control.pressEndedAction = { actions.append("ended") }
            // UIButton's system accessibility activation needs a hosted accessibility session.
            // The lightweight control must implement activation itself.
            if !((control as UIControl) is UIButton) {
                precondition(control.isAccessibilityElement && control.accessibilityTraits.contains(.button))
                precondition(control.accessibilityActivate())
                precondition(actions == ["began", "tap", "ended"])
            }
            control.beginRoutedHighlight()
            control.beginRoutedHighlight()
            control.endRoutedHighlight()
            precondition(control.isHighlighted)
            control.endRoutedHighlight()
            precondition(!control.isHighlighted)

            let keyboard = KeyboardViewController()
            keyboard.loadViewIfNeeded()
            for width: CGFloat in [320, 393, 430, 852, 1024, 393] {
                let height: CGFloat = width >= 560 ? 169 : 216
                keyboard.view.frame = CGRect(x: 0, y: 0, width: width, height: height)
                keyboard.view.setNeedsLayout()
                keyboard.view.layoutIfNeeded()
                keyboard.view.layoutIfNeeded()
                self.checkRouting(in: keyboard.view)
                let keys = self.buttons(in: keyboard.view)
                precondition(keys.count == 37)
                for key in keys {
                    let frame = key.convert(key.bounds, to: keyboard.view)
                    precondition(frame.width > 0 && frame.height > 0)
                    precondition(frame.minX >= 0 && frame.maxX <= width + 0.5)
                    precondition(frame.minY >= 0 && frame.maxY <= height + 0.5)
                }
                let frames = keys.map { key -> [String: Any] in
                    let f = key.convert(key.bounds, to: keyboard.view)
                    return ["key": key.accessibilityLabel ?? "", "frame": [f.minX, f.minY, f.width, f.height]]
                }
                let data = try! JSONSerialization.data(withJSONObject: frames, options: [.sortedKeys])
                print("GEOMETRY width=\(width) " + String(data: data, encoding: .utf8)!)
            }
            let host = window.rootViewController!
            host.addChild(keyboard)
            host.view.addSubview(keyboard.view)
            keyboard.didMove(toParent: host)
            for style: UIUserInterfaceStyle in [.light, .dark] {
                window.overrideUserInterfaceStyle = style
                keyboard.overrideUserInterfaceStyle = style
                keyboard.view.overrideUserInterfaceStyle = style
                window.layoutIfNeeded()
                keyboard.view.layoutIfNeeded()
                precondition(self.buttons(in: keyboard.view).allSatisfy { $0.traitCollection.userInterfaceStyle == style })
                let preview = UIGraphicsImageRenderer(size: keyboard.view.bounds.size).image { context in
                    UIColor(white: style == .dark ? 0.15 : 0.82, alpha: 1).setFill()
                    context.fill(keyboard.view.bounds)
                    keyboard.view.layer.render(in: context.cgContext)
                }
                let filename = style == .dark ? "keyboard-startup-dark.png" : "keyboard-startup.png"
                let previewURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(filename)
                try! preview.pngData()!.write(to: previewURL)
                print("PREVIEW \(previewURL.path)")
                let traits = UITraitCollection(userInterfaceStyle: style)
                for label in self.labels(in: keyboard.view) where !(label.text ?? "").isEmpty {
                    precondition(label.textColor.resolvedColor(with: traits).isEqual(UIColor.label.resolvedColor(with: traits)))
                }
            }
            for (base, alternate) in [("о", "ө"), ("у", "ү"), ("е", "ё"), ("ь", "ъ")] {
                let key = self.buttons(in: keyboard.view).first { $0.title(for: .normal) == base }!
                key.pressBeganAction?()
                key.longPressBeganAction?(CGPoint(x: 150, y: 100))
                precondition(self.labels(in: keyboard.view).contains { $0.text == alternate })
                key.longPressCancelledAction?()
                precondition(!self.labels(in: keyboard.view).contains { $0.text == alternate })
            }
            // Check the outer view's fitting height without supplying a height.
            // The key-frame checks above assign one and cannot validate sizing.
            let sizingKeyboard = KeyboardViewController()
            sizingKeyboard.loadViewIfNeeded()
            for width: CGFloat in [393, 852, 393] {
                sizingKeyboard.view.bounds.size = CGSize(width: width, height: 500)
                sizingKeyboard.view.setNeedsLayout()
                sizingKeyboard.view.layoutIfNeeded()
                let expectedHeight = KeyboardMetrics(width: width, traits: sizingKeyboard.traitCollection).keyboardHeight
                let fitted = sizingKeyboard.view.systemLayoutSizeFitting(
                    CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                    withHorizontalFittingPriority: .required,
                    verticalFittingPriority: .fittingSizeLevel
                )
                precondition(abs(fitted.height - expectedHeight) < 0.5, "Incorrect keyboard fitting height")
            }
            let warmTimes = times.dropFirst().sorted()
            let warmMedian = (warmTimes[14] + warmTimes[15]) / 2
            print("BENCHMARK first_ms=\(times[0]) warm_median_ms=\(warmMedian) checks=passed")
            fflush(stdout)
            exit(0)
        }
        return true
    }
    func checkRouting(in view: UIView) {
        let keys = buttons(in: view)
        func findRouter(_ view: UIView) -> KeyboardTouchRouterView? {
            if let router = view as? KeyboardTouchRouterView { return router }
            return view.subviews.lazy.compactMap { findRouter($0) }.first
        }
        findRouter(view)!.checkKeyCenters(keys)
    }
    func labels(in view: UIView) -> [UILabel] {
        view.subviews.flatMap { ($0 as? UILabel).map { [$0] } ?? labels(in: $0) }
    }
    func buttons(in view: UIView) -> [KeyboardButton] {
        view.subviews.flatMap { ($0 as? KeyboardButton).map { [$0] } ?? buttons(in: $0) }
    }
}
private extension KeyboardTouchRouterView {
    func checkKeyCenters(_ keys: [KeyboardButton]) {
        for key in keys {
            let point = key.convert(CGPoint(x: key.bounds.midX, y: key.bounds.midY), to: self)
            precondition(nearestButton(at: point) === key, "Touch routing missed a key after layout/page change")
        }
    }
}

UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(Delegate.self))
