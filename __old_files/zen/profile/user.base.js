// Zen profile preferences safe for dotfiles.
// Keep personal, sync, session, cookie, history, path, extension, telemetry,
// profile ID, generated migration, and timestamp state out of this file.

// Custom stylesheets.
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);

// Accessibility and navigation.
user_pref("accessibility.typeaheadfind.flashBar", 0);
user_pref("general.autoScroll", true);

// Bookmarks UI only. This does not include bookmark contents.
user_pref("browser.bookmarks.restore_default_bookmarks", false);
user_pref("browser.bookmarks.showMobileBookmarks", false);
user_pref("browser.toolbars.bookmarks.visibility", "never");

// Browser privacy and form behavior.
user_pref("browser.contentblocking.category", "standard");
user_pref("dom.forms.autocomplete.formautofill", true);
user_pref("privacy.clearOnShutdown_v2.formdata", true);
user_pref("privacy.userContext.enabled", false);

// Downloads. Keep paths such as browser.download.lastDir out of dotfiles.
user_pref("browser.download.useDownloadDir", false);

// New tab and URL bar behavior. Keep pinned sites and search history out.
user_pref("browser.newtabpage.activity-stream.feeds.topsites", true);
user_pref("browser.newtabpage.activity-stream.system.showWeatherOptIn", false);
user_pref("browser.tabs.warnOnClose", true);
user_pref("browser.urlbar.maxRichResults", 7);

// Fonts.
user_pref("font.default.x-western", "sans-serif");
user_pref("font.name.monospace.x-western", "FiraCode Nerd Font Mono");
user_pref("font.name.sans-serif.x-western", "FiraCode Nerd Font");
user_pref("font.name.serif.x-western", "FiraCode Nerd Font");
user_pref("font.size.monospace.x-western", 14);
user_pref("font.size.variable.x-western", 14);

// Developer tools layout only.
user_pref("devtools.inspector.activeSidebar", "computedview");
user_pref("devtools.inspector.selectedSidebar", "computedview");
user_pref("devtools.toolsidebar-height.inspector", 350);
user_pref("devtools.toolsidebar-width.inspector", 700);
user_pref("devtools.toolsidebar-width.inspector.splitsidebar", 350);

// Zen appearance.
user_pref("browser.preferences.experimental.hidden", true);
user_pref("browser.theme.toolbar-theme", 0);
user_pref("zen.theme.content-element-separation", 8);
user_pref("zen.theme.gradient", true);
user_pref("zen.theme.gradient.show-custom-colors", true);
user_pref("zen.view.grey-out-inactive-windows", false);

// Zen layout and behavior.
user_pref("sidebar.visibility", "hide-sidebar");
user_pref("zen.view.compact.enable-at-startup", false);
user_pref("zen.view.compact.toolbar-flash-popup", true);
user_pref("zen.view.use-single-toolbar", false);
user_pref("zen.workspaces.continue-where-left-off", true);
