#!/bin/sh

set -eu

if [ "${CI_XCODE_CLOUD:-}" != "TRUE" ]; then
    exit 0
fi

action="${CI_XCODEBUILD_ACTION:-unknown}"
branch="${CI_BRANCH:-}"
build_number="${CI_BUILD_NUMBER:-}"

case "$build_number" in
    ''|*[!0-9]*)
        echo "error: Xcode Cloud did not provide a numeric CI_BUILD_NUMBER." >&2
        exit 1
        ;;
esac

if [ "$action" = "archive" ] && [ -n "$branch" ]; then
    case "$branch" in
        main|production)
            ;;
        *)
            echo "error: Distribution archives are restricted to main and production; received '$branch'." >&2
            exit 1
            ;;
    esac
fi

echo "Xcode Cloud: action=$action branch=${branch:-detached} build=$build_number"
