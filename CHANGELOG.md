# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.2.0] - 2026-09-17
### Added
- A panel replaces the menu on a left click of the status item: a search field over every host, favourites for the ones buried in a submenu, submenu browsing, and the command line of each entry shown under its name. Keyboard: the search field takes focus on opening, ↑/↓ move the selection, ↩ runs it, ← leaves a submenu. Shuttle's own commands moved to the gear menu in the panel's header.
- Right-clicking (or ⌃-clicking) the status item still shows the classic menu, unchanged.
- ⌘⌥↑ and ⌘⌥↓ move the selected entry in the editor's source list, next to the existing **Move Up** and **Move Down** commands.

### Changed
- The editor window follows the macOS 27 idiom: a header on each page with a tinted symbol and a one-line description, matching badges in the source list, **Save** as a prominent Liquid Glass button, and a Liquid Glass button in the About window.
- The source list shows a hint instead of an empty area when no host is defined yet.
- The panel renders the menu Shuttle already builds, keeping each entry's own action, so themes, `inTerminal`, `open_in`, the alternate JSON file and the hosts merged in from `~/.ssh/config` all behave exactly as before.

### Fixed
- Clicking a host or a submenu in the editor's source list selects it again, and the selected row is highlighted. Making the rows reorderable had turned them into drag sources, which stopped the list from turning a click into a selection and from drawing the selection itself.
- The symbols in the source list badges are no longer cramped against the edge of their badge: they are drawn to a box that is a fixed share of the badge instead of being set in a point size calibrated for the larger one.
- The badge colour of a command is darker, so the white symbol inside it stays readable.

## [2.1.1] - 2026-09-17
### Changed
- Menus follow the order of the entries in the configuration file instead of being sorted alphabetically, and the editor's source list reorders them by drag and drop. Dropping a row just under an open group files it in that submenu; **Move Up**, **Move Down** and **Move to** are in the contextual menu, and **Sort by name** commands restore an alphabetical order for one submenu or for the whole menu.
- The `[abc]` sort prefix is retired: it is still stripped from titles read from the file, including by the menu builder, but the editor no longer offers it and drops it when saving. The `[---]` separator marker is unchanged.
- Two entries can share a name in the same menu; both now appear. The menu builder used to key its items by title, so one of them was silently dropped. The warning about duplicate names is gone with it.
- Hosts read from `~/.ssh/config` are appended in alphabetical order, since the config file gives them no order of their own.
- The About window has been rebuilt: the copyright notice is laid out on one line per holder instead of being clipped to a single truncated line, and the window now shows the app icon, name, tagline, version and a link to the project page. It replaces a fixed 460×172 xib.

### Fixed
- Right-clicking a host inside a group in the editor acted on the whole group: **Delete** removed the group and everything in it. The contextual menu was attached to the disclosure group, which also covers its child rows. Every entry is now a row of its own and its menu acts on the entry under the pointer.

## [2.1.0] - 2026-09-16
### Added
- A configuration editor window, replacing hand-editing of `~/.shuttle.json` for everyday changes. Open it from **Settings > Edit** in the menu. It covers both the global settings (terminal, iTerm version, default theme, default window mode, editor, launch at login, SSH config hosts and the ignore lists) and the whole `hosts` tree, with commands and groups added, duplicated, moved between groups and deleted from a source list.
- The `[abc]` sort prefix and the `[---]` separator marker are now edited as a "Force a position in the menu" field and an "Add a separator after this entry" checkbox, so the bracket syntax never has to be typed by hand.
- Non-blocking warnings for configurations Shuttle would silently ignore: two entries sharing a name in the same menu (only one of them ever reaches the menu), entries with no name, commands with no command line, empty groups and malformed sort keys. Selecting a warning jumps to the entry.
- French translation of the whole editor.
- **Settings > Edit as Text…** keeps the previous behaviour of opening the raw JSON, still honouring the `editor` key.

### Changed
- Saving from the editor preserves the `_comments` block and any key Shuttle does not know about, at the top level as well as inside a command, so hand-written configurations survive a round trip. Unknown per-command keys are listed read-only under "Other Keys".
- The editor writes atomically, detects when another app changed the file while the window was open, and offers to overwrite or reload rather than silently clobbering it.
- Swift is now enabled on the target (Swift 6, main-actor-by-default isolation), with the Swift optimization level set per configuration.

## [2.0.0] - 2026-09-16
### Changed
- Minimum supported system is now macOS 27 (Golden Gate); the deployment target moved from 10.9 to 27.0.
- Launch at login is now driven by `SMAppService` instead of the long-deprecated `LSSharedFileList` API, which no longer has any effect on current systems. The login item appears in System Settings > General > Login Items.
- Replaced AppKit APIs and constants removed or deprecated since 10.9: `NSOKButton`/`NSFileHandlingPanelOKButton` become `NSModalResponseOK`, `NSWarningAlertStyle` becomes `NSAlertStyleWarning`, `-[NSWorkspace openFile:]` becomes `-openURL:`, and the status item image and highlight are set through its `button` rather than the deprecated `NSStatusItem` accessors.
- Project format upgraded to Xcode 27 and the `ServiceManagement` framework is now linked.

### Fixed
- ssh commands no longer fail with "Unable to open the application: -50". `-[NSURL URLWithString:]` alone was used to decide whether a command was a URL, and on macOS 26/27 it also succeeds for plain shell commands by percent-escaping them into a relative URL with no scheme. Commands are now only handed to NSWorkspace when they really are openable URLs.

### Added
- The ability to open multiple, or same command(s) off one menu item. https://github.com/fitztrev/shuttle/issues/236
- The ability to add a second json.config file 
- The ability to add ```[---]``` in the name of a command to add a line seperator 
- Adding a new apple script which will allow running commands in the background with screen
- @philippetev Changes to iTerm applescripts to fix issues with settings in iTerm's Preferences/General
- French translations by @anivon
- @anivon localize Error parsing config message is JSON is invalid 
- @blackadmin version typos in about window. 
- @ChrisMoriarty add the ability to set the terminal window position and size

## [1.2.9] - 2016-10-18
### Added
- @pluwen added Chinese language translations #185

### Changed 
- All the documentation has been moved out of the readme.md and placed in the wiki.

### Fixed 
- Corrected by @pluwen icon changes changes #184
- Corrected by @bihicheng config file edits not working #199

## [1.2.8] - 2016-10-18
### Added
- Menus have been translated to Spanish
- Added a bash script to the default JSON file that allows writing a command to terminal without execution #200

### Fixed
- Fixed an issue that prevented character escapes #194
- Fixed an issue that prevented tabs from opening in terminal on macOS #198
- Fixed an issue where english was not the default language.

## [1.2.7] - 2016-07-24
### Added
- Now that iTerm stable is at version 3, the version 2 applescripts no longer apply to the stable branch. shuttle still supports iTerm 2.14. If you still want to use this legacy version you will have to change your iTerm_version setting to legacy. Valid settings are:

```"iTerm_version": "legacy",``` targeting iTerm 2.14

```"iTerm_version": "stable",``` targeting new versions of iTerm

```"iTerm_version": "nightly",``` targeting only the nightly build of iTerm

Please make sure to change your shuttle.JSON file accordingly. For more on this see #181

### Fixed 
- corrected by @mortonfox -- when iTerm startup preferences are set to "Don't Open Any Windows" nothing happens #175.
- corrected by @pluwen shuttle icon contains unwanted artifacts #141
- Fixed an issue where commas were not getting parsed #173

## [1.2.6] - 2016-02-24
### Added
- added by @keesfransen -- ssh config file parsing only keeps the first alias. This change keeps the menu clean as it only keeps the first argument to Host and will allow for hosts defined like:
```
Host prod/host host.prod
    HostName myserver.local
```
- Added the script files that compile the applescript files for inclusion in shuttle.app

### Fixed 
- corrected by @mortonfox -- when iTerm stable is running but no windows are open nothing happens.
- iTerm Stable and Terminal apple scripts were not correctly handling events where the app was open but no windows were open.
- Fixed an issue were iTerm Nightly applescripts would not open if a theme was not set.
- Fixed an issue with the URL detection. shuttle checks the command to see if its a URL then opens that URL in the default app.
Example:
```
"cmd": "cifs://myServer/c$"
```
Should open the above path in finder.

## [1.2.5] - 2015-11-05
### Added
- Added a new feature ```"open_in": "VALUE"``` is a global setting which sets how commands are open. Do they open in new tabs or new windows? This setting accepts the value of ```"tab"``` or ```"new"```
- Added a new feature ```"default_theme": "VALUE"``` is a global setting which sets the default theme for all terminal windows.
- Cleaned up the default JSON file and changed the names to reflect the action.
- Added alert boxes on errors for ```"iTerm_version": "VALUE"``` and ```"inTerminal": "VALUE"```

### Changed
- Changed the readme.md to reflect all options. Please see the new wiki it explains all of the settings.

## [1.2.4] - 2015-10-17
### Added
- If ```"title":"Terminal Title"``` is empty then the title becomes the same as the commands menu name.

### Fixed
- Fixed the icon it was not turning white.
- Fixed iTerm2 variable
- About window on top changes

## [1.2.3] - 2015-10-15
### Added
- Applescript Changes allow for iTerm Stable and Nightly support. Note that this only works with Nightly versions starting after 2.9.20150414
- Open a Command in a new window. In your JSON for the command add this directive:
```"inTerminal": "new",```
- Open a Command in the existing window. In your JSON for the command add this directive:
```"inTerminal": "current",```
- Add a Title to your window: In your JSON for the command add this directive:
```"title": "Dev Server - SSH"```
- Add a Theme to your window: In your JSON for the command add this directive:
```"theme": "Homebrew",```
- Change the Path to the JSON file. In your home directory create a file called ```~/.shuttle.path``` In this file is the path to the JSON settings. Mine currently reads ```/Users/thshdw/Desktop/shuttle.json```
- Change the default editor. In the JSON settings change ```“editor”: “default”``` will open the settings file from the Settings > edit menu in that editor. Set the editor to 'nano', 'vi', or any terminal based editor.
- Shuttle About Opens a GUI window that shows the version with a button to the home page.

## [1.2.2] - 2014-11-01
### Added
- Adds support for dark mode in Yosemite

## [1.2.0] - 2013-12-02
### Added
- Include option to show/hide servers from SSH config files
- Include option to ignore hosts based on name or keyword
- Ability to Import/Export settings file
- Support for multiple nested menus

### Fixed
- Remove status icon from status bar on quit

## [1.1.2] - 2013-07-23
### Fixed
- Fix issue with parsing the default JSON config file

## [1.1.1] - 2013-07-19
### Added
- cmd in .shuttle.json now supports URLs (http://, smb://, vnc://, etc.)
Opens in your OS default applications
- Added test configuration files

### Changed
- Create default config file on application load, instead of menu open

### Fixed
- Fix issue with iTerm running command in the previous tab's split, instead of the new tab.
- Escape double quote characters in cmd

## [1.1.0] - 2013-07-16
### Added
- Option to automatically launch at login
- In addition to the JSON config, also generate menu items from hosts in .ssh/config

## [1.0.1] - 2013-07-11
### Added
- OS X 10.7 support
- Change menu bar item to use an icon instead of "SSH".

## [1.0.0] - 2013-07-10
### Added
- Initial Release
