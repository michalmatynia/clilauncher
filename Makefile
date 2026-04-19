SHELL := /bin/bash

.PHONY: lint test ci

lint:
\t./Scripts/lint.sh

test:
\t./Scripts/test.sh

ci:
\t$(MAKE) lint
\t$(MAKE) test
