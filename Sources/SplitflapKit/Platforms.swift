// SplitflapKit is made for iOS and iPadOS, and runs on the Mac through Mac Catalyst (UIKit there
// too). The planner's tests also run on a Mac and on Linux with
// `swift test -Xswiftc -DSPLITFLAP_HOST_TESTS`, where the view is left out; any other build stops
// here, so no platform looks supported that is not.
#if !os(iOS) && !SPLITFLAP_HOST_TESTS
#error("SplitflapKit runs on iOS, iPadOS and Mac Catalyst")
#endif
