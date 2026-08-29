.DEFAULT_GOAL := wizard

.PHONY: wizard skills skills-update wallpapers screensaver-effects test
wizard:
	@./bin/dotfiles

skills:
	@./bin/dotfiles --action skills

skills-update:
	@./bin/dotfiles --action skills-update

wallpapers:
	@./bin/dotfiles --action wallpapers

screensaver-effects:
	@./bin/dotfiles --action screensaver-effects

test:
	@./tests/run.sh
