import SwiftUI

/// Design tokens mirrored 1:1 from the Figma variables (see Assets.xcassets/Colors).
/// Asset names follow the Figma variable path: `brand/primary` → `BrandPrimary`.
extension Color {
    // Brand
    static let brandPrimary = Color("BrandPrimary")
    static let brandMint = Color("BrandMint")
    static let brandOnPrimary = Color("BrandOnPrimary")
    static let brandPrimaryPressed = Color("BrandPrimaryPressed")
    // Backgrounds
    static let bgCanvas = Color("BgCanvas")
    static let bgSurface = Color("BgSurface")
    static let bgSurface2 = Color("BgSurface2")
    static let bgSurfaceTranslucent = Color("BgSurfaceTranslucent")
    // Text
    static let textPrimary = Color("TextPrimary")
    static let textSecondary = Color("TextSecondary")
    static let textTertiary = Color("TextTertiary")
    static let textLink = Color("TextLink")
    static let textOnImage = Color("TextOnImage")
    // Status
    static let statusError = Color("StatusError")
    static let statusErrorBg = Color("StatusErrorBg")
    static let statusInfo = Color("StatusInfo")
    static let statusInfoBg = Color("StatusInfoBg")
    static let statusSuccess = Color("StatusSuccess")
    static let statusSuccessBg = Color("StatusSuccessBg")
    static let statusWarning = Color("StatusWarning")
    static let statusWarningBg = Color("StatusWarningBg")
    // Crowd levels
    static let crowdLow = Color("CrowdLow")
    static let crowdLowBg = Color("CrowdLowBg")
    static let crowdMedium = Color("CrowdMedium")
    static let crowdMediumBg = Color("CrowdMediumBg")
    static let crowdHigh = Color("CrowdHigh")
    static let crowdHighBg = Color("CrowdHighBg")
    static let crowdUnknown = Color("CrowdUnknown")
    static let crowdUnknownBg = Color("CrowdUnknownBg")
    /// Plan/Live Step «Active» (#1F3F99) — the experience happening now.
    static let liveActive = Color("LiveActive")
    /// Route glow on the Discover next-stop card (#2BB894).
    static let brandAccent = Color("BrandAccent")
    // Expo axes (المحاور)
    static let axisCoop = Color("AxisCoop")
    static let axisCulture = Color("AxisCulture")
    static let axisHuman = Color("AxisHuman")
    static let axisEarth = Color("AxisEarth")
    static let axisTech = Color("AxisTech")
    // Glass & borders
    static let glassTint = Color("GlassTint")
    static let glassTintStrong = Color("GlassTintStrong")
    static let glassStroke = Color("GlassStroke")
    static let borderDefault = Color("BorderDefault")
    static let borderStrong = Color("BorderStrong")
    static let bgCanvasTranslucent = Color("BgCanvasTranslucent")
    // Map
    static let mapGround = Color("MapGround")
    static let locationBlue = Color("LocationBlue")
    static let locationBlueBg = Color("LocationBlueBg")
    /// Shadow tint used by every Figma drop shadow (#0A1F17).
    static let shadowTint = Color(red: 10 / 255, green: 31 / 255, blue: 23 / 255)
}

extension Color {
    /// Hex helper for one-off Figma values that have no variable (gradients, map art).
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}
