.DEFAULT_GOAL := wizard

.PHONY: wizard applications skills skills-update wallpapers screensaver-effects input-languages test
wizard:
	@./bin/dotfiles

applications:
	@./bin/dotfiles --action applications

skills:
	@./bin/dotfiles --action skills

skills-update:
	@./bin/dotfiles --action skills-update

wallpapers:
	@./bin/dotfiles --action wallpapers

screensaver-effects:
	@./bin/dotfiles --action screensaver-effects

input-languages:
	@./bin/dotfiles --action input-languages

test:
	@./tests/run.sh
