SHELL := /bin/bash

.PHONY: install-dev-tools format format-check lint lint-baseline smoke test ci

install-dev-tools:
	./Scripts/install-swift-tools.sh

format:
	./Scripts/format.sh

format-check:
	./Scripts/format.sh check

lint:
	./Scripts/lint.sh

lint-baseline:
	./Scripts/lint.sh --write-baseline

test:
	./Scripts/test.sh

smoke:
	./Scripts/smoke.sh

ci:
	$(MAKE) lint
	$(MAKE) smoke
	$(MAKE) test
