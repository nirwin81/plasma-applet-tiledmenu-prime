.pragma library

// Safety checks for live "command" tiles in imported layouts.
//
// A layout's tileModel can carry `liveCommand` entries that are run as shell
// commands whenever the menu is open, so importing someone else's layout can
// execute arbitrary code. The import page uses these helpers to find commands
// that aren't already in the user's own layout, warn about them, and strip
// any command that invokes `rm`.
//
// NOTE: the `rm` check is a blocklist, not a sandbox. It catches `rm`
// written as a command word (`rm -rf x`, `sudo rm`, `/bin/rm`, `a; rm b`,
// `$(rm x)`), but a deliberately obfuscated command can get past it, which
// is why every new command is still shown to the user for approval.

// `rm` preceded by start/whitespace/shell operator/path separator/quote/
// backslash, and followed by end/whitespace/shell operator/quote.
var rmPattern = /(^|[\s;&|()`'"\/\\{}!$])rm(?=$|[\s;&|()`'"{}<>])/

function isRmCommand(command) {
	return typeof command === "string" && rmPattern.test(command)
}

function commandsIn(tileModel) {
	var result = []
	if (!Array.isArray(tileModel)) {
		return result
	}
	for (var i = 0; i < tileModel.length; i++) {
		var tile = tileModel[i]
		if (tile && typeof tile.liveCommand === "string" && tile.liveCommand.trim() !== "") {
			result.push(tile.liveCommand)
		}
	}
	return result
}

// Returns { rm: [commands], unknown: [commands] } for an incoming tileModel.
// `unknown` = non-rm commands not present in the current (trusted) layout.
function analyze(newTileModel, currentTileModel) {
	var trusted = commandsIn(currentTileModel)
	var rm = []
	var unknown = []
	var incoming = commandsIn(newTileModel)
	for (var i = 0; i < incoming.length; i++) {
		var cmd = incoming[i]
		if (isRmCommand(cmd)) {
			rm.push(cmd)
		} else if (trusted.indexOf(cmd) === -1) {
			unknown.push(cmd)
		}
	}
	return { rm: rm, unknown: unknown }
}

function needsReview(report) {
	return report.rm.length > 0 || report.unknown.length > 0
}

function removeCommandFromTile(tile) {
	delete tile.liveCommand
	delete tile.liveInterval
	if (tile.liveType === "command") {
		delete tile.liveType
		delete tile.liveCycle
	}
}

// Mutates and returns newTileModel. Always strips rm commands; when
// `removeUnknown` is true also strips commands not in currentTileModel.
function sanitize(newTileModel, currentTileModel, removeUnknown) {
	if (!Array.isArray(newTileModel)) {
		return newTileModel
	}
	var trusted = commandsIn(currentTileModel)
	for (var i = 0; i < newTileModel.length; i++) {
		var tile = newTileModel[i]
		if (!tile || typeof tile.liveCommand !== "string") {
			continue
		}
		var cmd = tile.liveCommand
		if (isRmCommand(cmd) || (removeUnknown && trusted.indexOf(cmd) === -1)) {
			removeCommandFromTile(tile)
		}
	}
	return newTileModel
}
