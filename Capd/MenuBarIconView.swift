import AppKit
import Foundation
import SwiftUI

struct MenuBarRingIconView: View {
  @EnvironmentObject private var batteryMonitor: BatteryMonitor

  @AppStorage(CapdConstants.defaultsChargeLimitKey)
  private var limitPercent: Int = CapdConstants.defaultChargeLimitPercent

  @AppStorage(CapdConstants.defaultsColoredIconKey)
  private var coloredIconEnabled: Bool = false

  var body: some View {
    let percent = batteryMonitor.snapshot.percentage
    let limit = CapdConstants.clampLimit(limitPercent)
    let image = MenuBarRingIcon.image(
      currentPercent: percent,
      limitPercent: limit,
      colored: coloredIconEnabled
    )
    Image(nsImage: image)
      .renderingMode(.original)
      .frame(width: 18, height: 18)
      .accessibilityLabel(Text("Capd"))
  }
}

enum MenuBarRingIcon {
  static func image(currentPercent: Int, limitPercent: Int, colored: Bool) -> NSImage {
    let size = NSSize(width: 18, height: 18)
    let lineWidth: CGFloat = 2.2
    let ringColor = colored
      ? NSColor(srgbRed: 0.20, green: 0.86, blue: 0.50, alpha: 1.0)
      : NSColor.white
    let trackColor = colored
      ? NSColor(srgbRed: 0.20, green: 0.86, blue: 0.50, alpha: 0.35)
      : NSColor.white.withAlphaComponent(0.25)

    return NSImage(size: size, flipped: false) { rect in
      let radius = min(rect.width, rect.height) / 2 - lineWidth / 2
      let center = CGPoint(x: rect.midX, y: rect.midY)
      let startAngle: CGFloat = 90

      NSGraphicsContext.current?.imageInterpolation = .high

      let track = NSBezierPath()
      track.appendArc(
        withCenter: center,
        radius: radius,
        startAngle: 0,
        endAngle: 360,
        clockwise: false
      )
      track.lineWidth = lineWidth
      track.lineCapStyle = .round
      trackColor.setStroke()
      track.stroke()

      let clampedPercent = max(0, min(currentPercent, 100))
      if clampedPercent > 0 {
        let endAngle = startAngle - (360 * CGFloat(clampedPercent) / 100)
        let progress = NSBezierPath()
        progress.appendArc(
          withCenter: center,
          radius: radius,
          startAngle: startAngle,
          endAngle: endAngle,
          clockwise: true
        )
        progress.lineWidth = lineWidth
        progress.lineCapStyle = .round
        ringColor.setStroke()
        progress.stroke()
      }

      let clampedLimit = max(CapdConstants.minChargeLimitPercent, min(limitPercent, 100))
      let limitReached = clampedPercent >= clampedLimit
      if clampedLimit < 100 {
        let limitAngle = (startAngle - (360 * CGFloat(clampedLimit) / 100)) * (.pi / 180)
        let direction = CGPoint(
          x: CGFloat(cos(Double(limitAngle))),
          y: CGFloat(sin(Double(limitAngle)))
        )
        let innerEdge = radius - (lineWidth / 2)
        let notchDepth = max(2.5, lineWidth * 1.4)
        let startPoint = CGPoint(
          x: center.x + direction.x * innerEdge,
          y: center.y + direction.y * innerEdge
        )
        let endPoint = CGPoint(
          x: center.x + direction.x * (innerEdge - notchDepth),
          y: center.y + direction.y * (innerEdge - notchDepth)
        )

        let notch = NSBezierPath()
        notch.move(to: startPoint)
        notch.line(to: endPoint)
        notch.lineWidth = lineWidth
        notch.lineCapStyle = .round
        (limitReached ? ringColor : trackColor).setStroke()
        notch.stroke()
      }

      return true
    }
  }
}
