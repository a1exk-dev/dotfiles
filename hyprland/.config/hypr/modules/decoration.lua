hl.config({
	decoration = {
		rounding = 10,
		rounding_power = 2,

		-- Change transparency of focused and unfocused windows
		active_opacity = 0.9,
		inactive_opacity = 0.7,
		fullscreen_opacity = 0.9,

		shadow = {
			enabled = true,
			range = 4,
			render_power = 3,
			color = 0xee1a1a1a,
		},

		blur = {
			enabled = true,
			size = 8,
			passes = 2,
			ignore_opacity = true,
			new_optimizations = true,
			vibrancy = 0.2,
		},
	},
})

hl.layer_rule({
	name = "waybar-ignore-alpha",
	match = { namespace = "^waybar$" },
	ignore_alpha = 0.1,
})

hl.layer_rule({
	name = "waybar-blur",
	match = { namespace = "^waybar$" },
	blur = true,
})
