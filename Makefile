# Common tasks. Requires Xcode 27.1+ with the iOS 27.1 simulator runtime.
PROJECT     := Duor.xcodeproj
SCHEME      := Duor
SIMULATOR   := iPhone Duo
DESTINATION := platform=iOS Simulator,name=$(SIMULATOR)
BUNDLE_ID   := com.jeffkroon.Duor
DERIVED     := build/DerivedData
APP         := $(DERIVED)/Build/Products/Debug-iphonesimulator/Duor.app
ARCHIVE     := build/Duor.xcarchive
# Every upload needs a new build number: use the commit count, which only goes up.
BUILD_NUMBER := $(shell git rev-list --count HEAD)

.PHONY: build test test-audio run sounds bench audio-check banner format lint archive upload clean

# On a Mac through xcrun; elsewhere (Linux) the Swift toolchain on the PATH.
SWIFTC := $(shell command -v xcrun >/dev/null 2>&1 && echo xcrun swiftc || echo swiftc)

build:
	xcodebuild build -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -derivedDataPath $(DERIVED)

# The suites that synthesize and measure sound are slow; `make test` skips them, `make test-audio`
# runs everything (as does `make audio-check`, without a simulator).
AUDIO_SUITES := CreakTests GainStagingTests ImpactTests RoomTests RecipeTests SlidingDoorTests \
	SweepTests ScrapeTests SwingSoundTests

test:
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -derivedDataPath $(DERIVED) \
		$(foreach suite,$(AUDIO_SUITES),-skip-testing:DuorTests/$(suite))

test-audio:
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -derivedDataPath $(DERIVED)

run: build
	xcrun simctl boot "$(SIMULATOR)" 2>/dev/null || true
	open -a DeviceHub
	xcrun simctl install "$(SIMULATOR)" $(APP)
	xcrun simctl launch "$(SIMULATOR)" $(BUNDLE_ID)

# Render every synthesized sound to build/sounds/*.wav for listening (afplay) and tuning, and print
# the measurements (loudness against targets, peaks, creak tonality, decay, render cost).
# Compare with an earlier run: make sounds BASELINE=path/to/metrics.json
sounds: build/render-sounds
	build/render-sounds build/sounds --json build/sounds/metrics.json $(if $(BASELINE),--baseline $(BASELINE))

# Render cost only.
bench: build/render-sounds
	build/render-sounds --bench

build/render-sounds: Duor/Audio/DSP/*.swift Tools/RenderSounds/*.swift
	mkdir -p build
	$(SWIFTC) -O -swift-version 6 -default-isolation MainActor Duor/Audio/DSP/*.swift Tools/RenderSounds/*.swift \
		-o build/render-sounds

# The audio and door-logic tests without Xcode or a simulator (also runs on Linux). `make test` runs
# them too, with everything else, as `make test-audio` does.
audio-check:
	swift test --package-path Tools/AudioCheck

# Render the App Store header (21:9) and search results (3:2) artwork to appstore/creative/.
banner:
	mkdir -p build appstore/creative
	xcrun swiftc -O -swift-version 6 Duor/Door/Scenes/*.swift Duor/Door/CatStories.swift Duor/Door/DoorStyle.swift Duor/Door/DoorArt.swift \
		Duor/Audio/DSP/*.swift Tools/RenderBanner/main.swift -o build/render-banner
	build/render-banner appstore/creative

format:
	swift format --in-place --recursive Duor DuorTests Tools

lint:
	swift format lint --strict --recursive Duor DuorTests Tools

# Release archive for the App Store, signed automatically with the team in the project.
archive:
	xcodebuild archive -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-destination 'generic/platform=iOS' -archivePath $(ARCHIVE) -allowProvisioningUpdates \
		CURRENT_PROJECT_VERSION=$(BUILD_NUMBER)

# Uploads the archive to App Store Connect (TestFlight) using the Apple account signed in to Xcode.
upload: archive
	xcodebuild -exportArchive -archivePath $(ARCHIVE) -exportOptionsPlist ExportOptions.plist \
		-exportPath build/export -allowProvisioningUpdates

clean:
	rm -rf build
