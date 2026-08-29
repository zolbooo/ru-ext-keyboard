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
    private weak var variantPopup: UIView?

    override func viewDidLoad() {
        super.viewDidLoad()
        configureRootView()
        rebuildKeyboard()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        variantPopup?.removeFromSuperview()
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
                self.rebuildKeyboard()
            }
        }
        leading.widthAnchor.constraint(equalTo: row.widthAnchor, multiplier: 0.115).isActive = true
        row.addArrangedSubview(leading)

        characters.forEach { row.addArrangedSubview(makeCharacterKey($0)) }

        let delete = makeSpecialKey("⌫") { [weak self] in
            self?.textDocumentProxy.deleteBackward()
        }
        delete.accessibilityLabel = "Удалить"
        delete.widthAnchor.constraint(equalTo: row.widthAnchor, multiplier: 0.115).isActive = true
        row.addArrangedSubview(delete)
        return row
    }

    private func makeBottomRow() -> UIView {
        let row = makeRow()

        let pageKey = makeSpecialKey(page == .letters ? "123" : "АБВ") { [weak self] in
            guard let self else { return }
            self.page = self.page == .letters ? .symbols : .letters
            self.shifted = false
            self.rebuildKeyboard()
        }
        pageKey.widthAnchor.constraint(equalTo: row.widthAnchor, multiplier: 0.16).isActive = true
        row.addArrangedSubview(pageKey)

        let globe = makeSpecialKey("◎", action: nil)
        globe.accessibilityLabel = "Следующая клавиатура"
        globe.addTarget(self, action: #selector(nextKeyboard(_:for:)), for: .allTouchEvents)
        globe.widthAnchor.constraint(equalTo: row.widthAnchor, multiplier: 0.13).isActive = true
        row.addArrangedSubview(globe)

        let space = makeKey(title: "пробел", style: .character) { [weak self] in
            self?.insert(" ")
        }
        space.titleLabel?.font = .systemFont(ofSize: 16)
        row.addArrangedSubview(space)

        let enter = makeSpecialKey("ввод") { [weak self] in
            self?.insert("\n")
        }
        enter.titleLabel?.font = .systemFont(ofSize: 15)
        enter.widthAnchor.constraint(equalTo: row.widthAnchor, multiplier: 0.19).isActive = true
        row.addArrangedSubview(enter)
        return row
    }

    private func makeCharacterKey(_ character: String) -> KeyboardButton {
        let displayed = shifted ? character.uppercased() : character
        let key = makeKey(title: displayed, style: .character) { [weak self] in
            self?.insert(displayed)
            if self?.shifted == true {
                self?.shifted = false
                self?.rebuildKeyboard()
            }
        }
        key.accessibilityLabel = displayed

        let variant: String?
        switch character {
        case "о": variant = shifted ? "Ө" : "ө"
        case "у": variant = shifted ? "Ү" : "ү"
        case "₽": variant = "₮"
        default: variant = nil
        }
        if let variant {
            key.longPressAction = { [weak self, weak key] in
                guard let self, let key else { return }
                self.showVariants([displayed, variant], from: key)
            }
            key.accessibilityHint = "Удерживайте для \(variant)"
        }
        return key
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
        variantPopup?.removeFromSuperview()
        textDocumentProxy.insertText(text)
    }

    private func showVariants(_ variants: [String], from key: UIView) {
        variantPopup?.removeFromSuperview()

        let popup = UIStackView()
        popup.axis = .horizontal
        popup.spacing = 2
        popup.distribution = .fillEqually
        popup.backgroundColor = .secondarySystemBackground
        popup.layer.cornerRadius = 10
        popup.layer.shadowColor = UIColor.black.cgColor
        popup.layer.shadowOpacity = 0.25
        popup.layer.shadowRadius = 5
        popup.layer.shadowOffset = CGSize(width: 0, height: 2)
        popup.isLayoutMarginsRelativeArrangement = true
        popup.layoutMargins = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)

        variants.forEach { value in
            let button = KeyboardButton(style: .character)
            button.setTitle(value, for: .normal)
            button.tapAction = { [weak self] in self?.insert(value) }
            popup.addArrangedSubview(button)
        }

        let keyFrame = key.convert(key.bounds, to: view)
        let width: CGFloat = 104
        let height: CGFloat = 56
        let x = min(max(4, keyFrame.midX - width / 2), view.bounds.width - width - 4)
        let y = keyFrame.minY > height + 8 ? keyFrame.minY - height - 4 : keyFrame.maxY + 4
        popup.frame = CGRect(x: x, y: y, width: width, height: height)
        view.addSubview(popup)
        variantPopup = popup
        UIAccessibility.post(notification: .layoutChanged, argument: popup)
    }

    @objc private func nextKeyboard(_ sender: UIControl, for event: UIEvent) {
        handleInputModeList(from: sender, with: event)
    }
}

private final class KeyboardButton: UIButton {
    enum Style {
        case character
        case special
    }

    var tapAction: (() -> Void)?
    var longPressAction: (() -> Void)? {
        didSet { longPressRecognizer.isEnabled = longPressAction != nil }
    }

    private var suppressTap = false
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
        longPressRecognizer.cancelsTouchesInView = false
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
        if suppressTap {
            suppressTap = false
        } else {
            tapAction?()
        }
    }

    @objc private func longPressed(_ recognizer: UILongPressGestureRecognizer) {
        if recognizer.state == .began {
            suppressTap = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            longPressAction?()
        } else if recognizer.state == .cancelled || recognizer.state == .failed {
            suppressTap = false
        }
    }
}
