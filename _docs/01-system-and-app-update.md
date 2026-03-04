# System and App Updates

Starting point for keeping the system, apps, and firmware up to date.

Refresh native package metadata.
```bash
sudo dnf makecache --refresh
```

Update native packages.
```bash
sudo dnf upgrade
```

Update Flathub packages.
```bash
flatpak update
```

Update device firmware.
```bash
fwupdmgr refresh && fwupdmgr update
```

Remove unused native packages.
```bash
sudo dnf autoremove
```

Remove unused Flatpak runtimes.
```bash
flatpak uninstall --unused
```

Clean native package caches.
```bash
sudo dnf clean all
```

## COSMIC Theme (EverForest Dark Hard)

Theme source (download "EverForest"):
- https://cosmic-themes.org/?search=everforest&sort=popular&color=%23000000

Apply via GUI (upload a theme file).
1. Open COSMIC Settings.
2. Go to Appearance -> Themes.
3. Select the import or upload option.
4. Choose the EverForest (dark hard) theme file.
5. Apply the theme and confirm it is active.
