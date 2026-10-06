# Contributing

Thank you for taking the time.

## Bugs

Open an issue with the [bug form](https://github.com/enavermate/SplitflapKit/issues/new/choose). What
helps the most:

- the SplitflapKit and Xcode versions
- the platform and OS version, device or simulator
- a few lines that reproduce it: the modifiers or properties and the texts the board went through

## Ideas and questions

[Discussions](https://github.com/enavermate/SplitflapKit/discussions) — Ideas for a feature, Q&A for
help.

## Pull requests

This repository holds the package as it is published: `master` gets one commit per release. A pull
request is read and welcome, and its change lands in the next release rather than being merged here.
For anything larger than a fix, open an issue or a discussion first, so the change fits the
library's direction before the work is done.

The planner (`Sources/SplitflapPlanner`) is a line-by-line port of
[react-native-splitflap](https://github.com/enavermate/react-native-splitflap)'s TypeScript planner,
and its tests check it against that planner's golden plans: a change to how a board moves belongs
in both, so a text animates the same way in React Native and in Swift.

```sh
swift test -Xswiftc -DSPLITFLAP_HOST_TESTS   # the planner, on the Mac (the view needs UIKit)
xcodebuild -scheme SplitflapKit -destination 'generic/platform=iOS Simulator' build
open Examples/SplitflapDemo/SplitflapDemo.xcodeproj
```

## Code of conduct

Everyone taking part follows the [code of conduct](CODE_OF_CONDUCT.md).
