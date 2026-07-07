# catty-embroidery

[![CI](https://github.com/stoneacher/catty-embroidery/actions/workflows/ci.yml/badge.svg)](https://github.com/stoneacher/catty-embroidery/actions/workflows/ci.yml)

A standalone native iOS app that brings [Catrobat](https://catrobat.org)'s embroidery
functionality to iOS — the counterpart of the Android
[Pocket Code](https://github.com/Catrobat/Catroid) "Embroidery Designer" flavor. Users
program embroidery designs with Pocket Code-style visual blocks, watch a live stitch
preview, and export machine-readable [Tajima DST](https://en.wikipedia.org/wiki/Tajima_(embroidery)) files
for real embroidery machines.

The project is developed as a bachelor-thesis open-source contribution at TU Graz and is
intended to be transferred to the [Catrobat organization](https://github.com/Catrobat)
after sign-off. It is built test-first in small user-story iterations; the roadmap,
architecture decision records, and user stories live in [`docs/`](docs/). The embroidery
engine is a platform-independent Swift package
([`Packages/EmbroideryEngine`](Packages/EmbroideryEngine)), with a SwiftUI app on top.
Reference implementations: [Catroid](https://github.com/Catrobat/Catroid) (canonical
embroidery semantics) and [Catty](https://github.com/Catrobat/Catty) (iOS prior art).

Licensed under [AGPL-3.0](LICENSE), like all Catrobat projects.

## Build & test

- Engine: `cd Packages/EmbroideryEngine && swift test` (no simulator required)
- App: open `catrobat_embroidery_ios/catrobat_embroidery_ios.xcodeproj` in Xcode, or
  `xcodebuild -project catrobat_embroidery_ios/catrobat_embroidery_ios.xcodeproj -scheme catrobat_embroidery_ios -destination 'platform=iOS Simulator,name=iPhone 17' test`
