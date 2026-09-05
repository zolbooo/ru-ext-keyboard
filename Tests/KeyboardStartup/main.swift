import UIKit

final class Delegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
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
                    keyboard.loadViewIfNeeded()
                    keyboard.view.frame = CGRect(x: 0, y: 0, width: 393, height: 216)
                    keyboard.view.setNeedsLayout()
                    keyboard.view.layoutIfNeeded()
                    times.append((CACurrentMediaTime() - start) * 1000)
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
                    precondition(self.buttons(in: keyboard.view).contains { $0.title(for: .normal) == "≠" || $0.title(for: .normal) == "=" })
                    self.buttons(in: keyboard.view).first { $0.accessibilityLabel == "Буквы" }!.sendActions(for: .touchUpInside)
                    keyboard.view.layoutIfNeeded()
                    self.checkRouting(in: keyboard.view)
                    precondition(self.buttons(in: keyboard.view).contains { $0.title(for: .normal) == "й" })
                }
            }
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
            for (base, alternate) in [("о", "ө"), ("у", "ү"), ("е", "ё"), ("ь", "ъ")] {
                let key = self.buttons(in: keyboard.view).first { $0.title(for: .normal) == base } as! KeyboardButton
                key.pressBeganAction?()
                key.longPressBeganAction?(CGPoint(x: 150, y: 100))
                precondition(self.labels(in: keyboard.view).contains { $0.text == alternate })
                key.longPressCancelledAction?()
                precondition(!self.labels(in: keyboard.view).contains { $0.text == alternate })
            }
            print("BENCHMARK first_ms=\(times[0]) warm_median_ms=\(times.dropFirst().sorted()[15]) checks=passed")
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
    func buttons(in view: UIView) -> [UIButton] {
        view.subviews.flatMap { ($0 as? UIButton).map { [$0] } ?? buttons(in: $0) }
    }
}
private extension KeyboardTouchRouterView {
    func checkKeyCenters(_ keys: [UIButton]) {
        for key in keys {
            let point = key.convert(CGPoint(x: key.bounds.midX, y: key.bounds.midY), to: self)
            precondition(nearestButton(at: point) === key, "Touch routing missed a key after layout/page change")
        }
    }
}

UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(Delegate.self))
