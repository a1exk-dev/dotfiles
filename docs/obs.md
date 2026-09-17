[Back to README](../README.md)

# OBS Studio integration

Three parts connect OBS Studio to Omarchy:

- The `obs-theme` Stow package gives OBS a theme that follows the Omarchy theme and font.
- The `obs-scene` Stow package renders a TUI-styled scene whose look follows the Omarchy theme. It depends on `obs-theme`.
- The `Install OBS set` wizard action copies a machine set into OBS. A machine set holds this machine's OBS profile and the scene collection.

## Requirements

The integration supports Omarchy 4.0 and OBS 32.2. It was tested with these versions:

- Omarchy `4.0.3-1`
- `obs-studio` `32.2.2-1`, the native Arch package (the Flatpak was not tested)
- `obs-studio-plugin-browser` with CEF 151
- AUR `obs-backgroundremoval` `1.4.1`
- `imagemagick` `7.1.2.31-1`
- `bun` `1.4.0-1`

The package plans install what is missing through Omarchy after you approve them. `obs-theme` needs `obs-studio`. `obs-scene` also needs `obs-studio-plugin-browser`, `imagemagick`, `bun`, and the AUR package `obs-backgroundremoval`. Third-party maintainers supply AUR packages, and Arch does not review them. Examine the package before you approve the plan. The browser plugin pulls in `cef`, which takes about 363 MiB.

If the Omarchy version is outside the 4.0 series, the hooks exit with an error and keep their last output, and the wizard steps ask for your consent. If the OBS version is outside the 32.2 series, the hooks print a warning and still run, and every `user.ini` write asks for your consent.

## OBS theme

### What it does

The `obs-theme` package links an Omarchy template, `~/.config/omarchy/themed/obs-omarchy.ovt.tpl`, and two hooks. On each `omarchy theme set` or `omarchy font set`, the hook takes Omarchy's render of the template, adds the current Omarchy font, and writes `~/.config/obs-studio/themes/Omarchy.ovt`. On a light theme, it also adds OBS's dark icons, because the stock icons are white. The theme extends OBS's stock Yami theme. It has a flat background, thin borders, square corners, and the accent colour for focus. Meters and warnings keep the theme's own red, green and yellow.

### Install

Close OBS, run `make`, select `Apply Stow packages`, then select `obs-theme`.

After it links the package, the apply step changes two keys in `~/.config/obs-studio/user.ini`: `[Appearance] Theme` selects the Omarchy theme, and `AutoReload=true` lets OBS reload the theme file while it runs. The step backs up `user.ini` to `~/.config/obs-studio/backups/` first and changes nothing else. If OBS is running, the step changes nothing and asks you to close OBS and apply again. If OBS has never run, start and close it once, then apply again.

Then run `omarchy theme set` once, so the hook writes `Omarchy.ovt`, and start OBS. OBS finds a new theme file only when it starts.

`Omarchy.ovt` extends the stock Yami theme, so OBS treats it as a variant. In **Settings → Appearance**, the **Theme** list shows `Yami` and the **Variant** list shows `Omarchy`. The **Theme** list has no `Omarchy` entry.

### Following the theme

With both keys set, a running OBS changes colour about a second after `omarchy theme set` or `omarchy font set`, and you don't need to restart it.

### Remove

Close OBS, select `Remove Stow package`, then select `obs-theme`. The removal is blocked while OBS runs, and while `obs-scene` is applied. It deletes `Omarchy.ovt` and, if `user.ini` still selects the Omarchy theme, switches it back to Yami. These things stay:

- `AutoReload=true` in `user.ini`
- the `obs-studio` package
- the rendered `obs-omarchy.ovt` in Omarchy's theme state, until the next `omarchy theme set`
- copied profiles and scene collections, which belong to OBS

## OBS scene

### What it does

The `obs-scene` package links a scene generator, a Lua script for OBS, and two hooks. The hooks render the scene files into `~/.config/obs-studio/omarchy-scene/` for your machine's canvas. They render only after `Install OBS set` has written `geometry.json` there. Until then, they do nothing. Once a set is installed, `Apply Stow packages` renders the scene again, so a package update reaches the collection OBS already holds.

The collection, `Omarchy Scene`, holds eight scenes:

| Scene | Use |
| --- | --- |
| Stream | Your screen at full height, with the Omarchy bar cropped. A stack of boxes sits on the screen's right edge: camera, chat, and the time and date. |
| Full | Your screen at full height. |
| Full cam | Full, plus a boxed camera in the bottom-right corner. Use it for recorded videos. |
| Starting | A card with a countdown. |
| Intro | A card with the episode title. |
| BRB | A "be right back" card. |
| Ending | A "thanks for watching" card. |
| Privacy | A card with a red border. Switch to it by hand before you show something private. |

The bar crop changes the screen's shape, so it rarely fills the canvas exactly. Left-over width becomes side blocks. Left-over height becomes a thin band above and below the screen. The band takes the theme background and carries the screen's edge line. It is thinner than one block, so no blocks fit there. Every card has animated blocks around it.

### Following the theme

With OBS running, `omarchy theme set` and `omarchy font set` update the boxes, the cards, the avatar, the text and the chat within about 2 seconds. OBS reloads the images by itself. The Lua script pushes the new colours and font into the text and the chat.

### Chat

The Chat source starts blank. In OBS, open the Chat source's properties and paste a chat URL:

- Twitch: `https://www.twitch.tv/popout/<channel>/chat`
- YouTube: `https://www.youtube.com/live_chat?is_popout=1&v=<video-id>`. The video id changes with every broadcast.

The generated `chat.css` gives the chat a transparent background, the theme's text colour and the Omarchy font. It hides the header, the input box, hype trains, pinned and paid messages, leaderboards and consent banners. The styling targets the sites' own page markup, so a site redesign can break parts of it.

If the chat shows a cookie or consent prompt, right-click the Chat source, select **Interact**, and answer it once. OBS keeps the answer. YouTube's prompt can only be answered this way.

### Title and countdown

The Intro card shows `~/.config/obs-studio/omarchy-scene/title.txt`. Edit that file, and OBS shows the new title within a second. The hooks create it once and never overwrite it.

The Starting countdown lasts 5 minutes by default. To change it, open **Tools → Scripts**, select `omarchy-scene.lua`, and set **Starting countdown (minutes)** between 1 and 60.

### Camera

The Camera source ships with no device. On each machine, open its properties and select your camera. A background blur from `obs-backgroundremoval` at strength 4 is on by default. The blur uses about 85% of one CPU core. To turn it off, open the Camera source's filters and disable **background blur**.

### Camera-off avatar

When the camera is off, the Stream and Full cam camera boxes show an animated avatar: a hooded figure that nods to a beat, with eyes that glow and blink. The avatar takes its colours from the Omarchy theme.

The avatar is a pixel-art portrait made with [Craiyon](https://www.craiyon.com/). The `obs-scene` package includes it and links it to `~/.config/dotfiles/obs-avatar.jpg`, so applying the package is all you need. The crop and the animation are measured for that one picture. Every `Omarchy Scene` collection expects the six avatar layers, so the hooks refuse any other file: they stop with an error and keep the last render. Removing the package unlinks the portrait.

The avatar shows when you hide the Camera item (the eye icon in the Sources list) or when the camera sends no picture, for example when it is unplugged or busy. It hides when the camera shows a picture. To change the nod speed, open **Tools → Scripts** and set **Avatar nod tempo (BPM)** between 40 and 200. The default is 90.

### Remove

Close OBS, select `Remove Stow package`, then select `obs-scene`. The removal is blocked while OBS runs. It deletes `~/.config/obs-studio/omarchy-scene/`, including `title.txt`, the avatar layers and the geometry file. These things stay:

- the copied `Omarchy Scene` collection. It shows missing images and a missing script until you delete it in OBS.
- any portrait you placed at `~/.config/dotfiles/obs-avatar.jpg` yourself, in place of the linked one
- the `obs-backgroundremoval`, `obs-studio-plugin-browser`, `imagemagick`, `bun` and `obs-studio` packages

## Install OBS set

### Machine sets

Machine sets live in `obs/sets/<set>/`. Each set has an OBS profile named `Twitch` and the `Omarchy Scene` collection for its canvas. Two sets ship:

- `laptop`: a 1920x1080 canvas for a 16:10 laptop panel, with side blocks.
- `pc`: a 2560x1440 canvas, scaled to 1920x1080 output, for a 16:9 monitor, with bands above and below the screen.

Both profiles use Advanced output mode at 60 fps with the VAAPI H.264 encoder. Streaming uses CBR at 6000 kbps with 2-second keyframes. Recording uses CQP 14 in hybrid MP4, saved to `~/Videos/Recordings`. The sets contain no stream key, so enter yours in OBS.

### Install a set

Close OBS, run `make`, and select `Install OBS set`. Guided setup also offers it as phase 9. Select the set for this machine.

The action stops if the `obs` command is missing, and refuses while OBS runs. It installs nothing. Before it copies anything, it encodes one test frame with each profile's encoder on `/dev/dri/renderD128`. It refuses a profile whose encoder fails or is unknown. The plan shows what the action will copy, and nothing changes until you approve it.

The action copies the profile and, if `obs-scene` is applied, the collection:

- It refuses to copy a profile or collection when another one in OBS already has the same name.
- If the profile or collection already exists, the action asks whether to replace it. It backs up the old one to `~/.config/obs-studio/backups/` first.
- It copies through a temporary file, so an interrupted copy leaves nothing behind.
- It fills in your home folder in the recording, image and script paths.

If `obs-scene` is applied, the action also writes the set's `geometry.json` and renders the scene once. If it isn't, the action copies the profile and tells you to apply `obs-scene` and run the action again.

Finally, the action selects the profile, and the collection if it copied one, in `user.ini`. It changes no other keys.

### Delete a copied profile or collection

After the copy, the profile and the collection belong to OBS. The wizard keeps no record of them and has no remove action. To delete them, use **Profile → Remove** and **Scene Collection → Remove** in OBS.

### Add a set

1. Run `bin/dotfiles --action obs-diagnose` on the machine. It prints the monitor's resolution and scale, the screen size, strip width and band height for each canvas, and which VAAPI encoders work.
2. Copy an existing set to `obs/sets/<name>/`. Set the canvas and output size in `profiles/Twitch/basic.ini`, and set `canvas`, `bar_crop`, `strip_width` and `band_height` in `scene/geometry.json`. The report gives the last two.
3. Keep the stream's peak upload at or below 80% of your measured upload speed.
4. Regenerate the collection:

   ```bash
   bun config/obs-scene/.local/libexec/dotfiles/obs-scene/generate.ts collection \
     --geometry obs/sets/<name>/scene/geometry.json --output obs/sets/<name>/scene/Omarchy_Scene.json
   ```

5. Run `bash tests/obs_sets_test.sh`. It checks that the set has no stream key, account data, device paths or home-folder paths, and that the collection matches a fresh generation.
