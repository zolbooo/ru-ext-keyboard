import UIKit

final class KeyboardViewController: UIInputViewController {
    private enum Page {
        case letters
        case symbols
    }

    private let letterRows = [
        ["й", "ц", "у", "к", "е", "н", "г", "ш", "щ", "з", "х"],
        ["ф", "ы", "в", "а", "п", "р", "о", "л", "д", "ж", "э"],
        ["я", "ч", "с", "м", "и", "т", "ь", "б", "ю"]
    ]

    private let symbolRows = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["-", "/", ":", ";", "(", ")", "₽", "&", "@", "\""] ,
        [".", ",", "?", "!", "'", "+", "=", "%"]
    ]

    private let candidateBar = CandidateBarView()
    private let keyboardStack = UIStackView()
    private weak var layoutContainer: UIView?
    private var page: Page = .letters
    private var shifted = false
    private var characterKeys: [(button: KeyboardButton, character: String)] = []
    private var rowStacks: [UIStackView] = []
    private var bottomSideKeyConstraints: [NSLayoutConstraint] = []
    private var appliedMetrics: KeyboardMetrics?
    private var keyboardHeightConstraint: NSLayoutConstraint!
    private var candidateTopConstraint: NSLayoutConstraint!
    private var candidateLeadingConstraint: NSLayoutConstraint!
    private var candidateTrailingConstraint: NSLayoutConstraint!
    private var candidateHeightConstraint: NSLayoutConstraint!
    private var keyboardTopConstraint: NSLayoutConstraint!
    private var keyboardLeadingConstraint: NSLayoutConstraint!
    private var keyboardTrailingConstraint: NSLayoutConstraint!
    private var keyboardBottomConstraint: NSLayoutConstraint!
    private var variantPopup: VariantPopup?
    private weak var returnKey: KeyboardButton?

    override func viewDidLoad() {
        super.viewDidLoad()
        configureRootView()
        rebuildKeyboard()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateLayoutMetrics()
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

        candidateBar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(candidateBar)

        keyboardStack.axis = .vertical
        keyboardStack.distribution = .fillEqually
        keyboardStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(keyboardStack)

        keyboardHeightConstraint = container.heightAnchor.constraint(equalToConstant: 276)
        candidateTopConstraint = candidateBar.topAnchor.constraint(equalTo: container.topAnchor)
        candidateLeadingConstraint = candidateBar.leadingAnchor.constraint(equalTo: container.leadingAnchor)
        candidateTrailingConstraint = candidateBar.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        candidateHeightConstraint = candidateBar.heightAnchor.constraint(equalToConstant: 50)
        keyboardTopConstraint = keyboardStack.topAnchor.constraint(equalTo: candidateBar.bottomAnchor)
        keyboardLeadingConstraint = keyboardStack.leadingAnchor.constraint(equalTo: container.leadingAnchor)
        keyboardTrailingConstraint = keyboardStack.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        keyboardBottomConstraint = keyboardStack.bottomAnchor.constraint(equalTo: container.bottomAnchor)

        NSLayoutConstraint.activate([
            keyboardHeightConstraint,
            candidateTopConstraint,
            candidateLeadingConstraint,
            candidateTrailingConstraint,
            candidateHeightConstraint,
            keyboardTopConstraint,
            keyboardLeadingConstraint,
            keyboardTrailingConstraint,
            keyboardBottomConstraint
        ])
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        updateReturnKey()
    }

    private func rebuildKeyboard() {
        dismissVariantPopup()
        characterKeys.removeAll()
        rowStacks.removeAll()
        bottomSideKeyConstraints.removeAll()
        keyboardStack.arrangedSubviews.forEach {
            keyboardStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let rows = page == .letters ? letterRows : symbolRows
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

        let leading = page == .letters
            ? makeIconKey("shift", accessibilityLabel: "Сдвиг")
            : makeSpecialKey("#+=", action: nil)
        leading.tapAction = { [weak self, weak leading] in
            guard let self else { return }
            if self.page == .letters {
                self.shifted.toggle()
                leading?.setImage(
                    UIImage(systemName: self.shifted ? "shift.fill" : "shift"),
                    for: .normal
                )
                leading?.setSelectedStyle(self.shifted)
                self.updateCharacterKeys()
            }
        }
        row.addArrangedSubview(leading)
        characters.forEach { row.addArrangedSubview(makeCharacterKey($0)) }

        let delete = makeIconKey("delete.left", accessibilityLabel: "Удалить") { [weak self] in
            self?.textDocumentProxy.deleteBackward()
        }
        row.addArrangedSubview(delete)
        return row
    }

    private func makeBottomRow() -> UIView {
        let row = makeRow()
        row.distribution = .fill

        let pageKey = makeSpecialKey(page == .letters ? "123" : "АБВ") { [weak self] in
            guard let self else { return }
            self.page = self.page == .letters ? .symbols : .letters
            self.shifted = false
            self.rebuildKeyboard()
        }
        row.addArrangedSubview(pageKey)
        bottomSideKeyConstraints.append(pageKey.widthAnchor.constraint(equalToConstant: 76))

        let space = makeKey(title: "пробел", style: .character) { [weak self] in
            self?.insert(" ")
        }
        space.titleLabel?.font = .systemFont(ofSize: 16)
        space.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(space)

        let enter = makeSpecialKey("ввод") { [weak self] in
            self?.insert("\n")
        }
        enter.titleLabel?.font = .systemFont(ofSize: 15)
        row.addArrangedSubview(enter)
        bottomSideKeyConstraints.append(enter.widthAnchor.constraint(equalToConstant: 76))
        NSLayoutConstraint.activate(bottomSideKeyConstraints)
        returnKey = enter
        updateReturnKey()
        return row
    }

    private func updateReturnKey() {
        guard let returnKey else { return }

        returnKey.setImage(nil, for: .normal)
        let returnKeyType = textDocumentProxy.returnKeyType
        switch returnKeyType {
        case .search:
            returnKey.setTitle(nil, for: .normal)
            returnKey.setImage(UIImage(systemName: "magnifyingglass"), for: .normal)
            returnKey.accessibilityLabel = "Найти"
        case .done:
            returnKey.setTitle("готово", for: .normal)
            returnKey.accessibilityLabel = "Готово"
        case .go:
            returnKey.setTitle("перейти", for: .normal)
            returnKey.accessibilityLabel = "Перейти"
        case .next:
            returnKey.setTitle("далее", for: .normal)
            returnKey.accessibilityLabel = "Далее"
        case .send:
            returnKey.setTitle("отправить", for: .normal)
            returnKey.accessibilityLabel = "Отправить"
        default:
            returnKey.setTitle("ввод", for: .normal)
            returnKey.accessibilityLabel = "Ввод"
        }
        returnKey.setActionStyle(returnKeyType != .default)
    }

    private func makeCharacterKey(_ character: String) -> KeyboardButton {
        let key = makeKey(title: character, style: .character) { [weak self] in
            guard let self else { return }
            self.insert(self.shifted ? character.uppercased() : character)
            self.resetShiftIfNeeded()
        }
        characterKeys.append((key, character))

        if variant(for: character) != nil {
            key.longPressAction = { [weak self, weak key] recognizer in
                guard let self, let key else { return }
                self.handleVariantGesture(recognizer, character: character, from: key)
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
        key.setTitle(displayed, for: .normal)
        key.accessibilityLabel = displayed
        key.accessibilityHint = variant(for: character).map { "Удерживайте для \($0)" }
    }

    private func variant(for character: String) -> String? {
        switch character {
        case "е": return shifted ? "Ё" : "ё"
        case "о": return shifted ? "Ө" : "ө"
        case "у": return shifted ? "Ү" : "ү"
        case "ь": return shifted ? "Ъ" : "ъ"
        case "₽": return "₮"
        default: return nil
        }
    }

    private func resetShiftIfNeeded() {
        guard shifted else { return }
        shifted = false
        updateCharacterKeys()
    }

    private func handleVariantGesture(
        _ recognizer: UILongPressGestureRecognizer,
        character: String,
        from key: KeyboardButton
    ) {
        switch recognizer.state {
        case .began:
            let displayed = shifted ? character.uppercased() : character
            guard let variant = variant(for: character) else { return }
            showVariants([displayed, variant], from: key)
        case .changed:
            updateVariantSelection(at: recognizer.location(in: view))
        case .ended:
            updateVariantSelection(at: recognizer.location(in: view))
            if let value = variantPopup?.selectedValue {
                insert(value)
                resetShiftIfNeeded()
            }
            dismissVariantPopup()
        case .cancelled, .failed:
            dismissVariantPopup()
        default:
            break
        }
    }

    private func showVariants(_ variants: [String], from key: UIView) {
        dismissVariantPopup()

        let popup = VariantPopup(values: variants)
        let keyFrame = key.convert(key.bounds, to: view)
        let size = CGSize(width: CGFloat(variants.count) * 33 + 20, height: 60)
        let x = min(max(4, keyFrame.midX - size.width / 2), view.bounds.width - size.width - 4)
        let y = keyFrame.minY - size.height - 4
        popup.frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
        popup.layer.zPosition = 10
        view.addSubview(popup)
        view.bringSubviewToFront(popup)
        variantPopup = popup
    }

    private func updateVariantSelection(at location: CGPoint) {
        guard let popup = variantPopup else { return }
        let localLocation = view.convert(location, to: popup)
        popup.selectValue(at: localLocation)
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
        candidateTopConstraint.constant = metrics.candidateTopInset
        candidateLeadingConstraint.constant = metrics.horizontalInset
        candidateTrailingConstraint.constant = -metrics.horizontalInset
        candidateHeightConstraint.constant = metrics.candidateHeight
        keyboardTopConstraint.constant = metrics.candidateToKeysSpacing
        keyboardLeadingConstraint.constant = metrics.horizontalInset
        keyboardTrailingConstraint.constant = -metrics.horizontalInset
        keyboardBottomConstraint.constant = -metrics.bottomInset
        keyboardStack.spacing = metrics.rowSpacing
        rowStacks.forEach { $0.spacing = metrics.keySpacing }
        bottomSideKeyConstraints.forEach { $0.constant = metrics.bottomSideKeyWidth }
    }

    private func makeSpecialKey(_ title: String, action: (() -> Void)?) -> KeyboardButton {
        makeKey(title: title, style: .special, action: action)
    }

    private func makeIconKey(
        _ systemName: String,
        accessibilityLabel: String,
        action: (() -> Void)? = nil
    ) -> KeyboardButton {
        let key = KeyboardButton(style: .special)
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
    let candidateTopInset: CGFloat
    let candidateHeight: CGFloat
    let candidateToKeysSpacing: CGFloat
    let bottomInset: CGFloat
    let horizontalInset: CGFloat
    let rowSpacing: CGFloat
    let keySpacing: CGFloat
    let bottomSideKeyWidth: CGFloat

    init(width: CGFloat, traits: UITraitCollection) {
        let isCompact = traits.verticalSizeClass == .compact || width >= 560

        if isCompact {
            keyboardHeight = 207
            candidateTopInset = 2
            candidateHeight = 38
            candidateToKeysSpacing = 4
            bottomInset = 4
            horizontalInset = Self.clamp(width * 0.004, minimum: 2, maximum: 4)
            rowSpacing = 5
            keySpacing = Self.clamp(width * 0.007, minimum: 3, maximum: 5)
            bottomSideKeyWidth = (width - 2 * horizontalInset) * 0.18
            return
        }

        // The decoded iPhone templates grow from a 320-point, 42-point-row
        // keyplane to taller Choco/Truffle keyplanes. Interpolate within that
        // family instead of locking every device to one set of pixel values.
        let templateWidth = Self.clamp(width, minimum: 320, maximum: 414)
        let progress = (templateWidth - 320) / (414 - 320)

        keyboardHeight = (276 + 12 * progress).rounded()
        candidateTopInset = 4
        candidateHeight = (50 + 6 * progress).rounded()
        candidateToKeysSpacing = 8
        bottomInset = 8
        horizontalInset = Self.clamp(width * 0.003125, minimum: 1, maximum: 2)
        rowSpacing = (12 - 4 * progress).rounded()
        keySpacing = Self.clamp(width * 0.009, minimum: 3, maximum: 4)
        bottomSideKeyWidth = (width - 2 * horizontalInset) * 0.24
    }

    private static func clamp(_ value: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        min(max(value, minimum), maximum)
    }
}

private final class CandidateBarView: UIView {
    var selectionHandler: ((String) -> Void)?

    private let stack = UIStackView()
    private lazy var buttons: [UIButton] = (0..<3).map { index in
        let button = UIButton(type: .system)
        button.tag = index
        button.titleLabel?.font = .systemFont(ofSize: 17)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.75
        button.setTitleColor(.label, for: .normal)
        button.addTarget(self, action: #selector(candidateSelected(_:)), for: .touchUpInside)
        return button
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        buttons.forEach(stack.addArrangedSubview)

        for button in buttons.dropLast() {
            let separator = UIView()
            separator.backgroundColor = .separator
            separator.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(separator)
            NSLayoutConstraint.activate([
                separator.topAnchor.constraint(equalTo: button.topAnchor, constant: 10),
                separator.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                separator.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -10),
                separator.widthAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
            ])
        }

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        setCandidates([])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setCandidates(_ candidates: [String]) {
        for (index, button) in buttons.enumerated() {
            let candidate = candidates.indices.contains(index) ? candidates[index] : nil
            button.setTitle(candidate, for: .normal)
            button.isUserInteractionEnabled = candidate != nil
            button.isAccessibilityElement = candidate != nil
            button.accessibilityLabel = candidate
        }
    }

    @objc private func candidateSelected(_ sender: UIButton) {
        guard let candidate = sender.title(for: .normal), !candidate.isEmpty else { return }
        selectionHandler?(candidate)
    }
}

private final class KeyboardButton: UIButton {
    enum Style {
        case character
        case special
    }

    var tapAction: (() -> Void)?
    var longPressAction: ((UILongPressGestureRecognizer) -> Void)? {
        didSet { longPressRecognizer.isEnabled = longPressAction != nil }
    }

    private let style: Style
    private var usesActionStyle = false
    private var usesSelectedStyle = false
    private lazy var longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:)))

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
        addTarget(self, action: #selector(tapped), for: .touchUpInside)

        longPressRecognizer.minimumPressDuration = 0.38
        longPressRecognizer.cancelsTouchesInView = true
        longPressRecognizer.isEnabled = false
        addGestureRecognizer(longPressRecognizer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.7 : 1 }
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

    private func applyAppearance() {
        if usesActionStyle {
            backgroundColor = .systemBlue
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
        backgroundColor = style == .character || usesSelectedStyle ? characterColor : specialColor
        setTitleColor(.label, for: .normal)
        tintColor = .label
    }

    @objc private func tapped() {
        tapAction?()
    }

    @objc private func longPressed(_ recognizer: UILongPressGestureRecognizer) {
        if recognizer.state == .began {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        longPressAction?(recognizer)
    }
}

private final class VariantPopup: UIView {
    private let values: [String]
    private let labels: [UILabel]
    private let selectionView = UIView()
    private let backgroundView = UIView()
    private var selectedIndex = 1

    var selectedValue: String? {
        values.indices.contains(selectedIndex) ? values[selectedIndex] : nil
    }

    init(values: [String]) {
        self.values = values
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
        layer.cornerRadius = 10
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.22
        layer.shadowRadius = 5
        layer.shadowOffset = CGSize(width: 0, height: 2)
        backgroundView.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.34, alpha: 0.98)
                : UIColor(white: 1, alpha: 0.98)
        }
        backgroundView.layer.cornerRadius = 10
        backgroundView.clipsToBounds = true
        addSubview(backgroundView)

        selectionView.backgroundColor = .systemBlue
        selectionView.layer.cornerRadius = 11
        addSubview(selectionView)
        labels.forEach(addSubview)
        updateHighlight()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        backgroundView.frame = bounds
        let contentBounds = CGRect(x: 10, y: 6, width: bounds.width - 20, height: 48)
        let optionWidth = contentBounds.width / CGFloat(labels.count)
        selectionView.frame = CGRect(
            x: contentBounds.minX + CGFloat(selectedIndex) * optionWidth,
            y: contentBounds.minY,
            width: optionWidth,
            height: contentBounds.height
        )
        for (index, label) in labels.enumerated() {
            label.frame = CGRect(
                x: contentBounds.minX + CGFloat(index) * optionWidth,
                y: contentBounds.minY,
                width: optionWidth,
                height: contentBounds.height
            )
        }
    }

    func selectValue(at location: CGPoint) {
        guard bounds.insetBy(dx: -12, dy: -18).contains(location) else { return }
        let contentBounds = CGRect(x: 10, y: 6, width: bounds.width - 20, height: 48)
        let optionWidth = contentBounds.width / CGFloat(labels.count)
        let index = min(
            max(Int((location.x - contentBounds.minX) / optionWidth), 0),
            labels.count - 1
        )
        guard index != selectedIndex else { return }
        selectedIndex = index
        updateHighlight()
        setNeedsLayout()
    }

    private func updateHighlight() {
        for (index, label) in labels.enumerated() {
            label.textColor = index == selectedIndex ? .white : .label
        }
    }
}
