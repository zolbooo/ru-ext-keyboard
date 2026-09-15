# Symbol page return policy checks

Run `bash Tests/PageReturn/run.sh` on macOS with Xcode. This compiles the actual
pure policy from the keyboard source and checks punctuation/digit sequences,
empty symbols sessions, apostrophes, numeric-field suppression, and reset.
No running Simulator is required. These checks do not exercise UIKit touch
routing or assert exact native keyboard parity.
