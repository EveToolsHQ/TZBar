build: TZBar.app/Contents/Info.plist TZBar.app/Contents/Resources/AppIcon.icns
	swift build -c release --arch arm64 --arch x86_64
	mkdir -p TZBar.app/Contents/MacOS
	cp .build/release/TZBar TZBar.app/Contents/MacOS/TZBar
	chmod +x TZBar.app/Contents/MacOS/TZBar

TZBar.app/Contents/Info.plist: packaging/Info.plist
	mkdir -p $(@D)
	cp $< $@

packaging/AppIcon.icns: packaging/AppIcon.png
	pnpm icns-generator -i $< -O .icons
	cp .icons/icon.icns $@

TZBar.app/Contents/Resources/AppIcon.icns: packaging/AppIcon.icns
	mkdir -p $(@D)
	cp $< $@

dmg: build packaging/AppIcon.icns
	rm -rf TZBar.dmg
	pnpm appdmg packaging/dmg.json TZBar.dmg
	pnpm fileicon set TZBar.dmg packaging/AppIcon.icns

run:
	swift run TZBar

clean:
	swift package clean
	rm -rf TZBar.app .icons TZBar.dmg
