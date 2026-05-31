build: TZBar.app/Contents/Info.plist TZBar.app/Contents/Resources/AppIcon.icns
	swift build -c release
	mkdir -p TZBar.app/Contents/MacOS
	cp .build/release/TZBar TZBar.app/Contents/MacOS/TZBar
	chmod +x TZBar.app/Contents/MacOS/TZBar

TZBar.app/Contents/Info.plist: packaging/Info.plist
	mkdir -p $(@D)
	cp $< $@

packaging/AppIcon.icns: packaging/AppIcon.png
	pnpm dlx icns-generator -i $< -O .icons
	cp .icons/icon.icns $@

TZBar.app/Contents/Resources/AppIcon.icns: packaging/AppIcon.icns
	mkdir -p $(@D)
	cp $< $@

run:
	swift run TZBar

clean:
	swift package clean
	rm -rf TZBar.app .icons
