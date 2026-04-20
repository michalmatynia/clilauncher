SHELL := /bin/bash

.PHONY: lint test ci

lint:
	./Scripts/lint.sh

test:
	./Scripts/test.sh

ci:
	$(MAKE) lint
	$(MAKE) test
