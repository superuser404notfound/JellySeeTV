Premium Icon Assets - JellySeeTV
=================================

USE CASE: Premium-Variante des JellySeeTV Logos mit goldener Krone.
Verwendung in der UI (NICHT als App Icon - dafür gibt's das separate Asset).

STRUKTUR
--------

UI_Assets/  (SwiftUI/UIKit Image Assets, drag-in Assets.xcassets)
  PremiumLogo_Hero.imageset    - 200pt - Splash, About-Screen Hero
  PremiumLogo_Medium.imageset  - 80pt  - Header, prominent placement
  PremiumLogo_Small.imageset   - 40pt  - Settings Rows, List Items
  PremiumBadge.imageset        - 24pt  - Inline badge (neben Username etc.)

LaunchScreen/
  LaunchHero.imageset                - iOS Launch Screen Storyboard
  tvOS_LaunchImage_1920x1080.png     - tvOS Static Launch Image

_Source/
  premium_transparent_1024.png       - Master (transparent BG)
  premium_transparent_2048.png       - Hi-Res Master
  premium_original_1024_black_bg.png - Original mit schwarzem BG


INTEGRATION IN XCODE
====================

1) UI Assets:
   - Ziehe alle .imageset Ordner aus UI_Assets/ in dein Assets.xcassets
   - In SwiftUI verwenden:
       Image("PremiumLogo_Hero")
           .resizable()
           .scaledToFit()
           .frame(width: 200, height: 200)

2) iOS Launch Screen (Storyboard):
   - Ziehe LaunchHero.imageset in dein Assets.xcassets
   - Öffne LaunchScreen.storyboard
   - Füge UIImageView hinzu, setze Image = "LaunchHero"
   - Constraints: Center Horizontally + Vertically, 200x200 (oder deine Präferenz)
   - Background: Black

3) tvOS Launch Image:
   - Ziehe tvOS_LaunchImage_1920x1080.png in dein Assets.xcassets als "LaunchImage"
   - In Info.plist ist dies bereits als UILaunchImageFile referenziert
   - Alternativ: LaunchScreen Storyboard analog zu iOS

4) Premium Gating (Beispiel SwiftUI):
   ```swift
   struct LogoView: View {
       let isPremium: Bool
       var body: some View {
           Image(isPremium ? "PremiumLogo_Medium" : "Logo_Medium")
               .resizable()
               .scaledToFit()
       }
   }
   ```

HINWEISE
--------
- preserves-vector-representation ist in Contents.json aktiviert,
  falls du später SVG/PDF Assets nachrüstest
- template-rendering-intent = "original" damit die Goldfarbe erhalten bleibt
  (nicht als Template Image gerendert wird)
- Transparenter Hintergrund erlaubt Verwendung auf jedem UI-Hintergrund
