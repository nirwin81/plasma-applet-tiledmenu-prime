import QtQuick
import QtCore

QtObject {
	id: appObj

	property var tile: null

	readonly property bool isGroup: tile && tile.tileType == "group"
	readonly property bool isLauncher: !isGroup

	// Group state derived from tile positions. Refreshed imperatively rather than
	// bound: while a drag is in progress TileGrid's group functions leave out the
	// dragged items, and a binding would follow them (collapsing the background of
	// a dragged group). Both keep their value during a drag, and are refreshed
	// when it ends.
	//   groupRect: for a group, the rect of its content area (else null).
	//   inPaintedGroup: with "Extend group background" on, whether this tile is in
	//   a group that paints a background. Such a tile has no color of its own
	//   until one is chosen, so the group shows through.
	property var groupRect: null
	property bool inPaintedGroup: false
	function refreshGroupState() {
		// Not isGroup: that binding may not have caught up with `tile` yet.
		var tileIsGroup = !!tile && tile.tileType == "group"
		groupRect = tileIsGroup ? tileGrid.getGroupAreaRect(tile) : null
		inPaintedGroup = !!tile && !tileIsGroup && config.extendGroupBackground
			&& tileGrid.hasVisibleBackground(tileGrid.getGroupForTile(tile))
	}
	onTileChanged: refreshGroupState()

	readonly property color defaultBackgroundColor: (isGroup || inPaintedGroup) ? "transparent" : config.defaultTileColor
	readonly property bool defaultShowIcon: isGroup ? false : true
	readonly property int defaultTileW: isGroup ? 6 : 2
	readonly property int defaultTileH: isGroup ? 1 : 2

	readonly property string favoriteId: tile && tile.url || ''
	readonly property var app: favoriteId ? appsModel.tileGridModel.getApp(favoriteId) : null
	readonly property string appLabel: app ? app.display : ""
	readonly property string appUrl: app ? app.url : ""
	readonly property var appIcon: app ? app.decoration : null
	readonly property string labelText: tile && tile.label || appLabel || appUrl || ""
	readonly property var iconSource: tile && tile.icon || appIcon
	readonly property bool iconFill: tile && typeof tile.iconFill !== "undefined" ? tile.iconFill : false
	readonly property bool showIcon: tile && typeof tile.showIcon !== "undefined" ? tile.showIcon : defaultShowIcon
	readonly property bool showLabel: tile && typeof tile.showLabel !== "undefined" ? tile.showLabel : true
	readonly property bool hasOwnBackgroundColor: tile && typeof tile.backgroundColor !== "undefined"
	readonly property color backgroundColor: hasOwnBackgroundColor ? tile.backgroundColor : defaultBackgroundColor
	readonly property string backgroundImage: tile && typeof tile.backgroundImage !== "undefined" ? tile.backgroundImage : ""
	readonly property bool backgroundGradient: {
		if (tile && typeof tile.gradient !== "undefined") {
			return tile.gradient
		}
		// A default gradient on a clear tile would paint over the group.
		if (!hasOwnBackgroundColor && (inPaintedGroup || (isGroup && config.extendGroupBackground))) {
			return false
		}
		return config.defaultTileGradient
	}

	// Live tiles: a tile with a known `liveType` shows a dynamic face
	// (live/<Type>LiveTile.qml) on top of / alternating with its normal face.
	// Fields are kept flat on the tile (not a nested object) so the same
	// tileChanged() re-emit used for every other field keeps bindings fresh.
	readonly property var liveTileSources: ({
		"clock": "live/ClockLiveTile.qml",
		"command": "live/CommandLiveTile.qml",
		"slideshow": "live/SlideshowLiveTile.qml",
		"media": "live/MediaLiveTile.qml",
		"notifications": "live/NotificationsLiveTile.qml",
	})
	// Types whose content should fill the tile edge to edge (no padding,
	// label drawn over a scrim).
	readonly property bool liveFullBleed: liveType === "slideshow"
	readonly property string liveType: tile && tile.liveType || ""
	readonly property string liveSource: liveTileSources[liveType] || ""
	readonly property bool isLive: !isGroup && liveSource !== ""
	readonly property bool liveCycle: tile && typeof tile.liveCycle !== "undefined" ? tile.liveCycle : true
	readonly property string liveFormat: tile && tile.liveFormat || ""
	readonly property string liveCommand: tile && typeof tile.liveCommand === "string" ? tile.liveCommand : ""
	readonly property int liveInterval: tile && tile.liveInterval > 0 ? tile.liveInterval : (liveType === "slideshow" ? 10 : 60)
	readonly property string liveFolder: tile && tile.liveFolder || ""
	readonly property bool liveShuffle: tile && tile.liveShuffle || false
	readonly property bool liveRecursive: tile && tile.liveRecursive || false
	readonly property bool liveMediaAppOnly: tile && tile.liveMediaAppOnly || false
	readonly property bool liveNotificationPreview: tile && tile.liveNotificationPreview || false
	// liveFolder as a file:// URL: accepts a plain path, "~/..." or a URL;
	// empty means the user's Pictures folder.
	readonly property string liveFolderUrl: {
		var path = liveFolder
		if (!path) {
			return StandardPaths.writableLocation(StandardPaths.PicturesLocation).toString()
		}
		if (path.indexOf("file://") === 0) {
			return path
		}
		if (path === "~" || path.indexOf("~/") === 0) {
			return StandardPaths.writableLocation(StandardPaths.HomeLocation).toString() + path.substring(1)
		}
		return "file://" + path
	}

	readonly property int tileX:tile && typeof tile.x !== "undefined" ? tile.x : 0
	readonly property int tileY: tile && typeof tile.y !== "undefined" ? tile.y : 0
	readonly property int tileW: tile && typeof tile.w !== "undefined" ? tile.w : defaultTileW
	readonly property int tileH: tile && typeof tile.h !== "undefined" ? tile.h : defaultTileH


	// onTileChanged: console.log('onTileChanged', JSON.stringify(tile))
	// onAppLabelChanged: console.log('onAppLabelChanged', appLabel)

	// Qt >= 6.10 (Plasma 6.8) no longer tracks property changes made on plain
	// JavaScript objects inside QML bindings, so after the tile editor mutates
	// a tile (w/h/x/y, label, icon, background, ...), bindings that read those
	// values don't re-evaluate on their own. Manually re-emit this object's
	// `tile` changed signal so every dependent binding re-reads the tile.
	function updateFromTile() {
		if (tile) {
			tileChanged()
		}
	}

	function hasActionList() {
		return app ? appsModel.tileGridModel.indexHasActionList(app.indexInModel) : false
	}

	function getActionList() {
		return app ? appsModel.tileGridModel.getActionListAtIndex(app.indexInModel) : []
	}

	function addActionList(menu) {
		if (hasActionList()) {
			var actionList = getActionList()
			menu.addActionList(actionList, appsModel.tileGridModel, appObj.app.indexInModel)
		}
	}

	property Connections tileGridConnection: Connections {
		target: tileGrid
		function onTileModelChanged() {
			appObj.refreshGroupState()
		}
		// The edited tile may be this tile's group, gaining or losing a background.
		function onTileEdited() {
			appObj.refreshGroupState()
		}
		// A drop emits tileModelChanged before the drag state is cleared.
		function onDragEnded() {
			appObj.refreshGroupState()
		}
	}
	property Connections configConnection: Connections {
		target: config
		function onExtendGroupBackgroundChanged() {
			appObj.refreshGroupState()
		}
	}
}
