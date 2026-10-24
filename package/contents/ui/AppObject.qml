import QtQuick

QtObject {
	id: appObj

	property var tile: null

	readonly property bool isGroup: tile && tile.tileType == "group"
	readonly property bool isLauncher: !isGroup

	// Tiles inside a group have no color of their own until one is chosen,
	// so the group background shows through instead of the launcher color.
	property bool inGroup: false
	function refreshInGroup() {
		var inside = false
		if (tile && !isGroup && tileGrid) {
			inside = !!tileGrid.getGroupForTile(tile)
		}
		if (inGroup !== inside) {
			inGroup = inside
		}
	}
	onTileChanged: refreshInGroup()
	Component.onCompleted: refreshInGroup()

	readonly property color defaultBackgroundColor: (isGroup || inGroup) ? "transparent" : config.defaultTileColor
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
		if ((isGroup || inGroup) && !hasOwnBackgroundColor) {
			return false
		}
		return config.defaultTileGradient
	}

	readonly property int tileX: tile && typeof tile.x !== "undefined" ? tile.x : 0
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

	readonly property var groupRect: {
		if (isGroup) {
			return tileGrid.getGroupAreaRect(tile)
		} else {
			return null
		}
	}
	property Connections tileGridConnection: Connections {
		target: tileGrid
		function onTileModelChanged() {
			if (appObj.isGroup) {
				appObj.groupRectChanged()
			}
			appObj.refreshInGroup()
		}
	}
}
