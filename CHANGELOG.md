# Changelog

## [0.5.2](https://github.com/enavermate/SplitflapKit/compare/0.5.1...0.5.2) — 2026-10-06

### Added

- Recipes in the README and the documentation: a departure board, prices, a clock, loading words
  instead of a skeleton, custom alphabets, list rows, callbacks, UIKit and the planner

## [0.5.1](https://github.com/enavermate/SplitflapKit/compare/0.5.0...0.5.1) — 2026-10-05

### Fixed

- The demo app builds with Xcode 16 too

## [0.5.0] — 2026-10-05

### Added

- `Splitflap` for SwiftUI and `SplitflapView` for UIKit: departure-board text played by Core
  Animation, on iPhone and iPad (iOS and iPadOS 15+) and the Mac through Mac Catalyst
- Four transitions: `.reel()` (default), `.roll()`, `.flip(surface:)` and `.scramble`; direction for
  `reel` and `roll`
- Cell widths `natural` and `uniform`, with a dense default for `.flip` and `.scramble`; tabular
  digits by default
- Alphabets by script: Latin, Cyrillic, Greek, Armenian, Georgian, the Indic and Southeast Asian
  scripts, the kana and many numeral systems, or custom letters; any other character changes in one
  step
- Changes mid-flight continue from where every cell is
- Loading words while data loads, with a fixed length or a range
- Dynamic Type, Reduce Motion, VoiceOver, `…` truncation like a one-line label
- `SplitflapPlanner`: the planner as plain Swift, plan for plan the same as react-native-splitflap's
