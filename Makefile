.PHONY: check format format-check lint syntax test tools

check:
	./scripts/check.sh

format:
	./scripts/format.sh

format-check:
	./scripts/format.sh --check

lint:
	./scripts/lint.sh

syntax:
	./scripts/syntax.sh

test:
	./scripts/test.sh

tools:
	./scripts/check-tools.sh
