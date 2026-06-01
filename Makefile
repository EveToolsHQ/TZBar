VERSION = 1.0
APP = TZBar.app
DMG = TZBar-$(VERSION).dmg

APP_RESOURCES = $(APP)/Contents/Info.plist $(APP)/Contents/Resources/AppIcon.icns

build: $(APP_RESOURCES)
	swift build
	mkdir -p $(APP)/Contents/MacOS
	cp .build/debug/TZBar $(APP)/Contents/MacOS/TZBar

run: build
	$(APP)/Contents/MacOS/TZBar

build-release: $(APP_RESOURCES)
	swift build -c release --arch arm64 --arch x86_64
	mkdir -p $(APP)/Contents/MacOS
	cp .build/release/TZBar $(APP)/Contents/MacOS/TZBar

$(APP)/Contents/Info.plist: packaging/Info.plist
	mkdir -p $(@D)
	cp $< $@

packaging/AppIcon.icns: packaging/AppIcon.png
	pnpm icns-generator -i $< -O .icons
	cp .icons/icon.icns $@

$(APP)/Contents/Resources/AppIcon.icns: packaging/AppIcon.icns
	mkdir -p $(@D)
	cp $< $@

build-signed: build-release
	codesign --force --timestamp --options runtime \
		--entitlements packaging/entitlements.plist \
		--sign "$(APPLE_CODESIGN_IDENTITY)" $(APP)/Contents/MacOS/TZBar

	codesign --force --timestamp --options runtime \
		--entitlements packaging/entitlements.plist \
		--sign "$(APPLE_CODESIGN_IDENTITY)" $(APP)

dmg: build-release
	rm -f $(DMG)
	pnpm appdmg packaging/dmg.json $(DMG)
	pnpm fileicon set $(DMG) packaging/AppIcon.icns

dmg-signed: build-signed
	rm -f $(DMG)
	pnpm appdmg packaging/dmg.json $(DMG)
	pnpm fileicon set $(DMG) packaging/AppIcon.icns
	codesign --force --timestamp --sign "$(APPLE_CODESIGN_IDENTITY)" $(DMG)

release: dmg-signed
	xcrun notarytool submit $(DMG) --wait \
		--key "$(APPLE_API_KEY_PATH)" --key-id "$(APPLE_API_KEY)" --issuer "$(APPLE_API_ISSUER)"

	xcrun stapler staple $(DMG)

clean:
	swift package clean
	rm -rf $(APP) .icons $(DMG)

bump:
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" packaging/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(VERSION)" packaging/Info.plist
