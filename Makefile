.DEFAULT_GOAL := wizard

.PHONY: wizard applications skills skills-update wallpapers screensaver-effects voxtype voxtype-gpu test
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

voxtype:
	@./bin/dotfiles --action voxtype-profile

voxtype-gpu:
	@sudo voxtype setup gpu --enable
	@systemctl --user restart voxtype
	@voxtype info accel

test:
	@./tests/run.sh
