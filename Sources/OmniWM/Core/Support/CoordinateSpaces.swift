// SPDX-License-Identifier: GPL-2.0-only
import CoreGraphics
import Foundation


struct AppKitPoint: Hashable {
    let raw: CGPoint
    init(_ raw: CGPoint) { self.raw = raw }
}

struct AppKitRect: Hashable {
    let raw: CGRect
    init(_ raw: CGRect) { self.raw = raw }
}

struct QuartzPoint: Hashable {
    let raw: CGPoint
    init(_ raw: CGPoint) { self.raw = raw }
}

struct QuartzRect: Hashable {
    let raw: CGRect
    init(_ raw: CGRect) { self.raw = raw }
}

struct BackingRect: Hashable {
    let raw: CGRect
    init(_ raw: CGRect) { self.raw = raw }
}

extension AppKitRect {
    func toQuartz() -> QuartzRect {
        QuartzRect(ScreenCoordinateSpace.toWindowServer(rect: raw))
    }

    func toBacking(scale: CGFloat) -> BackingRect {
        BackingRect(
            CGRect(
                x: raw.origin.x * scale,
                y: raw.origin.y * scale,
                width: raw.size.width * scale,
                height: raw.size.height * scale
            )
        )
    }
}

extension QuartzRect {
    func toAppKit() -> AppKitRect {
        AppKitRect(ScreenCoordinateSpace.toAppKit(rect: raw))
    }
}

extension AppKitPoint {
    func toQuartz() -> QuartzPoint {
        QuartzPoint(ScreenCoordinateSpace.toWindowServer(point: raw))
    }
}

extension QuartzPoint {
    func toAppKit() -> AppKitPoint {
        AppKitPoint(ScreenCoordinateSpace.toAppKit(point: raw))
    }
}
