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

    override func viewDidLoad() {
        super.viewDidLoad()
        configureRootView()
        rebuildKeyboard()
    }

    private func configureRootView() {
        view.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.12, green: 0.13, blue: 0.15, alpha: 1)
                : UIColor(red: 0.82, green: 0.84, blue: 0.87, alpha: 1)
        }

        keyboardStack.axis = .vertical
        keyboardStack.spacing = 7
        keyboardStack.distribution = .fillEqually
        keyboardStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboardStack)

        let height = view.heightAnchor.constraint(equalToConstant: 258)
        height.priority = .defaultHigh
        NSLayoutConstraint.activate([
            keyboardStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 7),
            keyboardStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            keyboardStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            keyboardStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -7),
            height
        ])
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

        let leading = makeSpecialKey(page == .letters ? (shifted ? "⇧" : "⇧") : "#+=") { [weak self] in
            guard let self else { return }
            if self.page == .letters {
                self.shifted.toggle()
                self.updateCharacterKeys()
            }
        }
        row.addArrangedSubview(leading)

        characters.forEach { row.addArrangedSubview(makeCharacterKey($0)) }

        let delete = makeSpecialKey("⌫") { [weak self] in
            self?.textDocumentProxy.deleteBackward()
        }
        delete.accessibilityLabel = "Удалить"
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
        pageKey.widthAnchor.constraint(equalTo: row.widthAnchor, multiplier: 0.16).isActive = true

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
        enter.widthAnchor.constraint(equalTo: row.widthAnchor, multiplier: 0.19).isActive = true
        return row
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
        case "о": return shifted ? "Ө" : "ө"
        case "у": return shifted ? "Ү" : "ү"
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
        let size = CGSize(width: 112, height: 56)
        let x = min(max(4, keyFrame.midX - size.width / 2), view.bounds.width - size.width - 4)
        let y = keyFrame.minY > size.height + 8
            ? keyFrame.minY - size.height - 4
            : keyFrame.maxY + 4
        popup.frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
        view.addSubview(popup)
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

    private lazy var longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:)))

    init(style: Style) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 5
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.22
        layer.shadowRadius = 0
        layer.shadowOffset = CGSize(width: 0, height: 1)
        titleLabel?.font = .systemFont(ofSize: style == .character ? 22 : 18)
        setTitleColor(.label, for: .normal)
        setTitleColor(.secondaryLabel, for: .highlighted)
        backgroundColor = style == .character ? .systemBackground : .systemGray3
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
        didSet { alpha = isHighlighted ? 0.62 : 1 }
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
    private let buttons: [KeyboardButton]
    private var selectedIndex = 1

    var selectedValue: String? {
        values.indices.contains(selectedIndex) ? values[selectedIndex] : nil
    }

    init(values: [String]) {
        self.values = values
        self.buttons = values.map { value in
            let button = KeyboardButton(style: .character)
            button.setTitle(value, for: .normal)
            button.accessibilityLabel = value
            button.isUserInteractionEnabled = false
            return button
        }
        super.init(frame: .zero)

        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 10
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 5
        layer.shadowOffset = CGSize(width: 0, height: 2)
        buttons.forEach(addSubview)
        updateHighlight()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let contentBounds = bounds.insetBy(dx: 4, dy: 4)
        let spacing: CGFloat = 2
        let buttonWidth = (contentBounds.width - spacing * CGFloat(buttons.count - 1)) / CGFloat(buttons.count)
        for (index, button) in buttons.enumerated() {
            button.frame = CGRect(
                x: contentBounds.minX + CGFloat(index) * (buttonWidth + spacing),
                y: contentBounds.minY,
                width: buttonWidth,
                height: contentBounds.height
            )
        }
    }

    func selectValue(at location: CGPoint) {
        guard bounds.insetBy(dx: -12, dy: -18).contains(location) else { return }
        let index = min(max(Int(location.x / (bounds.width / CGFloat(buttons.count))), 0), buttons.count - 1)
        guard index != selectedIndex else { return }
        selectedIndex = index
        updateHighlight()
    }

    private func updateHighlight() {
        for (index, button) in buttons.enumerated() {
            let isSelected = index == selectedIndex
            button.backgroundColor = isSelected ? .systemBlue : .systemBackground
            button.setTitleColor(isSelected ? .white : .label, for: .normal)
        }
    }
}
