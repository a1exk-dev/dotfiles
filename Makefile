.DEFAULT_GOAL := wizard

.PHONY: wizard skills skills-update wallpapers test
wizard:
	@./bin/dotfiles

skills:
	@./bin/dotfiles --action skills

skills-update:
	@./bin/dotfiles --action skills-update

wallpapers:
	@./bin/dotfiles --action wallpapers

test:
	@./tests/run.sh
