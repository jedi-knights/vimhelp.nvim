.PHONY: test lint format check

# Run the plenary-busted test suite headlessly.
test:
	nvim --headless -u scripts/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/ { minimal_init = 'scripts/minimal_init.lua' }"

lint:
	@if ! command -v stylua > /dev/null; then \
		echo "install stylua: https://github.com/JohnnyMorganz/StyLua"; \
		exit 1; \
	fi
	stylua --check .

format:
	@if ! command -v stylua > /dev/null; then \
		echo "install stylua: https://github.com/JohnnyMorganz/StyLua"; \
		exit 1; \
	fi
	stylua .

check: lint test
