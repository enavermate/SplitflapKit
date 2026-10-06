# ``SplitflapKit``

Split-flap departure-board text for SwiftUI and UIKit: every letter rolls, flips or flickers into
place, played by Core Animation.

## Overview

```swift
Splitflap(gate)
    .splitflapTransition(.flip(surface: .black))
    .splitflapFont(size: 28, weight: .bold)
```

A new string turns in from the one on screen; a change mid-flight continues from where every cell
is. The board lays out like a one-line label in the same font, `…` included, and supports Dynamic
Type, Reduce Motion and VoiceOver.

## Topics

### Essentials

- <doc:Recipes>

### SwiftUI

- ``Splitflap``
- ``SplitflapConfiguration``

### UIKit

- ``SplitflapView``

### Settings

- ``SplitflapViewTransition``
- ``SplitflapCellWidth``
- ``SplitflapReduceMotion``
