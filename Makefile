.PHONY: all qa unit install test-device test-ui
all:
	bash build.sh
qa:
	bash build.sh --tests
unit:
	python3 Tests/run-unit.py
install: all
	sudo -n dpkg -i packages/com.alsinas.sounddeck_0.1.0_iphoneos-arm64.deb
test-device:
	python3 Tests/run-device.py
test-ui:
	python3 Tests/run-ui.py
