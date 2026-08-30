# Xcode Cloud release workflows

The repository uses two distribution branches:

- `main` creates TestFlight builds.
- `production` creates App Store-eligible builds.

Promote a tested release by merging `main` into `production`. Avoid committing
directly to `production`.

Xcode Cloud stores workflow definitions in Xcode and App Store Connect, not in
the Git repository. Configure the workflows below after linking this project to
Xcode Cloud.

## Prerequisites

1. Register `com.nomadsim.ru-mn-ext-kbd` and its keyboard extension identifier
   `com.nomadsim.ru-mn-ext-kbd.keyboard` for team `AK7J2H5G3S`.
2. Create or confirm the Русская+ app record in App Store Connect.
3. Create an internal TestFlight tester group before adding the TestFlight
   post-action.
4. In Xcode, open the Report navigator, select Cloud, and choose Get Started.
   Select the `RussianExtendedKeyboard` product and shared
   `RussianExtendedKeyboard` scheme, then grant Xcode Cloud access to GitHub.

## Workflow: Main — TestFlight

- General: name it `Main — TestFlight` and enable Restrict Editing.
- Environment: use the latest released Xcode and select Clean.
- Start condition: Branch Changes on `main`.
- Action: Archive for iOS using the `RussianExtendedKeyboard` scheme.
- Deployment Preparation: `TestFlight (Internal Testing Only)`.
- Post-action: distribute to the internal TestFlight group.

If external TestFlight testing is required, change Deployment Preparation to
`TestFlight and App Store` and choose the external group in the post-action.

## Workflow: Production — App Store

- General: name it `Production — App Store` and enable Restrict Editing.
- Environment: use the latest released Xcode and select Clean.
- Start condition: Branch Changes on `production`.
- Action: Archive for iOS using the `RussianExtendedKeyboard` scheme.
- Deployment Preparation: `TestFlight and App Store`.
- Post-action: upload the version to App Store Connect.

The production workflow uploads an App Store-eligible build. Complete the app
metadata, privacy details, screenshots, export-compliance answers, phased-release
choice, and App Review submission in App Store Connect.

## Versioning

The marketing version is `MARKETING_VERSION` in the Xcode project. Update it on
`main` before promoting a new App Store version. Xcode Cloud supplies the unique
integer build number; both the app and keyboard extension read
`CURRENT_PROJECT_VERSION`, so their embedded versions stay aligned.

The pre-build script in `ci_scripts` rejects non-numeric Cloud build numbers and
prevents distribution archives from branches other than `main` or `production`.

## Recommended branch protection

- Require pull requests for `main` and `production`.
- Require a successful Xcode Cloud build before merging.
- Allow merges into `production` only from `main`.
- Disable force-pushes and deletion for both branches.
