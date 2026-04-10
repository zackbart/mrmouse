//
//  DesktopSwitcher.swift
//
//  Desktop switching implementation using synthetic trackpad gesture technique.
//  Based on InstantSpaceSwitcher by jurplel (https://github.com/jurplel/InstantSpaceSwitcher)
//  MIT License
//
//  This technique synthesizes a trackpad swipe gesture with artificially high velocity
//  to trigger instant space switching on macOS 26 Tahoe, bypassing broken CGS APIs.
//

import Foundation

public enum DesktopSwitcher {

    public enum Direction {
        case left
        case right
    }

    private static var isInitialized = false

    private static func ensureInitialized() {
        guard !isInitialized else { return }
        iss_init()
        isInitialized = true
    }

    @discardableResult
    public static func switchDesktop(_ direction: Direction) -> Bool {
        ensureInitialized()
        let issDirection: ISSDirection = direction == .right ? ISSDirectionRight : ISSDirectionLeft
        return iss_switch(issDirection)
    }

    public static func canSwitch(_ direction: Direction) -> Bool {
        ensureInitialized()
        var info = ISSSpaceInfo()
        guard iss_get_space_info(&info) else { return true }
        let issDirection: ISSDirection = direction == .right ? ISSDirectionRight : ISSDirectionLeft
        return iss_can_move(info, issDirection)
    }

    public struct SpaceInfo {
        public let spaceCount: Int
        public let currentIndex: Int

        public init(spaceCount: Int, currentIndex: Int) {
            self.spaceCount = spaceCount
            self.currentIndex = currentIndex
        }
    }

    public static func getSpaceInfo() -> SpaceInfo? {
        ensureInitialized()
        var info = ISSSpaceInfo()
        guard iss_get_space_info(&info) else { return nil }
        return SpaceInfo(spaceCount: Int(info.spaceCount), currentIndex: Int(info.currentIndex))
    }
}