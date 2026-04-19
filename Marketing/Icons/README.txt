JellySeeTV Icon Assets
======================

AppStore/
  icon_1024x1024.png          - App Store Connect marketing icon (flat, no alpha)

IconComposer_Source/
  foreground_transparent_1024.png - Master file for Xcode 26 Icon Composer

tvOS_Layered_Large_AppStore/  - 2560x1536 (@2x of 1280x768), tvOS App Store
  layer_background.png
  layer_foreground.png

tvOS_Layered_Small_HomeScreen/ - 800x480 (@2x of 400x240), tvOS Home Screen
  layer_background.png
  layer_foreground.png

WORKFLOW
--------
Preferred (Xcode 26 / tvOS 26):
  1. Xcode -> File -> New -> File -> "Icon" (Icon Composer)
  2. Import foreground_transparent_1024.png as Foreground Layer
  3. Add solid black Background Layer
  4. Export to Asset Catalog

Legacy Asset Catalog:
  1. Assets.xcassets -> New -> tvOS App Icon & Top Shelf Image
  2. Drop foreground + background PNGs into matching slots

App Store Connect:
  Upload icon_1024x1024.png under App Information
