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

build-signed: build
	codesign --force --timestamp --options runtime \
		--entitlements packaging/entitlements.plist \
		--sign "$(APPLE_CODESIGN_IDENTITY)" TZBar.app/Contents/MacOS/TZBar

	codesign --force --timestamp --options runtime \
		--entitlements packaging/entitlements.plist \
		--sign "$(APPLE_CODESIGN_IDENTITY)" TZBar.app

dmg: build
	rm -rf TZBar.dmg
	pnpm appdmg packaging/dmg.json TZBar.dmg
	pnpm fileicon set TZBar.dmg packaging/AppIcon.icns

dmg-signed: build-signed
	rm -rf TZBar.dmg
	pnpm appdmg packaging/dmg.json TZBar.dmg
	pnpm fileicon set TZBar.dmg packaging/AppIcon.icns
	codesign --force --timestamp --sign "$(APPLE_CODESIGN_IDENTITY)" TZBar.dmg

release: dmg-signed
	xcrun notarytool submit TZBar.dmg --wait \
		--key "$(APPLE_API_KEY_PATH)" --key-id "$(APPLE_API_KEY)" --issuer "$(APPLE_API_ISSUER)"

	xcrun stapler staple TZBar.dmg

run:
	swift run TZBar

clean:
	swift package clean
	rm -rf TZBar.app .icons TZBar.dmg
