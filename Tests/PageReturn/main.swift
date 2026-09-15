func sequence(_ inputs: [String], prefersSymbols: Bool = false) -> [Bool] {
    var policy = SymbolPageReturnPolicy()
    return inputs.map { policy.didInsert($0, prefersSymbols: prefersSymbols) }
}
precondition(sequence([" ", " ", "\n"]) == [false, false, false])
for symbol in [".", ",", "?", "!", "-", "1", "₽", "#", "—", "…"] {
    precondition(sequence([symbol, " "]) == [false, true], symbol)
    precondition(sequence([symbol, "\n"]) == [false, true], symbol)
}
precondition(sequence(["3", ".", "1", "4", " "]) == [false, false, false, false, true])
precondition(sequence(["' "]) == [false]) // Only a single apostrophe key requests return.
precondition(sequence(["'"]) == [true])
precondition(sequence(["’"]) == [true])
precondition(sequence(["1", "'", "’", " ", "\n"], prefersSymbols: true) == Array(repeating: false, count: 5))
var policy = SymbolPageReturnPolicy()
_ = policy.didInsert("!", prefersSymbols: false)
policy.reset()
precondition(!policy.didInsert(" ", prefersSymbols: false))
precondition(!policy.didInsert("", prefersSymbols: false))
print("PAGE_RETURN passed")
