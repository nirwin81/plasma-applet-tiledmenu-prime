.pragma library

// Safety checks for live "command" tiles in imported layouts.
//
// A layout's tileModel can carry `liveCommand` entries that are run as shell
// commands whenever the menu is open, so importing someone else's layout can
// execute arbitrary code. The import page uses these helpers to find commands
// that aren't already in the user's own layout, warn about them, and strip
// any command that matches the blocklist.
//
// NOTE: this is a blocklist, not a sandbox. It catches the usual ways of
// writing a dangerous command (`a; rm b`, `sudo x`, `/bin/shred`, `$(rm x)`,
// `r''m x`), but a deliberately obfuscated command can get past it, which is
// why every new command is still shown to the user for approval.
//
// It deliberately errs towards blocking: a false positive only removes a
// command that the import dialog lists as removed.

var wordEnd = "(?=$|[\\s;&|()`'\"{}<>])"

// A position where the shell would run the next word as a command: the start
// of the text, after a shell operator or opening quote, or after a keyword or
// wrapper that runs its argument. Allows `VAR=x` prefixes, wrapper options
// (`nice -n 5`) and a leading path (`/bin/`).
var commandStart = "(?:^|[\\n;&|(){}`!'\"]"
	+ "|(?:^|\\s)(?:then|do|else|elif|if|while|until|exec|command|builtin|env|nohup|nice|time|timeout|xargs|busybox|-exec|-execdir)\\s+(?:(?:-\\S+|\\d\\S*)\\s+)*)"
	+ "\\s*(?:\\w+=\\S*\\s+)*(?:\\S*\\/)?"

var shells = "(?:ba|da|z|k|c|tc|fi|a)?sh"
var interpreters = "(?:python[\\d.]*|perl|ruby|php|node|lua)"

var persistencePaths = "\\S*(?:\\.bashrc|\\.bash_profile|\\.bash_login|\\.profile|\\.zshrc|\\.zprofile|\\.zshenv|\\.ssh\\/|\\.config\\/autostart|\\.config\\/systemd|\\.config\\/plasma-workspace)"

function commandNamed(names) {
	return new RegExp(commandStart + "(?:" + names.join("|") + ")" + wordEnd)
}

// Always stripped on import, whichever option the user picks.
var blockedPatterns = [
	// `rm` anywhere as a word, even as an argument (`xargs rm`, `echo rm`).
	/(^|[\s;&|()`'"\/\\{}!$])rm(?=$|[\s;&|()`'"{}<>])/,

	commandNamed([
		// Runs text as code.
		"eval", "source", "\\.",
		// Wipes disks.
		"dd", "mkfs(?:\\.\\w+)?", "wipefs", "fdisk", "parted", "sfdisk", "sgdisk", "blkdiscard",
		// Destroys files.
		"shred", "unlink", "truncate",
		// Escalates privileges. A password prompt appearing when the menu
		// opens would also be an easy phishing trick.
		"sudo", "doas", "su", "pkexec",
		// Disrupts the session.
		"shutdown", "reboot", "poweroff", "halt", "pkill", "killall",
	]),

	// Download or decode, then run.
	new RegExp("\\|&?\\s*(?:\\S*\\/)?(?:env\\s+)?" + shells + wordEnd), // curl x | sh
	new RegExp("\\|&?\\s*(?:\\S*\\/)?(?:env\\s+)?" + interpreters + "\\s*(?:-\\s*)?(?=$|[;&|)'\"`])"), // curl x | python3
	new RegExp("(?:^|[\\s;&|(\\/])" + shells + "\\s*<"), // bash <(curl x), sh <<< "$x"
	new RegExp("(?:^|[\\s;&|(\\/])" + shells + "\\s+-\\w*c\\s+['\"]?(?:\\$\\(|`)"), // sh -c "$(curl x)"
	/(?:\$\(|`)[^)`]*\bbase64\s+(?:-\w*d|--decode)/, // $(echo x | base64 -d)

	// Wipes disks through a redirect.
	/>>?\s*["']?\/dev\/(?:sd|hd|vd|xvd|nvme|mmcblk|dm-|mapper\/|disk\/)/,

	// Destroys files.
	/\bfind\s[^;|&\n]*\s-delete(?=$|[\s;&|)'"`])/,
	/\bgit\s+(?:-C\s+\S+\s+)?clean(?=$|[\s;&|)'"`])/,
	/\brsync\s[^;|&\n]*\s--delete/,

	// Survives a reboot, or stops the machine.
	/\bsystemctl\s(?:[^;|&\n]*\s)?(?:enable|link|halt|kexec)(?=$|[\s;&|)'"`])/,
	new RegExp(commandStart + "crontab(?!\\s+-l" + wordEnd + ")" + wordEnd), // `crontab -l` only reads
	new RegExp(">>?\\s*[\"']?" + persistencePaths),
	new RegExp("(?:^|[\\s;&|(])(?:tee|cp|mv|ln|install|sed\\s+-\\w*i\\S*)\\s[^;|&\\n]*" + persistencePaths),

	// Fork bomb, e.g. :(){ :|:& };:
	/(\S+)\s*\(\)\s*\{\s*\1\s*\|\s*\1/,
]

// Legitimate often enough that we only warn. The user still decides, so these
// are new commands that get a stronger warning in the dialog.
var cautionPatterns = [
	// Inline scripts can do anything without naming a command we'd recognise.
	new RegExp("(?:^|[\\s;&|(\\/'\"])" + interpreters + "\\s+(?:-\\S+\\s+)*-\\w*[cer](?=$|[\\s'\"])"),
	// Overwrites files.
	commandNamed(["mv", "tee"]),
	// Any redirect to a file. Discarding output (`2>/dev/null`) or merging
	// streams (`2>&1`) is fine.
	/>>?(?!\s*(?:[>&]|\/dev\/null\b))/,
]

// Also check with quotes and backslashes removed, so `r''m` and `r\m` are seen
// the way the shell will see them. The original text is checked as well
// because removing quotes can hide a command start (`sh -c 'dd x'`).
function matchesAny(patterns, command) {
	var normalized = command.replace(/['"\\]/g, "")
	for (var i = 0; i < patterns.length; i++) {
		if (patterns[i].test(command) || patterns[i].test(normalized)) {
			return true
		}
	}
	return false
}

// Too long for anyone to review in the dialog, and a hostile command this long
// could otherwise stall the patterns above and freeze the config dialog.
var maxCommandLength = 1024

// A non-string `liveCommand` can't be inspected, so it's treated as dangerous
// rather than ignored.
function isBlockedCommand(command) {
	return typeof command !== "string"
		|| command.length > maxCommandLength
		|| matchesAny(blockedPatterns, command)
}

function isCautionCommand(command) {
	return typeof command === "string" && matchesAny(cautionPatterns, command)
}

// A non-array tileModel can't be checked tile by tile, but could still be
// rendered: a Repeater treats a plain object as a one item model.
function isValidTileModel(tileModel) {
	return typeof tileModel === "undefined" || Array.isArray(tileModel)
}

function hasCommand(tile) {
	if (!tile || typeof tile !== "object" || typeof tile.liveCommand === "undefined") {
		return false
	}
	return typeof tile.liveCommand !== "string" || tile.liveCommand.trim() !== ""
}

function commandsIn(tileModel) {
	var result = []
	if (!Array.isArray(tileModel)) {
		return result
	}
	for (var i = 0; i < tileModel.length; i++) {
		if (hasCommand(tileModel[i])) {
			result.push(tileModel[i].liveCommand)
		}
	}
	return result
}

function displayText(command) {
	return typeof command === "string" ? command : JSON.stringify(command)
}

// Returns { blocked: [text], caution: [text], unknown: [text] } for an incoming
// tileModel. `caution` and `unknown` only hold commands that aren't blocked and
// aren't present in the current (trusted) layout.
function analyze(newTileModel, currentTileModel) {
	var trusted = commandsIn(currentTileModel)
	var blocked = []
	var caution = []
	var unknown = []
	var incoming = commandsIn(newTileModel)
	for (var i = 0; i < incoming.length; i++) {
		var cmd = incoming[i]
		if (isBlockedCommand(cmd)) {
			blocked.push(displayText(cmd))
		} else if (trusted.indexOf(cmd) === -1) {
			if (isCautionCommand(cmd)) {
				caution.push(cmd)
			} else {
				unknown.push(cmd)
			}
		}
	}
	return { blocked: blocked, caution: caution, unknown: unknown }
}

function needsReview(report) {
	return report.blocked.length > 0 || report.caution.length > 0 || report.unknown.length > 0
}

function removeCommandFromTile(tile) {
	delete tile.liveCommand
	delete tile.liveInterval
	if (tile.liveType === "command") {
		delete tile.liveType
		delete tile.liveCycle
	}
}

// Mutates and returns newTileModel. Always strips blocked commands; when
// `removeUnknown` is true also strips commands not in currentTileModel.
function sanitize(newTileModel, currentTileModel, removeUnknown) {
	if (!Array.isArray(newTileModel)) {
		return newTileModel
	}
	var trusted = commandsIn(currentTileModel)
	for (var i = 0; i < newTileModel.length; i++) {
		var tile = newTileModel[i]
		if (!tile || typeof tile !== "object" || typeof tile.liveCommand === "undefined") {
			continue
		}
		var cmd = tile.liveCommand
		if (isBlockedCommand(cmd) || (removeUnknown && trusted.indexOf(cmd) === -1)) {
			removeCommandFromTile(tile)
		}
	}
	return newTileModel
}
