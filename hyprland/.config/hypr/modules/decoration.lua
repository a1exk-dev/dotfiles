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
