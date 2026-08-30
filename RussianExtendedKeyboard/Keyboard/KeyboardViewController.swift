import UIKit

final class KeyboardViewController: UIInputViewController {
    private enum Page {
        case letters
        case symbols
    }

    private let letterRows = [
        ["й", "ц", "у", "к", "е", "н", "г", "ш", "щ", "з", "х", "ъ"],
        ["ф", "ы", "в", "а", "п", "р", "о", "л", "д", "ж", "э"],
        ["я", "ч", "с", "м", "и", "т", "ь", "б", "ю"]
    ]

    private let symbolRows = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["-", "/", ":", ";", "(", ")", "₽", "&", "@", "\""] ,
        [".", ",", "?", "!", "'", "+", "=", "%"]
    ]

    private let keyboardStack = UIStackView()
    private var page: Page = .letters
    private var shifted = false
    private var characterKeys: [(button: KeyboardButton, character: String)] = []
    private var variantPopup: VariantPopup?
    private weak var returnKey: KeyboardButton?

    override func viewDidLoad() {
        super.viewDidLoad()
        configureRootView()
        rebuildKeyboard()
    }

    private func configureRootView() {
        view.backgroundColor = .clear
        view.isOpaque = false
        view.clipsToBounds = false
        inputView?.backgroundColor = .clear
        inputView?.isOpaque = false
        inputView?.clipsToBounds = false

        keyboardStack.axis = .vertical
        keyboardStack.spacing = 8
        keyboardStack.distribution = .fillEqually
        keyboardStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboardStack)

        let height = view.heightAnchor.constraint(equalToConstant: 276)
        height.priority = .defaultHigh
        NSLayoutConstraint.activate([
            keyboardStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 66),
            keyboardStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            keyboardStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            keyboardStack.heightAnchor.constraint(equalToConstant: 202),
            height
        ])
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        updateReturnKey()
    }

    private func rebuildKeyboard() {
        dismissVariantPopup()
        characterKeys.removeAll()
        keyboardStack.arrangedSubviews.forEach {
            keyboardStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let rows = page == .letters ? letterRows : symbolRows
        keyboardStack.addArrangedSubview(makeCharacterRow(rows[0]))
        keyboardStack.addArrangedSubview(makeCharacterRow(rows[1], horizontalInset: 14))
        keyboardStack.addArrangedSubview(makeThirdRow(rows[2]))
        keyboardStack.addArrangedSubview(makeBottomRow())
    }

    private func makeCharacterRow(_ characters: [String], horizontalInset: CGFloat = 0) -> UIView {
        let row = makeRow()
        characters.forEach { row.addArrangedSubview(makeCharacterKey($0)) }

        if horizontalInset == 0 { return row }
        let container = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: container.topAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: horizontalInset),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -horizontalInset)
        ])
        return container
    }

    private func makeThirdRow(_ characters: [String]) -> UIView {
        let row = makeRow()
        row.distribution = .fill

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
        leading.widthAnchor.constraint(equalTo: row.widthAnchor, multiplier: 0.11).isActive = true

        let characterRow = makeRow()
        characters.forEach { characterRow.addArrangedSubview(makeCharacterKey($0)) }
        row.addArrangedSubview(characterRow)

        let delete = makeIconKey("delete.left", accessibilityLabel: "Удалить") { [weak self] in
            self?.textDocumentProxy.deleteBackward()
        }
        row.addArrangedSubview(delete)
        delete.widthAnchor.constraint(equalTo: row.widthAnchor, multiplier: 0.11).isActive = true
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
        pageKey.widthAnchor.constraint(equalTo: row.widthAnchor, multiplier: 0.24).isActive = true

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
        enter.widthAnchor.constraint(equalTo: row.widthAnchor, multiplier: 0.24).isActive = true
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
        row.spacing = 5
        row.distribution = .fillEqually
        return row
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
