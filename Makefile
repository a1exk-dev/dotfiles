.DEFAULT_GOAL := wizard

.PHONY: wizard skills skills-update test
wizard:
	@./bin/dotfiles

skills:
	@./bin/dotfiles skills

skills-update:
	@./bin/dotfiles skills-update

test:
	@./tests/run.sh
