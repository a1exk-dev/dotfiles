-- Omarchy scene script, registered by the Omarchy Scene collection.
--
-- The obs-scene hooks render theme.txt, chat.css and the SVG chrome into
-- ~/.config/obs-studio/omarchy-scene/. OBS reloads the SVGs by itself; this
-- script carries the rest into the running scene, with no port and no
-- obs-websocket:
--   * every second it pushes a changed theme.txt (font face and colours) into
--     the text sources and a changed chat.css into the Chat source, and updates
--     the clock, the date and the Starting countdown;
--   * while a scene holds pulse layers, it fades their "pulse" colour filters so
--     a few blocks slowly brighten and dim;
--   * while a scene holds the avatar, it shows the avatar in place of a hidden or
--     frameless camera, nods it to the beat, breathes its glow and blinks.

obs = obslua

local CONFIG_HOME = os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")
local SCENE_DIR = CONFIG_HOME .. "/obs-studio/omarchy-scene/"
local PULSES = 6
local TICK_MS = 33

local countdown_seconds = 300
local bpm = 90
local next_blink = 3
local last_theme = nil
local last_css = nil
local last_text = {}
local scene_name = ""
local scene_since = os.time()
local clock = 0

local function read(path)
	local file = io.open(path, "r")
	if not file then return nil end
	local content = file:read("*a")
	file:close()
	return content
end

-- Runs action with the named source and reports whether the source exists.
local function with_source(name, action)
	local source = obs.obs_get_source_by_name(name)
	if source == nil then return false end
	action(source)
	obs.obs_source_release(source)
	return true
end

local function update_settings(source, fill)
	local settings = obs.obs_data_create()
	fill(settings)
	obs.obs_source_update(source, settings)
	obs.obs_data_release(settings)
end

local function update_source(name, fill)
	with_source(name, function(source) update_settings(source, fill) end)
end

local function set_filter_opacity(source, filter_name, opacity)
	local filter = obs.obs_source_get_filter_by_name(source, filter_name)
	if filter == nil then return end
	local settings = obs.obs_data_create()
	obs.obs_data_set_double(settings, "opacity", opacity)
	obs.obs_source_update(filter, settings)
	obs.obs_data_release(settings)
	obs.obs_source_release(filter)
end

local function set_text(name, text)
	if last_text[name] == text then return end
	last_text[name] = text
	update_source(name, function(settings) obs.obs_data_set_string(settings, "text", text) end)
end

-- theme.txt: "face=<font>", then one "<source>\t<colour>\t<size>" line per text source.
local function apply_theme(content)
	local face = content:match("^face=([^\n]*)")
	for name, color, size in content:gmatch("\n([^\t\n]+)\t(%d+)\t(%d+)") do
		update_source(name, function(settings)
			local font = obs.obs_data_create()
			obs.obs_data_set_string(font, "face", face)
			obs.obs_data_set_string(font, "style", "Regular")
			obs.obs_data_set_int(font, "size", tonumber(size))
			obs.obs_data_set_int(font, "flags", 0)
			obs.obs_data_set_obj(settings, "font", font)
			obs.obs_data_release(font)
			obs.obs_data_set_int(settings, "color1", tonumber(color))
			obs.obs_data_set_int(settings, "color2", tonumber(color))
		end)
	end
	obs.script_log(obs.LOG_INFO, "applied theme.txt with font " .. tostring(face))
end

-- A changed css setting reloads the browser source, so push only real changes.
local function apply_chat_css(css)
	return with_source("Chat", function(source)
		local settings = obs.obs_source_get_settings(source)
		local current = obs.obs_data_get_string(settings, "css")
		obs.obs_data_release(settings)
		if current == css then return end
		update_settings(source, function(update) obs.obs_data_set_string(update, "css", css) end)
		obs.script_log(obs.LOG_INFO, "applied chat.css")
	end)
end

local function tick()
	local theme = read(SCENE_DIR .. "theme.txt")
	if theme and theme ~= last_theme then
		last_theme = theme
		last_text = {}
		apply_theme(theme)
	end
	local css = read(SCENE_DIR .. "chat.css")
	if css and css ~= last_css and apply_chat_css(css) then
		last_css = css
	end
	set_text("Clock", os.date("%H:%M:%S"))
	set_text("Date", os.date("%Y-%m-%d %a"))
	if scene_name == "Starting" then
		local left = countdown_seconds - (os.time() - scene_since)
		set_text("Countdown", left > 0 and string.format("%02d:%02d", math.floor(left / 60), left % 60) or "any moment now")
	end
end

-- Each pulse layer breathes on its own period; the cubic curve keeps it dark
-- most of the time, so only a few blocks glow at once.
local function pulse(scene)
	for _, prefix in ipairs({ "Strip pulse ", "Card pulse " }) do
		if obs.obs_scene_find_source(scene, prefix .. "0") ~= nil then
			for k = 0, PULSES - 1 do
				local period = 5 + k * 1.3
				local wave = 0.5 - 0.5 * math.cos(2 * math.pi * (clock / period + k * 0.37))
				with_source(prefix .. k, function(source) set_filter_opacity(source, "pulse", wave ^ 3) end)
			end
		end
	end
end

local AVATAR_LAYERS = { "Avatar back", "Avatar head1", "Avatar head2", "Avatar head3", "Avatar eyes", "Avatar glow" }
-- The head bends: each band moves its share of the dip, and the rows below the
-- lowest band stay in the back layer, so no seam opens at the shoulders.
local AVATAR_SHARES = { ["Avatar head1"] = 1 / 3, ["Avatar head2"] = 2 / 3, ["Avatar head3"] = 1,
	["Avatar eyes"] = 2 / 3, ["Avatar glow"] = 2 / 3 }

-- Pixels the head dips at this moment: 2, 3, then 1 through the first 45% of each beat.
local function dip()
	local beat = (clock * bpm / 60) % 1
	if beat < 0.1 then return 2 end
	if beat < 0.28 then return 3 end
	if beat < 0.45 then return 1 end
	return 0
end

-- The avatar shows while the camera item is hidden or the camera has no frames.
local function avatar(scene)
	local back = obs.obs_scene_find_source(scene, "Avatar back")
	if back == nil then return end
	local show = true
	local camera = obs.obs_scene_find_source(scene, "Camera")
	if camera ~= nil then
		show = not obs.obs_sceneitem_visible(camera) or obs.obs_source_get_width(obs.obs_sceneitem_get_source(camera)) == 0
	end
	local blinking = clock > next_blink
	if clock > next_blink + 0.15 then next_blink = clock + 2.5 + math.random() * 4 end
	for _, name in ipairs(AVATAR_LAYERS) do
		local item = obs.obs_scene_find_source(scene, name)
		if item ~= nil then
			local visible = show and not (blinking and (name == "Avatar eyes" or name == "Avatar glow"))
			if obs.obs_sceneitem_visible(item) ~= visible then obs.obs_sceneitem_set_visible(item, visible) end
		end
	end
	if not show then return end

	local base = obs.vec2()
	obs.obs_sceneitem_get_pos(back, base)
	local position = obs.vec2()
	position.x = base.x
	local depth = dip()
	for name, share in pairs(AVATAR_SHARES) do
		local item = obs.obs_scene_find_source(scene, name)
		if item ~= nil then
			position.y = base.y + math.floor(depth * share + 0.5)
			obs.obs_sceneitem_set_pos(item, position)
		end
	end
	local breath = 0.5 - 0.5 * math.cos(math.pi * clock)
	with_source("Avatar glow", function(source) set_filter_opacity(source, "glow", 0.5 + 0.5 * breath) end)
end

local function animate()
	clock = clock + TICK_MS / 1000
	local source = obs.obs_frontend_get_current_scene()
	if source == nil then return end
	local scene = obs.obs_scene_from_source(source)
	pulse(scene)
	avatar(scene)
	obs.obs_source_release(source)
end

local function on_event(event)
	if event == obs.OBS_FRONTEND_EVENT_SCENE_CHANGED or event == obs.OBS_FRONTEND_EVENT_FINISHED_LOADING then
		local scene = obs.obs_frontend_get_current_scene()
		if scene ~= nil then
			scene_name = obs.obs_source_get_name(scene)
			obs.obs_source_release(scene)
		end
		scene_since = os.time()
	end
end

function script_description()
	return "Omarchy scene: follows the Omarchy theme and font, and drives the clock, countdown, animated blocks and camera-off avatar."
end

function script_properties()
	local properties = obs.obs_properties_create()
	obs.obs_properties_add_int(properties, "countdown_minutes", "Starting countdown (minutes)", 1, 60, 1)
	obs.obs_properties_add_int(properties, "avatar_bpm", "Avatar nod tempo (BPM)", 40, 200, 1)
	return properties
end

function script_defaults(settings)
	obs.obs_data_set_default_int(settings, "countdown_minutes", 5)
	obs.obs_data_set_default_int(settings, "avatar_bpm", 90)
end

function script_update(settings)
	countdown_seconds = obs.obs_data_get_int(settings, "countdown_minutes") * 60
	bpm = obs.obs_data_get_int(settings, "avatar_bpm")
end

function script_load(settings)
	obs.obs_frontend_add_event_callback(on_event)
	obs.timer_add(tick, 1000)
	obs.timer_add(animate, TICK_MS)
end

function script_unload()
	obs.timer_remove(tick)
	obs.timer_remove(animate)
end
