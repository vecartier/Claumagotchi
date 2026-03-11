.PHONY: build install uninstall clean

build:
	@./build.sh

install: build
	@echo ""
	@echo "Setting up Claude Code hooks..."
	@python3 setup.py
	@echo ""
	@echo "Launching ClawGotchi..."
	@open ClawGotchi.app

uninstall:
	@echo "Uninstalling ClawGotchi..."
	@python3 uninstall.py

clean:
	@rm -rf .build ClawGotchi.app
	@echo "Cleaned build artifacts"
