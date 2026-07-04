#!/bin/sh

exec ghostty --class=calendar --title=calendar -e sh -lc 'cal -3; printf "\nPress Enter to close..."; read -r _'
