# TrafficLightKit

Read `README.md` and `Package.swift` first. This is a small SwiftUI library for
the **macOS 27 Liquid Glass** traffic-light appearance, using Swift 6.4 / Xcode 27.

## Integrating into another app

- Add the package and its `TrafficLightKit` product to the app target.
- Use `TrafficLightGroup` with three `TrafficLightButton` views, as in the README.
- Supply the app's existing actions, localized labels and document-edited state.
- Keep `.disabled(...)` tied to the app's actual capabilities.
- The green hover menu and window-management implementation are outside scope.
- Do not add capture tools, permissions, calibration data files or dependencies.

## Changing this library

- Preserve the small public API and macOS 27 appearance. Do not add older-OS
  fallbacks or unrelated window-management features without an explicit request.
- Keep AppKit artwork decorative; only the semantic button invokes actions.
- Material coefficients are intentional runtime data. Do not round, delete or
  regenerate them to make the repository smaller without validating rendering.
- Run `swift build` and `swift test`. Report test results separately from visual
  fidelity; unit tests do not prove native pixel identity.
