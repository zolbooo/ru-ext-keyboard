import UIKit

private var checks = 0
private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        print("SPACE_CURSOR FAILED: \(message)")
        exit(1)
    }
    checks += 1
}

private extension KeyboardTouchRouterView {
    func activateForCheck(at point: CGPoint) -> UITouch {
        let touch = UITouch()
        let time = ProcessInfo.processInfo.systemUptime
        beginTouch(touch, at: point, time: time)
        activateCursor(touch, active: activeTouches[touch]!, time: time)
        return touch
    }

    func moveForCheck(_ touch: UITouch, to point: CGPoint) {
        moveTouch(touch, to: point, time: ProcessInfo.processInfo.systemUptime)
    }

    func runCursorChecks() {
        let space = KeyboardButton()
        space.isCursorKey = true
        space.frame = CGRect(x: 100, y: 100, width: 200, height: 44)
        let letter = KeyboardButton()
        letter.isRoutableCharacter = true
        letter.frame = CGRect(x: 0, y: 0, width: 100, height: 44)
        let delete = KeyboardButton()
        delete.frame = CGRect(x: 300, y: 0, width: 60, height: 44)
        [space, letter, delete].forEach(addSubview)
        buttons = [space, letter, delete]
        var spaces = 0, letters = 0, deletesStarted = 0, deletesEnded = 0, variantsCancelled = 0
        var offsets: [Int] = []
        space.tapAction = { spaces += 1 }
        letter.tapAction = { letters += 1 }
        letter.longPressBeganAction = { _ in }
        letter.longPressCancelledAction = { variantsCancelled += 1 }
        delete.pressBeganAction = { deletesStarted += 1 }
        delete.pressEndedAction = { deletesEnded += 1 }
        cursorModeChanged = { [weak self] enabled in self?.buttons.forEach { $0.setCursorMode(enabled) } }
        moveCursor = { offsets.append($0) }
        let center = CGPoint(x: 200, y: 120)
        let letterPoint = CGPoint(x: 50, y: 20)
        var time = ProcessInfo.processInfo.systemUptime

        func start() -> UITouch {
            let touch = UITouch()
            beginTouch(touch, at: center, time: time)
            return touch
        }
        func hold(_ touch: UITouch) {
            check(activeTouches[touch]?.longPressTimer != nil, "Space must schedule activation")
            time += 0.375
            activateCursor(touch, active: activeTouches[touch]!, time: time)
            check(cursorTouch === touch && cursorModeEnabled, "Space should capture cursor gesture")
            check(!space.isHighlighted, "Activation should remove the key highlight")
        }
        func reset() {
            cancelAllTouches()
            check(activeTouches.isEmpty && cursorTouch == nil && continuationTimer == nil, "Cancellation must clear all gesture state")
            check(!cursorModeEnabled && buttons.allSatisfy { !$0.isHighlighted && $0.isAccessibilityElement }, "Restore key presentation")
            time += 1
        }

        var touch = start()
        check(!cursorModeEnabled, "Touch down must not activate immediately")
        let tapTimer = activeTouches[touch]!.longPressTimer!
        endTouch(touch, at: center, time: time + 0.1)
        tapTimer.fire()
        check(spaces == 1 && !cursorModeEnabled, "Short Space tap inserts once and cancels activation")

        touch = start()
        let cancelledTimer = activeTouches[touch]!.longPressTimer!
        moveTouch(touch, to: CGPoint(x: 217, y: 120), time: time + 0.1)
        check(activeTouches[touch]?.longPressTimer == nil, "17-point drift must cancel hold")
        cancelledTimer.fire()
        check(!cursorModeEnabled, "Cancelled timer cannot activate later")
        endTouch(touch, at: center, time: time + 0.2)
        check(spaces == 2, "Failed hold still permits a normal Space tap")

        touch = start()
        moveTouch(touch, to: CGPoint(x: 216, y: 120), time: time + 0.1)
        check(activeTouches[touch]?.longPressTimer != nil, "16-point drift remains allowed")
        hold(touch)
        check(offsets.isEmpty, "Reset movement origin on activation")
        moveTouch(touch, to: CGPoint(x: 224, y: 120), time: time + 0.02)
        check(offsets == [2], "Native 8-point acceleration should yield two character steps")
        moveTouch(touch, to: CGPoint(x: 224, y: 190), time: time + 0.04)
        check(offsets == [2], "Pure vertical motion must not move the cursor")
        moveTouch(touch, to: CGPoint(x: 216, y: 190), time: time + 0.06)
        check(offsets == [2, -2], "Reversal should move back without accumulated travel debt")
        let extra = UITouch()
        beginTouch(extra, at: letterPoint, time: time + 0.07)
        endTouch(extra, at: letterPoint, time: time + 0.08)
        check(letters == 0, "Extra fingers must not type while scrubbing")
        endTouch(touch, at: CGPoint(x: 216, y: 190), time: time + 0.09)
        check(spaces == 2 && !cursorModeEnabled, "Release outside Space exits without inserting")
        reset()

        touch = start()
        hold(touch)
        endTouch(touch, at: center, time: time + 0.3)
        check(cursorModeEnabled && continuationTimer != nil, "Careful release keeps a re-grab window")
        let expiredTimer = continuationTimer!
        time += 0.4
        let regrab = start()
        check(cursorTouch === regrab && activeTouches[regrab]?.longPressTimer == nil, "Quick re-grab must activate immediately")
        expiredTimer.fire()
        check(cursorTouch === regrab, "Old continuation timer must not interrupt re-grab")
        endTouch(regrab, at: center, time: time + 0.3)
        let nextLetter = UITouch()
        beginTouch(nextLetter, at: letterPoint, time: time + 0.4)
        check(!cursorModeEnabled, "A different key ends continuation immediately")
        endTouch(nextLetter, at: letterPoint, time: time + 0.45)
        check(letters == 1 && spaces == 2, "Normal typing resumes after continuation")
        reset()

        touch = start()
        hold(touch)
        endTouch(touch, at: center, time: time + 0.3)
        continuationTimer!.fire()
        check(!cursorModeEnabled, "Continuation timer restores keyboard")
        time += 1
        touch = start()
        check(cursorTouch == nil && activeTouches[touch]?.longPressTimer != nil, "Expired re-grab requires a fresh hold")
        reset()

        let deleting = UITouch()
        beginTouch(deleting, at: CGPoint(x: 330, y: 20), time: time)
        touch = start()
        hold(touch)
        check(deletesStarted == 1 && deletesEnded == 1, "Cursor activation stops an active backspace hold")
        endTouch(deleting, at: CGPoint(x: 330, y: 20), time: time + 0.1)
        check(deletesEnded == 1, "Cancelled backspace touch cannot fire again")
        reset()

        let variant = UITouch()
        beginTouch(variant, at: letterPoint, time: time)
        activeTouches[variant]!.longPressTimer!.fire()
        touch = start()
        hold(touch)
        check(variantsCancelled == 1 && variantTouch == nil, "Activation dismisses an existing variant gesture")
        endTouch(variant, at: letterPoint, time: time + 0.1)
        check(letters == 1, "Cancelled variant touch must not insert")
        reset()

        touch = start()
        hold(touch)
        cancel(touch)
        check(!cursorModeEnabled && continuationTimer == nil && spaces == 2, "System cancellation never inserts Space or re-grabs")
        reset()
        // Exercise the real timer callback too, independent of physical touch delivery.
        touch = start()
        activeTouches[touch]!.longPressTimer!.fire()
        check(cursorTouch === touch, "Scheduled activation callback must capture the touch")
        reset()
    }
}

private extension KeyboardViewController {
    func runLifecycleChecks() {
        loadViewIfNeeded()
        view.frame = CGRect(x: 0, y: 0, width: 393, height: 216)
        view.layoutIfNeeded()
        let space = touchRouter.buttons.first { $0.isCursorKey }!
        let center = space.convert(CGPoint(x: space.bounds.midX, y: space.bounds.midY), to: touchRouter)
        let touch = touchRouter.activateForCheck(at: center)
        check(cursorDocumentIdentifier != nil, "Capture document identity")
        check(touchRouter.buttons.allSatisfy { !$0.isAccessibilityElement }, "Hide blank keys from accessibility")
        for button in touchRouter.buttons { button.checkLegends(hidden: true) }
        savePreview("cursor-active")
        viewWillDisappear(false)
        check(cursorDocumentIdentifier == nil, "Disappearance clears document identity")
        check(touchRouter.buttons.allSatisfy { $0.isAccessibilityElement }, "Restore accessibility")
        for button in touchRouter.buttons { button.checkLegends(hidden: false) }
        savePreview("cursor-inactive")
        // No cursor or Space action may leak after dismissal.
        touchRouter.moveForCheck(touch, to: CGPoint(x: center.x + 40, y: center.y))
        _ = touchRouter.activateForCheck(at: center)
        view.bounds.size.width = 852
        view.setNeedsLayout()
        view.layoutIfNeeded()
        check(cursorDocumentIdentifier == nil, "Layout change cancels cursor mode")
        beginBackspace()
        viewWillDisappear(false)
        check(backspaceRepeatTimer == nil, "Disappearance stops backspace timer")
    }

    func scrubForCheck(distance: CGFloat = 8) {
        let space = touchRouter.buttons.first { $0.isCursorKey }!
        let center = space.convert(CGPoint(x: space.bounds.midX, y: space.bounds.midY), to: touchRouter)
        let touch = touchRouter.activateForCheck(at: center)
        touchRouter.moveForCheck(touch, to: CGPoint(x: center.x + distance, y: center.y))
        touchRouter.cancelAllTouches()
    }

    private func savePreview(_ name: String) {
        view.layoutIfNeeded()
        view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: view.bounds.size).image { context in
            UIColor(white: 0.82, alpha: 1).setFill()
            context.fill(view.bounds)
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name + ".png")
        try! image.pngData()!.write(to: path)
        print("PREVIEW \(path.path)")
    }
}

private extension KeyboardButton {
    func checkLegends(hidden: Bool) {
        check(storedTitleLabel == nil || storedTitleLabel!.alpha == (hidden ? 0 : 1), "Text legend visibility")
        check(storedImageView == nil || storedImageView!.alpha == (hidden ? 0 : 1), "Icon visibility")
    }
}

private final class CursorEditor: UITextView {
    let keyboard = KeyboardViewController()
    override var inputViewController: UIInputViewController? { keyboard }

}

private func checkMotion() {
    var motion = SpaceCursorMotion(origin: .zero, time: 0)
    var total = 0
    for i in 1...7 { total += motion.move(to: CGPoint(x: i, y: 0), time: Double(i) / 100) }
    check(total == 0, "Sub-character movement accumulates without jumping")
    total += motion.move(to: CGPoint(x: 8, y: 0), time: 0.08)
    check(total == 1, "Accumulated small movement crosses one character")
    let finish = motion.finish(at: CGPoint(x: 15, y: 0), time: 0.4)
    check(finish.careful && finish.offset == 0, "Careful lift suppresses terminal jitter")
    motion = SpaceCursorMotion(origin: .zero, time: 0)
    let fast = motion.finish(at: CGPoint(x: 32, y: 0), time: 0.05)
    check(!fast.careful && fast.offset == 4, "Fast terminal motion is unaccelerated")
    motion = SpaceCursorMotion(origin: .zero, time: 0)
    _ = motion.move(to: CGPoint(x: 80, y: 0), time: 0.1)
    check(!motion.finish(at: CGPoint(x: 100, y: 0), time: 0.21).careful, "Fast release must not start continuation")
    motion = SpaceCursorMotion(origin: .zero, time: 0)
    _ = motion.move(to: CGPoint(x: 80, y: 0), time: 0.1)
    check(motion.finish(at: CGPoint(x: 80, y: 0), time: 1).careful, "Stationary pause restores careful placement")
}

private func checkUnicodeProxy(_ editor: CursorEditor, completion: @escaping () -> Void) {
    let original = editor.text!
    let text = original as NSString
    var cases: [(start: Int, distance: CGFloat, expected: Int)] = []
    for character in ["Б", "👨‍👩‍👧‍👦", "🇲🇳", "е\u{301}"] {
        let range = text.range(of: character)
        cases.append((range.location, 6, NSMaxRange(range)))
        cases.append((NSMaxRange(range), -6, range.location))
    }
    cases.append((0, -6, 0))
    cases.append((text.length, 6, text.length))
    func run(_ index: Int) {
        guard index < cases.count else { completion(); return }
        let item = cases[index]
        editor.selectedRange = NSRange(location: item.start, length: 0)
        editor.keyboard.scrubForCheck(distance: item.distance)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            check(editor.selectedRange.location == item.expected,
                  "Proxy character boundary: from \(item.start), got \(editor.selectedRange.location), expected \(item.expected)")
            check(editor.text == original, "Scrubbing Unicode never edits text")
            run(index + 1)
        }
    }
    run(0)
}

private final class CursorTestDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        setbuf(stdout, nil)
        let window = UIWindow(frame: UIScreen.main.bounds)
        self.window = window
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        DispatchQueue.main.async {
            checkMotion()
            KeyboardTouchRouterView().runCursorChecks()
            let editor = CursorEditor(frame: CGRect(x: 0, y: 60, width: 360, height: 240))
            editor.text = "АБВГД 👨‍👩‍👧‍👦 🇲🇳 е\u{301} конец"
            window.rootViewController!.view.addSubview(editor)
            editor.becomeFirstResponder()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let original = editor.text!
                editor.selectedRange = NSRange(location: 1, length: 0)
                editor.keyboard.scrubForCheck()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    check(editor.selectedRange.location == 3, "Real document proxy moves two positions through the controller callback")
                    check(editor.text == original, "Cursor gesture must leave text unchanged")
                    checkUnicodeProxy(editor) {
                        editor.keyboard.runLifecycleChecks()
                        print("SPACE_CURSOR checks=\(checks) passed")
                        exit(0)
                    }
                }
            }
        }
        return true
    }
}
UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(CursorTestDelegate.self))
