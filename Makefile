SHELL := /bin/bash
.PHONY: build check format test package
build:
	swift build
check:
	./Scripts/lint.sh lint
format:
	./Scripts/lint.sh format
test:
	swift test
package:
	./Scripts/package_app.sh
