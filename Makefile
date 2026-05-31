build: TZBar.app/Contents/Info.plist TZBar.app/Contents/Resources/AppIcon.icns
	swift build -c release
	mkdir -p TZBar.app/Contents/MacOS
	cp .build/release/TZBar TZBar.app/Contents/MacOS/TZBar
	chmod +x TZBar.app/Contents/MacOS/TZBar

TZBar.app/Contents/Info.plist: packaging/Info.plist
	mkdir -p $(@D)
	cp $< $@

TZBar.app/Contents/Resources/AppIcon.icns: packaging/AppIcon.png
	mkdir -p $(@D) .icons/AppIcon.iconset
	sips -z 16 16 $< --out .icons/AppIcon.iconset/icon_16x16.png >/dev/null
	sips -z 32 32 $< --out .icons/AppIcon.iconset/icon_16x16@2x.png >/dev/null
	sips -z 32 32 $< --out .icons/AppIcon.iconset/icon_32x32.png >/dev/null
	sips -z 64 64 $< --out .icons/AppIcon.iconset/icon_32x32@2x.png >/dev/null
	sips -z 128 128 $< --out .icons/AppIcon.iconset/icon_128x128.png >/dev/null
	sips -z 256 256 $< --out .icons/AppIcon.iconset/icon_128x128@2x.png >/dev/null
	sips -z 256 256 $< --out .icons/AppIcon.iconset/icon_256x256.png >/dev/null
	sips -z 512 512 $< --out .icons/AppIcon.iconset/icon_256x256@2x.png >/dev/null
	sips -z 512 512 $< --out .icons/AppIcon.iconset/icon_512x512.png >/dev/null
	sips -z 1024 1024 $< --out .icons/AppIcon.iconset/icon_512x512@2x.png >/dev/null
	iconutil -c icns .icons/AppIcon.iconset -o $@

run:
	swift run TZBar

clean:
	swift package clean
	rm -rf TZBar.app .icons
