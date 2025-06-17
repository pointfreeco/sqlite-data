CONFIG = Debug

DERIVED_DATA_PATH = ~/.derivedData/$(CONFIG)

PLATFORM_IOS = iOS Simulator,id=$(call udid_for,iPhone)
PLATFORM = IOS
DESTINATION = platform="$(PLATFORM_$(PLATFORM))"
SCHEME = Reminders

PLATFORM_ID = $(shell echo "$(DESTINATION)" | sed -E "s/.+,id=(.+)/\1/")

XCODEBUILD_ARGUMENT = test

XCODEBUILD_FLAGS = \
	-configuration $(CONFIG) \
	-derivedDataPath $(DERIVED_DATA_PATH) \
	-destination $(DESTINATION) \
	-scheme "$(SCHEME)" \
	-skipMacroValidation \
	-project Examples/Examples.xcodeproj

XCODEBUILD_COMMAND = xcodebuild $(XCODEBUILD_ARGUMENT) $(XCODEBUILD_FLAGS)

# TODO: Prefer 'xcbeautify --quiet' when this is fixed:
# https://github.com/cpisciotta/xcbeautify/issues/339
ifneq ($(strip $(shell which xcbeautify)),)
	XCODEBUILD = set -o pipefail && $(XCODEBUILD_COMMAND) | xcbeautify
else
	XCODEBUILD = $(XCODEBUILD_COMMAND)
endif

TEST_RUNNER_CI = $(CI)

warm-simulator:
	@test "$(PLATFORM_ID)" != "" \
		&& xcrun simctl boot $(PLATFORM_ID) \
		&& open -a Simulator --args -CurrentDeviceUDID $(PLATFORM_ID) \
		|| exit 0

xcodebuild: warm-simulator
	$(XCODEBUILD)

xcodebuild-raw: warm-simulator
	$(XCODEBUILD_COMMAND)

.PHONY: warm-simulator xcodebuild xcodebuild-raw

define udid_for
$(shell xcrun simctl list --json devices available '$(1)' | jq -r '[.devices|to_entries|sort_by(.key)|reverse|.[].value|select(length > 0)|.[0]][0].udid')
endef
