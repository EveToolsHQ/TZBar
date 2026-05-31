.PHONY: build run clean

build:
	./scripts/build-app.sh

run:
	swift run TZBar

clean:
	swift package clean
	rm -rf TZBar.app/Contents/MacOS TZBar.app/Contents/Info.plist
