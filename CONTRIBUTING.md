# Contributing to MrMouse

Thanks for your interest in contributing! MrMouse is a lightweight macOS driver for Logitech MX Master mice, and contributions are welcome.

## Getting Started

1. Fork the repo and clone your fork
2. Open `mrmouse/mrmouse.xcodeproj` in Xcode
3. Build and run the `mrmouse` scheme (requires macOS 26+)

## Requirements

- macOS 26 (Tahoe) or later
- Xcode 26+
- A Logitech MX Master mouse (3S tested, others may work)

## Permissions

MrMouse requires **Accessibility** permission for CGEventTap. Grant this in System Settings > Privacy & Security > Accessibility when prompted.

## How to Contribute

1. Check existing issues or open a new one to discuss your idea
2. Create a branch from `main`
3. Make your changes
4. Test with a real device if possible
5. Open a pull request

## Areas Where Help is Needed

- **Desktop switching** — finding a working approach on macOS 26 Tahoe (see README for details on the OS-level limitation)
- **Additional Logitech devices** — testing and adding support for other MX Master models
- **BLE transport** — completing the CoreBluetooth path as an alternative to the Bolt receiver
- **UI polish** — improving the settings window

## Code Style

- Follow existing patterns in the codebase
- Use `NSLog` for debug logging (will be cleaned up before 1.0)
- Keep HID++ protocol code in `HIDPPCore/`, event handling in `EventEngine/`, config in `Config/`

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
