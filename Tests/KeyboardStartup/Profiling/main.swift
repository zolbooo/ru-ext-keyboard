import UIKit

private var firstConstructions = 0
private var repeatedConstructions = 0

// Preserve named measurement boundaries. Checked versus wrapping counter updates
// keep their bodies distinct even under function merging. Keyboard code stays optimized.
@inline(never)
@_optimize(none)
func profileFirstKeyboardStartup() -> KeyboardViewController {
    let keyboard = KeyboardViewController()
    keyboard.loadViewIfNeeded()
    keyboard.view.frame = CGRect(x: 0, y: 0, width: 393, height: 216)
    keyboard.view.setNeedsLayout()
    keyboard.view.layoutIfNeeded()
    firstConstructions += 1
    return keyboard
}

@inline(never)
@_optimize(none)
func profileRepeatedKeyboardStartup() -> KeyboardViewController {
    let keyboard = KeyboardViewController()
    keyboard.loadViewIfNeeded()
    keyboard.view.frame = CGRect(x: 0, y: 0, width: 393, height: 216)
    keyboard.view.setNeedsLayout()
    keyboard.view.layoutIfNeeded()
    repeatedConstructions &+= 1
    return keyboard
}

private final class ProfileDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        self.window = window
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        let dataDirectory = URL(fileURLWithPath: NSHomeDirectory())
        try! Data().write(to: dataDirectory.appendingPathComponent("profile-ready"))
        let marker = dataDirectory.appendingPathComponent("start-profile")
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            guard FileManager.default.fileExists(atPath: marker.path) else { return }
            timer.invalidate()
            autoreleasepool {
                let start = CACurrentMediaTime()
                let keyboard = profileFirstKeyboardStartup()
                print("PROFILE first_ms=\((CACurrentMediaTime() - start) * 1000)")
                withExtendedLifetime(keyboard) {}
            }
            for _ in 0..<500 {
                autoreleasepool {
                    let keyboard = profileRepeatedKeyboardStartup()
                    withExtendedLifetime(keyboard) {}
                }
            }
            print("PROFILE completed first=1 repeated=500")
            fflush(stdout)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { exit(0) }
        }
        return true
    }
}
UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(ProfileDelegate.self))
