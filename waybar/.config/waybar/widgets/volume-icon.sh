#!/bin/sh

case "$0" in
	*/*)
		widget_dir=${0%/*}
		;;
	*)
		widget_dir=.
		;;
esac

exec "$widget_dir/volume.sh" icon
