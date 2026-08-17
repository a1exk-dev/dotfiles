.DEFAULT_GOAL := wizard

.PHONY: wizard skills skills-update test
wizard:
	@./bin/dotfiles

skills:
	@./bin/dotfiles --action skills

skills-update:
	@./bin/dotfiles --action skills-update

test:
	@./tests/run.sh
