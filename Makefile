# Common tasks. Requires Xcode 27.1+ with the iOS 27.1 simulator runtime.
PROJECT     := Duor.xcodeproj
SCHEME      := Duor
SIMULATOR   := iPhone Duo
DESTINATION := platform=iOS Simulator,name=$(SIMULATOR)
BUNDLE_ID   := com.jeffkroon.Duor
DERIVED     := build/DerivedData
APP         := $(DERIVED)/Build/Products/Debug-iphonesimulator/Duor.app

.PHONY: build test run sounds format lint clean

build:
	xcodebuild build -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -derivedDataPath $(DERIVED)

test:
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -derivedDataPath $(DERIVED)

run: build
	xcrun simctl boot "$(SIMULATOR)" 2>/dev/null || true
	open -a DeviceHub
	xcrun simctl install "$(SIMULATOR)" $(APP)
	xcrun simctl launch "$(SIMULATOR)" $(BUNDLE_ID)

# Render every synthesized sound to build/sounds/*.wav for listening (afplay) and tuning.
sounds:
	mkdir -p build
	xcrun swiftc -O -swift-version 6 Duor/Audio/DSP/*.swift Tools/RenderSounds/main.swift -o build/render-sounds
	build/render-sounds build/sounds

format:
	swift format --in-place --recursive Duor DuorTests Tools

lint:
	swift format lint --strict --recursive Duor DuorTests Tools

clean:
	rm -rf build
