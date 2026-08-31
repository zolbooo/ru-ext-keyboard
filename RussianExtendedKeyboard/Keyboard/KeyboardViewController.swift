import NaturalLanguage
import UIKit

final class KeyboardViewController: UIInputViewController {
    private enum BackspaceTiming {
        static let initialRepeatDelay: TimeInterval = 0.5
        static let characterRepeatInterval: TimeInterval = 0.1
        static let wordRepeatInterval: TimeInterval = 0.3
        static let characterRepeatsBeforeWords = 20
    }

    private enum Page {
        case letters
        case symbols
        case moreSymbols
    }

    private let letterRows = [
        ["й", "ц", "у", "к", "е", "н", "г", "ш", "щ", "з", "х"],
        ["ф", "ы", "в", "а", "п", "р", "о", "л", "д", "ж", "э"],
        ["я", "ч", "с", "м", "и", "т", "ь", "б", "ю"]
    ]

    private let symbolRows = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["-", "/", ":", ";", "(", ")", "₽", "&", "@", "\""] ,
        [".", ",", "?", "!", "'"]
    ]

    private let moreSymbolRows = [
        ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
        ["_", "\\", "|", "~", "<", ">", "$", "€", "£", "•"],
        [".", ",", "?", "!", "'"]
    ]

    private let keyboardStack = UIStackView()
    private let touchRouter = KeyboardTouchRouterView()
    private weak var layoutContainer: UIView?
    private var page: Page = .letters
    private var shifted = false
    private var characterKeys: [(button: KeyboardButton, character: String)] = []
    private var rowStacks: [UIStackView] = []
    private var bottomSideKeyConstraints: [NSLayoutConstraint] = []
    private var bottomUtilityKeyConstraint: NSLayoutConstraint?
    private var appliedMetrics: KeyboardMetrics?
    private var keyboardHeightConstraint: NSLayoutConstraint!
    private var keyboardTopConstraint: NSLayoutConstraint!
    private var keyboardLeadingConstraint: NSLayoutConstraint!
    private var keyboardTrailingConstraint: NSLayoutConstraint!
    private var keyboardBottomConstraint: NSLayoutConstraint!
    private var variantPresentationFeedback: UIImpactFeedbackGenerator!
    private var variantSelectionFeedback: UISelectionFeedbackGenerator!
    private var variantPopup: VariantPopup?
    private var backspaceRepeatTimer: Timer?
    private var backspaceRepeatCount = 0
    private let backspaceWordTokenizer = NLTokenizer(unit: .word)
    private weak var returnKey: KeyboardButton?

    override func viewDidLoad() {
        super.viewDidLoad()
        configureRootView()
        rebuildKeyboard()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateLayoutMetrics()
        if let layoutContainer {
            layoutContainer.bringSubviewToFront(touchRouter)
        }
    }

    deinit {
        touchRouter.cancelAllTouches()
        backspaceRepeatTimer?.invalidate()
    }

    private func configureRootView() {
        view.backgroundColor = .clear
        view.isOpaque = false
        view.clipsToBounds = false
        inputView?.backgroundColor = .clear
        inputView?.isOpaque = false
        inputView?.clipsToBounds = false

        guard let container = inputView ?? view else { return }
        layoutContainer = container
        configureVariantFeedback(for: container)

        keyboardStack.axis = .vertical
        keyboardStack.distribution = .fillEqually
        keyboardStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(keyboardStack)

        touchRouter.translatesAutoresizingMaskIntoConstraints = false
        touchRouter.buttonsProvider = { [weak self] in
            self?.rowStacks.flatMap { row in
                row.arrangedSubviews.compactMap { $0 as? KeyboardButton }
            } ?? []
        }
        container.addSubview(touchRouter)

        keyboardHeightConstraint = container.heightAnchor.constraint(equalToConstant: 276)
        keyboardTopConstraint = keyboardStack.topAnchor.constraint(equalTo: container.topAnchor)
        keyboardLeadingConstraint = keyboardStack.leadingAnchor.constraint(equalTo: container.leadingAnchor)
        keyboardTrailingConstraint = keyboardStack.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        keyboardBottomConstraint = keyboardStack.bottomAnchor.constraint(equalTo: container.bottomAnchor)

        NSLayoutConstraint.activate([
            keyboardHeightConstraint,
            keyboardTopConstraint,
            keyboardLeadingConstraint,
            keyboardTrailingConstraint,
            keyboardBottomConstraint,
            touchRouter.topAnchor.constraint(equalTo: container.topAnchor),
            touchRouter.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            touchRouter.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            touchRouter.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        updateReturnKey()
    }

    private func rebuildKeyboard() {
        touchRouter.cancelAllTouches()
        dismissVariantPopup()
        characterKeys.removeAll()
        rowStacks.removeAll()
        bottomSideKeyConstraints.removeAll()
        bottomUtilityKeyConstraint = nil
        keyboardStack.arrangedSubviews.forEach {
            keyboardStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let rows: [[String]]
        switch page {
        case .letters:
            rows = letterRows
        case .symbols:
            rows = symbolRows
        case .moreSymbols:
            rows = moreSymbolRows
        }
        keyboardStack.addArrangedSubview(makeCharacterRow(rows[0]))
        keyboardStack.addArrangedSubview(makeCharacterRow(rows[1]))
        keyboardStack.addArrangedSubview(makeThirdRow(rows[2]))
        keyboardStack.addArrangedSubview(makeBottomRow())
        updateLayoutMetrics(force: true)
    }

    private func makeCharacterRow(_ characters: [String]) -> UIView {
        let row = makeRow()
        characters.forEach { row.addArrangedSubview(makeCharacterKey($0)) }
        return row
    }

    private func makeThirdRow(_ characters: [String]) -> UIView {
        let row = makeRow()

        let leading: KeyboardButton
        switch page {
        case .letters:
            leading = makeIconKey("shift", accessibilityLabel: "Сдвиг", style: .character)
        case .symbols:
            leading = makeKey(title: "#+=", style: .character, action: nil)
            leading.accessibilityLabel = "Дополнительные символы"
        case .moreSymbols:
            leading = makeKey(title: "123", style: .character, action: nil)
            leading.accessibilityLabel = "Цифры"
        }
        if page != .letters {
            leading.titleLabel?.font = .systemFont(ofSize: 16)
        }
        leading.tapAction = { [weak self, weak leading] in
            guard let self else { return }
            switch self.page {
            case .letters:
                self.shifted.toggle()
                leading?.setImage(
                    UIImage(systemName: self.shifted ? "shift.fill" : "shift"),
                    for: .normal
                )
                leading?.setSelectedStyle(self.shifted)
                self.updateCharacterKeys()
            case .symbols:
                self.page = .moreSymbols
                self.rebuildKeyboard()
            case .moreSymbols:
                self.page = .symbols
                self.rebuildKeyboard()
            }
        }
        row.addArrangedSubview(leading)
        characters.forEach { row.addArrangedSubview(makeCharacterKey($0)) }

        let delete = makeIconKey("delete.left", accessibilityLabel: "Удалить", style: .character)
        delete.pressBeganAction = { [weak self] in
            self?.beginBackspace()
        }
        delete.pressEndedAction = { [weak self] in
            self?.endBackspace()
        }
        row.addArrangedSubview(delete)
        return row
    }

    private func beginBackspace() {
        endBackspace()
        textDocumentProxy.deleteBackward()
        scheduleBackspaceRepeat(after: BackspaceTiming.initialRepeatDelay)
    }

    private func scheduleBackspaceRepeat(after delay: TimeInterval) {
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }

            if self.backspaceRepeatCount < BackspaceTiming.characterRepeatsBeforeWords {
                self.textDocumentProxy.deleteBackward()
                self.backspaceRepeatCount += 1
                let nextDelay = self.backspaceRepeatCount
                    == BackspaceTiming.characterRepeatsBeforeWords
                    ? BackspaceTiming.wordRepeatInterval
                    : BackspaceTiming.characterRepeatInterval
                self.scheduleBackspaceRepeat(after: nextDelay)
            } else {
                let deletedWord = self.deletePreviousWord()
                self.scheduleBackspaceRepeat(
                    after: deletedWord
                        ? BackspaceTiming.wordRepeatInterval
                        : BackspaceTiming.characterRepeatInterval
                )
            }
        }
        backspaceRepeatTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @discardableResult
    private func deletePreviousWord() -> Bool {
        guard let context = textDocumentProxy.documentContextBeforeInput,
              !context.isEmpty else {
            textDocumentProxy.deleteBackward()
            return false
        }

        backspaceWordTokenizer.string = context
        guard let tokenRange = backspaceWordTokenizer
            .tokens(for: context.startIndex..<context.endIndex)
            .last else {
            textDocumentProxy.deleteBackward()
            return false
        }
        let characterCount = context[tokenRange.lowerBound..<context.endIndex].count
        for _ in 0..<characterCount {
            textDocumentProxy.deleteBackward()
        }
        return true
    }

    private func endBackspace() {
        backspaceRepeatTimer?.invalidate()
        backspaceRepeatTimer = nil
        backspaceRepeatCount = 0
    }

    private func makeBottomRow() -> UIView {
        let row = makeRow()
        row.distribution = .fill

        let pageKey = makeKey(
            title: page == .letters ? "123" : "АБВ",
            style: .character
        ) { [weak self] in
            guard let self else { return }
            self.page = self.page == .letters ? .symbols : .letters
            self.shifted = false
            self.rebuildKeyboard()
        }
        pageKey.accessibilityLabel = page == .letters ? "Цифры" : "Буквы"
        pageKey.titleLabel?.font = .systemFont(ofSize: 16)
        row.addArrangedSubview(pageKey)
        bottomSideKeyConstraints.append(pageKey.widthAnchor.constraint(equalToConstant: 76))

        let nextKeyboard = makeIconKey(
            "globe",
            accessibilityLabel: "Следующая клавиатура",
            style: .character
        ) { [weak self] in
            self?.advanceToNextInputMode()
        }
        nextKeyboard.accessibilityHint = "Переключает на следующую установленную клавиатуру"
        row.addArrangedSubview(nextKeyboard)
        let utilityConstraint = nextKeyboard.widthAnchor.constraint(equalToConstant: 42)
        bottomUtilityKeyConstraint = utilityConstraint

        let space = makeKey(title: "", style: .character) { [weak self] in
            self?.insert(" ")
        }
        space.accessibilityLabel = "Пробел"
        space.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(space)

        let enter = makeIconKey("return", accessibilityLabel: "Ввод", style: .character) { [weak self] in
            self?.insert("\n")
        }
        row.addArrangedSubview(enter)
        bottomSideKeyConstraints.append(enter.widthAnchor.constraint(equalToConstant: 76))
        NSLayoutConstraint.activate(bottomSideKeyConstraints + [utilityConstraint])
        returnKey = enter
        updateReturnKey()
        return row
    }

    private func updateReturnKey() {
        guard let returnKey else { return }

        returnKey.setImage(nil, for: .normal)
        returnKey.setTitle(nil, for: .normal)
        let returnKeyType = textDocumentProxy.returnKeyType
        switch returnKeyType {
        case .search:
            returnKey.setImage(UIImage(systemName: "magnifyingglass"), for: .normal)
            returnKey.accessibilityLabel = "Найти"
        case .done:
            returnKey.setImage(UIImage(systemName: "checkmark"), for: .normal)
            returnKey.accessibilityLabel = "Готово"
        case .go:
            returnKey.setImage(UIImage(systemName: "arrow.right"), for: .normal)
            returnKey.accessibilityLabel = "Перейти"
        case .next:
            returnKey.setImage(UIImage(systemName: "arrow.right.to.line"), for: .normal)
            returnKey.accessibilityLabel = "Далее"
        case .send:
            returnKey.setImage(UIImage(systemName: "paperplane.fill"), for: .normal)
            returnKey.accessibilityLabel = "Отправить"
        default:
            returnKey.setImage(UIImage(systemName: "return"), for: .normal)
            returnKey.accessibilityLabel = "Ввод"
        }
        returnKey.setActionStyle(false)
    }

    private func makeCharacterKey(_ character: String) -> KeyboardButton {
        let key = makeKey(title: character, style: .character) { [weak self] in
            guard let self else { return }
            self.insert(self.shifted ? character.uppercased() : character)
            self.resetShiftIfNeeded()
        }
        characterKeys.append((key, character))
        key.isRoutableCharacter = true

        if !variants(for: character).isEmpty {
            key.pressBeganAction = { [weak self] in
                self?.prepareVariantFeedback()
            }
            key.longPressBeganAction = { [weak self, weak key] location in
                guard let self, let key else { return }
                self.beginVariantSelection(
                    character: character,
                    from: key,
                    at: self.view.convert(location, from: self.touchRouter)
                )
            }
            key.longPressMovedAction = { [weak self] location in
                guard let self else { return }
                self.updateVariantSelection(
                    at: self.view.convert(location, from: self.touchRouter),
                    emitFeedback: true
                )
            }
            key.longPressEndedAction = { [weak self] location in
                guard let self else { return }
                self.endVariantSelection(at: self.view.convert(location, from: self.touchRouter))
            }
            key.longPressCancelledAction = { [weak self] in
                self?.dismissVariantPopup()
            }
        }
        updateCharacterKey(key, character: character)
        return key
    }

    private func updateCharacterKeys() {
        characterKeys.forEach { updateCharacterKey($0.button, character: $0.character) }
    }

    private func updateCharacterKey(_ key: KeyboardButton, character: String) {
        let displayed = shifted ? character.uppercased() : character
        if page == .letters {
            key.setNativeLetterStyle(shifted: shifted)
        }
        key.setTitle(displayed, for: .normal)
        key.accessibilityLabel = displayed
        let alternates = variants(for: character)
        key.accessibilityHint = alternates.isEmpty
            ? nil
            : "Удерживайте для \(alternates.joined(separator: ", "))"
    }

    private func variants(for character: String) -> [String] {
        switch character {
        case "е": return [shifted ? "Ё" : "ё"]
        case "о": return [shifted ? "Ө" : "ө"]
        case "у": return [shifted ? "Ү" : "ү"]
        case "ь": return [shifted ? "Ъ" : "ъ"]
        case "0": return ["°"]
        case "-": return ["–", "—", "•"]
        case "/": return ["\\"]
        case "₽": return ["$", "€", "£", "¥", "₮"]
        case "&": return ["§"]
        case "\"": return ["«", "»", "„", "“", "”"]
        case ".": return ["…"]
        case "?": return ["¿"]
        case "!": return ["¡"]
        case "'": return ["’", "‘", "`"]
        case "#": return ["№"]
        case "%": return ["‰"]
        case "=": return ["≠", "≈"]
        default: return []
        }
    }

    private func resetShiftIfNeeded() {
        guard shifted else { return }
        shifted = false
        updateCharacterKeys()
    }

    private func beginVariantSelection(
        character: String,
        from key: KeyboardButton,
        at location: CGPoint
    ) {
        let displayed = shifted ? character.uppercased() : character
        let alternates = variants(for: character)
        guard !alternates.isEmpty else { return }
        showVariants([displayed] + alternates, from: key)
        playVariantPresentationFeedback(at: location)
        variantSelectionFeedback.prepare()
    }

    private func endVariantSelection(at location: CGPoint) {
        updateVariantSelection(at: location, emitFeedback: true)
        if let value = variantPopup?.selectedValue {
            insert(value)
            resetShiftIfNeeded()
        }
        dismissVariantPopup()
    }

    private func showVariants(_ variants: [String], from key: UIView) {
        dismissVariantPopup()

        let keyFrame = key.convert(key.bounds, to: view)
        let optionWidth = max(42, keyFrame.width)
        let size = VariantPopup.preferredSize(optionCount: variants.count, optionWidth: optionWidth)
        let opensLeft = keyFrame.midX > view.bounds.midX
        let orderedVariants = opensLeft ? Array(variants.reversed()) : variants
        let baseIndex = opensLeft ? orderedVariants.count - 1 : 0
        let desiredX = keyFrame.midX
            - VariantPopup.horizontalPadding
            - (CGFloat(baseIndex) + 0.5) * optionWidth
        let x = min(max(4, desiredX), view.bounds.width - size.width - 4)
        let y = max(2, keyFrame.minY - size.height - 2)
        let popup = VariantPopup(
            values: orderedVariants,
            selectedIndex: baseIndex,
            optionWidth: optionWidth
        )
        popup.frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
        popup.layer.zPosition = 10
        view.addSubview(popup)
        view.bringSubviewToFront(popup)
        variantPopup = popup
    }

    private func updateVariantSelection(at location: CGPoint, emitFeedback: Bool) {
        guard let popup = variantPopup else { return }
        let localLocation = view.convert(location, to: popup)
        guard popup.selectValue(at: localLocation) else { return }
        if emitFeedback, popup.selectedValue != nil {
            if #available(iOS 17.5, *) {
                variantSelectionFeedback.selectionChanged(at: location)
            } else {
                variantSelectionFeedback.selectionChanged()
            }
            variantSelectionFeedback.prepare()
        }
    }

    private func configureVariantFeedback(for feedbackView: UIView) {
        if #available(iOS 17.5, *) {
            variantPresentationFeedback = UIImpactFeedbackGenerator(style: .rigid, view: feedbackView)
            variantSelectionFeedback = UISelectionFeedbackGenerator(view: feedbackView)
        } else {
            variantPresentationFeedback = UIImpactFeedbackGenerator(style: .rigid)
            variantSelectionFeedback = UISelectionFeedbackGenerator()
        }
    }

    private func prepareVariantFeedback() {
        variantPresentationFeedback.prepare()
        variantSelectionFeedback.prepare()
    }

    private func playVariantPresentationFeedback(at location: CGPoint) {
        if #available(iOS 17.5, *) {
            variantPresentationFeedback.impactOccurred(intensity: 0.85, at: location)
        } else {
            variantPresentationFeedback.impactOccurred(intensity: 0.85)
        }
    }

    private func dismissVariantPopup() {
        variantPopup?.removeFromSuperview()
        variantPopup = nil
    }

    private func makeRow() -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fillEqually
        rowStacks.append(row)
        return row
    }

    private func updateLayoutMetrics(force: Bool = false) {
        let containerWidth = layoutContainer?.bounds.width ?? view.bounds.width
        let width = containerWidth > 0 ? containerWidth : 320
        let metrics = KeyboardMetrics(width: width, traits: traitCollection)
        guard force || metrics != appliedMetrics else { return }
        appliedMetrics = metrics

        keyboardHeightConstraint.constant = metrics.keyboardHeight
        keyboardTopConstraint.constant = metrics.topInset
        keyboardLeadingConstraint.constant = metrics.horizontalInset
        keyboardTrailingConstraint.constant = -metrics.horizontalInset
        keyboardBottomConstraint.constant = -metrics.bottomInset
        keyboardStack.spacing = metrics.rowSpacing
        rowStacks.forEach { $0.spacing = metrics.keySpacing }
        bottomSideKeyConstraints.forEach { $0.constant = metrics.bottomSideKeyWidth }
        bottomUtilityKeyConstraint?.constant = metrics.bottomUtilityKeyWidth
    }

    private func makeSpecialKey(_ title: String, action: (() -> Void)?) -> KeyboardButton {
        makeKey(title: title, style: .special, action: action)
    }

    private func makeIconKey(
        _ systemName: String,
        accessibilityLabel: String,
        style: KeyboardButton.Style = .special,
        action: (() -> Void)? = nil
    ) -> KeyboardButton {
        let key = KeyboardButton(style: style)
        key.setImage(UIImage(systemName: systemName), for: .normal)
        key.accessibilityLabel = accessibilityLabel
        key.tapAction = action
        return key
    }

    private func makeKey(title: String, style: KeyboardButton.Style, action: (() -> Void)?) -> KeyboardButton {
        let key = KeyboardButton(style: style)
        key.setTitle(title, for: .normal)
        key.tapAction = action
        return key
    }

    private func insert(_ text: String) {
        textDocumentProxy.insertText(text)
    }

}

private struct KeyboardMetrics: Equatable {
    let keyboardHeight: CGFloat
    let topInset: CGFloat
    let bottomInset: CGFloat
    let horizontalInset: CGFloat
    let rowSpacing: CGFloat
    let keySpacing: CGFloat
    let bottomSideKeyWidth: CGFloat
    let bottomUtilityKeyWidth: CGFloat

    init(width: CGFloat, traits: UITraitCollection) {
        let isCompact = traits.verticalSizeClass == .compact || width >= 560

        if isCompact {
            // Preserve the existing key area while adding clearance below it.
            topInset = 2
            bottomInset = 8
            keyboardHeight = 159 + topInset + bottomInset
            rowSpacing = 5
            keySpacing = Self.clamp(width * 0.007, minimum: 3, maximum: 5)
            horizontalInset = keySpacing
            bottomSideKeyWidth = (width - 2 * horizontalInset) * 0.18
            bottomUtilityKeyWidth = Self.clamp(width * 0.08, minimum: 42, maximum: 60)
            return
        }

        // Four native 43-pt rows separated by three 11-pt gaps.
        topInset = 7
        bottomInset = 4
        keyboardHeight = 4 * 43 + 3 * 11 + topInset + bottomInset
        rowSpacing = 11
        keySpacing = 6
        horizontalInset = 20 / 3
        bottomSideKeyWidth = (width - 2 * horizontalInset) * 0.24
        bottomUtilityKeyWidth = Self.clamp(width * 0.12, minimum: 42, maximum: 60)
    }

    private static func clamp(_ value: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        min(max(value, minimum), maximum)
    }
}

private final class KeyboardButton: UIButton {
    enum Style {
        case character
        case special
    }

    var tapAction: (() -> Void)?
    var pressBeganAction: (() -> Void)?
    var pressEndedAction: (() -> Void)?
    var longPressBeganAction: ((CGPoint) -> Void)?
    var longPressMovedAction: ((CGPoint) -> Void)?
    var longPressEndedAction: ((CGPoint) -> Void)?
    var longPressCancelledAction: (() -> Void)?
    var isRoutableCharacter = false

    private let style: Style
    private var usesActionStyle = false
    private var usesSelectedStyle = false
    private var routedHighlightCount = 0

    init(style: Style) {
        self.style = style
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 6
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.18
        layer.shadowRadius = 0
        layer.shadowOffset = CGSize(width: 0, height: 1)
        titleLabel?.font = .systemFont(ofSize: style == .character ? 21 : 17)
        titleLabel?.adjustsFontSizeToFitWidth = true
        titleLabel?.minimumScaleFactor = 0.72
        setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 18, weight: .regular),
            forImageIn: .normal
        )
        applyAppearance()
        addTarget(self, action: #selector(pressed), for: .touchDown)
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        addTarget(
            self,
            action: #selector(pressEnded),
            for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit]
        )

    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            if isHighlighted {
                layer.removeAllAnimations()
                applyAppearance()
            } else {
                UIView.animate(
                    withDuration: 0.08,
                    delay: 0,
                    options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut]
                ) { [weak self] in
                    self?.applyAppearance()
                }
            }
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyAppearance()
    }

    func setActionStyle(_ enabled: Bool) {
        usesActionStyle = enabled
        applyAppearance()
    }

    func setSelectedStyle(_ enabled: Bool) {
        usesSelectedStyle = enabled
        applyAppearance()
    }

    func setNativeLetterStyle(shifted: Bool) {
        let fontSize: CGFloat = shifted ? 22 : 25
        let verticalOffset: CGFloat = shifted ? -1 : -2
        titleLabel?.font = .systemFont(ofSize: fontSize, weight: .regular)
        titleEdgeInsets = UIEdgeInsets(
            top: verticalOffset,
            left: 0,
            bottom: -verticalOffset,
            right: 0
        )
    }

    func beginRoutedHighlight() {
        routedHighlightCount += 1
        isHighlighted = true
    }

    func endRoutedHighlight() {
        routedHighlightCount = max(0, routedHighlightCount - 1)
        isHighlighted = routedHighlightCount > 0
    }

    private func applyAppearance() {
        if usesActionStyle {
            let pressedActionColor = UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 0.03, green: 0.36, blue: 0.76, alpha: 1)
                    : UIColor(red: 0, green: 0.38, blue: 0.80, alpha: 1)
            }
            backgroundColor = isHighlighted ? pressedActionColor : .systemBlue
            setTitleColor(.white, for: .normal)
            tintColor = .white
            return
        }

        let characterColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.34, alpha: 0.82)
                : UIColor(white: 1, alpha: 0.94)
        }
        let specialColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.24, alpha: 0.88)
                : UIColor(white: 0.62, alpha: 0.72)
        }
        let pressedCharacterColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.52, alpha: 0.96)
                : UIColor(white: 0.72, alpha: 0.96)
        }
        let usesCharacterColor = style == .character || usesSelectedStyle
        let normalColor = usesCharacterColor ? characterColor : specialColor
        let highlightedColor = usesCharacterColor ? pressedCharacterColor : characterColor
        backgroundColor = isHighlighted ? highlightedColor : normalColor
        setTitleColor(.label, for: .normal)
        tintColor = .label
    }

    @objc private func tapped() {
        tapAction?()
    }

    @objc private func pressed() {
        pressBeganAction?()
    }

    @objc private func pressEnded() {
        pressEndedAction?()
    }

}

private final class KeyboardTouchRouterView: UIView {
    private enum TrackingMode {
        case character
        case control
    }

    private final class ActiveTouch {
        let mode: TrackingMode
        let initialKey: KeyboardButton
        var currentKey: KeyboardButton?
        var latestLocation: CGPoint
        var longPressOrigin: CGPoint
        var longPressTimer: Timer?
        var isShowingVariants = false
        var isHighlighted = true
        var controlPressIsActive = false

        init(mode: TrackingMode, key: KeyboardButton, location: CGPoint) {
            self.mode = mode
            initialKey = key
            currentKey = key
            latestLocation = location
            longPressOrigin = location
        }
    }

    var buttonsProvider: (() -> [KeyboardButton])?

    private static let longPressDuration: TimeInterval = 0.42
    private static let longPressMovement: CGFloat = 22
    private var activeTouches: [UITouch: ActiveTouch] = [:]
    private weak var variantTouch: UITouch?

    override init(frame: CGRect) {
        super.init(frame: frame)
        // A fully transparent hosted-extension view does not contribute a remote
        // hit-test region in the empty space between its opaque button siblings.
        // Keep a visually imperceptible fill so those gaps still receive touches.
        backgroundColor = UIColor(white: 0, alpha: 0.001)
        isOpaque = false
        isMultipleTouchEnabled = true
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled, !isHidden, alpha > 0.01, self.point(inside: point, with: event) else {
            return nil
        }
        return self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        for touch in touches {
            let location = touch.location(in: self)
            guard let key = nearestButton(at: location) else { continue }
            let mode: TrackingMode = key.isRoutableCharacter ? .character : .control
            let active = ActiveTouch(mode: mode, key: key, location: location)
            activeTouches[touch] = active
            key.beginRoutedHighlight()
            key.pressBeganAction?()
            if mode == .control {
                active.controlPressIsActive = true
            } else {
                scheduleLongPress(for: touch, active: active, key: key)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        for touch in touches {
            guard let active = activeTouches[touch] else { continue }
            let location = touch.location(in: self)
            active.latestLocation = location

            if active.isShowingVariants {
                active.currentKey?.longPressMovedAction?(location)
                continue
            }

            switch active.mode {
            case .character:
                updateCharacterTouch(touch, active: active, at: location)
            case .control:
                updateControlTouch(active, at: location)
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        for touch in touches {
            guard let active = activeTouches.removeValue(forKey: touch) else { continue }
            active.longPressTimer?.invalidate()
            active.longPressTimer = nil
            let location = touch.location(in: self)

            if active.isShowingVariants {
                active.currentKey?.longPressEndedAction?(location)
                if variantTouch === touch { variantTouch = nil }
                continue
            }

            switch active.mode {
            case .character:
                if let key = active.currentKey {
                    key.tapAction?()
                    endHighlightIfNeeded(active, key: key)
                }
            case .control:
                let isInside = nearestButton(at: location) === active.initialKey
                if isInside {
                    active.initialKey.tapAction?()
                }
                if active.controlPressIsActive {
                    active.initialKey.pressEndedAction?()
                }
                endHighlightIfNeeded(active, key: active.initialKey)
            }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        for touch in touches {
            cancel(touch)
        }
    }

    func cancelAllTouches() {
        for touch in Array(activeTouches.keys) {
            cancel(touch)
        }
    }

    private func updateCharacterTouch(_ touch: UITouch, active: ActiveTouch, at location: CGPoint) {
        let nextKey = nearestButton(at: location).flatMap { key in
            key.isRoutableCharacter ? key : nil
        }

        if nextKey !== active.currentKey {
            active.longPressTimer?.invalidate()
            active.longPressTimer = nil
            if let currentKey = active.currentKey {
                endHighlightIfNeeded(active, key: currentKey)
            }
            active.currentKey = nextKey
            active.longPressOrigin = location
            if let nextKey {
                nextKey.beginRoutedHighlight()
                active.isHighlighted = true
                nextKey.pressBeganAction?()
                scheduleLongPress(for: touch, active: active, key: nextKey)
            }
            return
        }

        let movement = hypot(location.x - active.longPressOrigin.x, location.y - active.longPressOrigin.y)
        if movement > Self.longPressMovement {
            active.longPressTimer?.invalidate()
            active.longPressTimer = nil
        }
    }

    private func updateControlTouch(_ active: ActiveTouch, at location: CGPoint) {
        let isInside = nearestButton(at: location) === active.initialKey
        guard isInside != active.isHighlighted else { return }
        if isInside {
            active.initialKey.beginRoutedHighlight()
            active.isHighlighted = true
        } else {
            endHighlightIfNeeded(active, key: active.initialKey)
            if active.controlPressIsActive {
                active.initialKey.pressEndedAction?()
                active.controlPressIsActive = false
            }
        }
    }

    private func scheduleLongPress(for touch: UITouch, active: ActiveTouch, key: KeyboardButton) {
        guard key.longPressBeganAction != nil else { return }
        let timer = Timer(timeInterval: Self.longPressDuration, repeats: false) {
            [weak self, weak touch, weak active] _ in
            guard let self, let touch, let active,
                  self.variantTouch == nil,
                  let tracked = self.activeTouches[touch],
                  tracked === active,
                  tracked.currentKey === key else { return }
            tracked.longPressTimer = nil
            tracked.isShowingVariants = true
            self.variantTouch = touch
            self.endHighlightIfNeeded(tracked, key: key)
            key.longPressBeganAction?(tracked.latestLocation)
        }
        active.longPressTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func cancel(_ touch: UITouch) {
        guard let active = activeTouches.removeValue(forKey: touch) else { return }
        active.longPressTimer?.invalidate()
        active.longPressTimer = nil
        if active.isShowingVariants {
            active.currentKey?.longPressCancelledAction?()
            if variantTouch === touch { variantTouch = nil }
        } else if active.mode == .control, active.controlPressIsActive {
            active.initialKey.pressEndedAction?()
        }
        if let key = active.currentKey {
            endHighlightIfNeeded(active, key: key)
        }
    }

    private func endHighlightIfNeeded(_ active: ActiveTouch, key: KeyboardButton) {
        guard active.isHighlighted else { return }
        key.endRoutedHighlight()
        active.isHighlighted = false
    }

    private func nearestButton(at location: CGPoint) -> KeyboardButton? {
        guard let buttons = buttonsProvider?(), !buttons.isEmpty else { return nil }
        var nearest: KeyboardButton?
        var nearestDistance = CGFloat.greatestFiniteMagnitude

        for button in buttons where !button.isHidden && button.alpha > 0.01 {
            let frame = button.convert(button.bounds, to: self)
            let dx = max(frame.minX - location.x, 0, location.x - frame.maxX)
            let dy = max(frame.minY - location.y, 0, location.y - frame.maxY)
            let distance = dx * dx + dy * dy
            if distance < nearestDistance {
                nearest = button
                nearestDistance = distance
            }
        }
        return nearest
    }
}

private final class VariantPopup: UIView {
    static let horizontalPadding: CGFloat = 8

    private static let bodyHeight: CGFloat = 44
    private static let verticalContentInset: CGFloat = 2
    private static let selectionCornerRadius: CGFloat = 9

    private let values: [String]
    private let labels: [UILabel]
    private let optionWidth: CGFloat
    private let selectionView = UIView()
    private let backgroundLayer = CAShapeLayer()
    private var selectedIndex: Int?

    var selectedValue: String? {
        guard let selectedIndex, values.indices.contains(selectedIndex) else { return nil }
        return values[selectedIndex]
    }

    static func preferredSize(optionCount: Int, optionWidth: CGFloat) -> CGSize {
        CGSize(
            width: horizontalPadding * 2 + CGFloat(optionCount) * optionWidth,
            height: bodyHeight
        )
    }

    init(values: [String], selectedIndex: Int, optionWidth: CGFloat) {
        self.values = values
        self.selectedIndex = values.indices.contains(selectedIndex) ? selectedIndex : nil
        self.optionWidth = optionWidth
        self.labels = values.map { value in
            let label = UILabel()
            label.text = value
            label.font = .systemFont(ofSize: 22)
            label.textAlignment = .center
            label.isAccessibilityElement = true
            label.accessibilityLabel = value
            return label
        }
        super.init(frame: .zero)

        backgroundColor = .clear
        isOpaque = false
        layer.insertSublayer(backgroundLayer, at: 0)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.24
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 2)

        selectionView.layer.cornerRadius = Self.selectionCornerRadius
        addSubview(selectionView)
        labels.forEach(addSubview)
        applyAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bodyBounds = CGRect(x: 0, y: 0, width: bounds.width, height: Self.bodyHeight)
        let contentBounds = CGRect(
            x: Self.horizontalPadding,
            y: Self.verticalContentInset,
            width: CGFloat(labels.count) * optionWidth,
            height: Self.bodyHeight - Self.verticalContentInset * 2
        )
        if let selectedIndex {
            selectionView.frame = CGRect(
                x: contentBounds.minX + CGFloat(selectedIndex) * optionWidth,
                y: contentBounds.minY,
                width: optionWidth,
                height: contentBounds.height
            )
        }
        for (index, label) in labels.enumerated() {
            label.frame = CGRect(
                x: contentBounds.minX + CGFloat(index) * optionWidth,
                y: contentBounds.minY,
                width: optionWidth,
                height: contentBounds.height
            )
        }

        let path = UIBezierPath(roundedRect: bodyBounds, cornerRadius: 11)
        backgroundLayer.frame = bounds
        backgroundLayer.path = path.cgPath
        layer.shadowPath = path.cgPath
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyAppearance()
    }

    @discardableResult
    func selectValue(at location: CGPoint) -> Bool {
        let interactionBounds = CGRect(
            x: -18,
            y: -24,
            width: bounds.width + 36,
            height: bounds.height + 88
        )
        guard interactionBounds.contains(location) else {
            return setSelectedIndex(nil)
        }

        let contentMinX = Self.horizontalPadding
        let contentMaxX = contentMinX + CGFloat(labels.count) * optionWidth
        guard location.x >= contentMinX - optionWidth / 2,
              location.x <= contentMaxX + optionWidth / 2 else {
            return setSelectedIndex(nil)
        }
        let index = min(
            max(Int((location.x - contentMinX) / optionWidth), 0),
            labels.count - 1
        )
        return setSelectedIndex(index)
    }

    private func setSelectedIndex(_ index: Int?) -> Bool {
        guard index != selectedIndex else { return false }
        selectedIndex = index
        updateHighlight()
        setNeedsLayout()
        return true
    }

    private func updateHighlight() {
        for (index, label) in labels.enumerated() {
            label.textColor = .label
            label.font = .systemFont(ofSize: 22, weight: index == selectedIndex ? .semibold : .regular)
        }
        selectionView.isHidden = selectedIndex == nil
    }

    private func applyAppearance() {
        let popupColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.31, alpha: 0.99)
                : UIColor(white: 0.98, alpha: 0.99)
        }
        let selectionColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.47, alpha: 0.96)
                : UIColor(white: 0.82, alpha: 0.96)
        }
        backgroundLayer.fillColor = popupColor.resolvedColor(with: traitCollection).cgColor
        selectionView.backgroundColor = selectionColor
        updateHighlight()
    }
}
