import QtQuick
import QtQuick.Window
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
// Private Plasma module (ships with plasma-workspace; used by the Media
// Player widget and lock screen). Its API is not guaranteed between Plasma
// releases: if this import fails, TileItemView's Loader logs the error and
// the tile keeps its normal face. Calls into it below are defensive too.
import org.kde.plasma.private.mpris as Mpris

// Live tile: now playing (album art, track, artist) from any MPRIS player.
// Tile fields: liveMediaAppOnly (bool) - only follow the player belonging
// to this tile's app instead of falling back to the active player.
Item {
	id: mediaLiveTile

	//--- Interface read by TileItemView
	// Only flip to the live face while a player is playing or paused.
	readonly property bool liveAvailable: player !== null
		&& (player.playbackStatus === Mpris.PlaybackStatus.Playing
			|| player.playbackStatus === Mpris.PlaybackStatus.Paused)
	readonly property bool fullBleed: hasArt
	readonly property bool hideTileLabel: true

	readonly property string logPrefix: "[tiledmenu:MediaLiveTile " + (appObj.favoriteId || "?") + "]"

	Mpris.Mpris2Model {
		id: mpris
		onCurrentPlayerChanged: mediaLiveTile.updatePlayer("currentPlayerChanged")
		onRowsInserted: mediaLiveTile.updatePlayer("rowsInserted")
		onRowsRemoved: mediaLiveTile.updatePlayer("rowsRemoved")
	}

	// QObject-typed, so it resets to null by itself if the player goes away.
	property QtObject player: null
	property bool apiWarned: false

	readonly property bool appOnly: appObj.liveMediaAppOnly
	onAppOnlyChanged: updatePlayer("appOnlyChanged")
	Connections {
		target: appObj
		function onFavoriteIdChanged() { mediaLiveTile.updatePlayer("favoriteIdChanged") }
	}
	Component.onCompleted: updatePlayer("completed")

	// "org.kde.elisa.desktop", "applications:org.kde.elisa.desktop" or a
	// file path -> launcher URL in the form the task manager passes.
	function launcherUrl() {
		var id = appObj.favoriteId
		if (!id) {
			return ""
		}
		if (id.indexOf("applications:") === 0 || id.indexOf("file://") === 0) {
			return id
		}
		if (id.charAt(0) === "/") {
			return "file://" + id
		}
		return "applications:" + id
	}

	function findAppPlayer() {
		var url = launcherUrl()
		if (!url) {
			return null
		}
		if (typeof mpris.playerForLauncherUrl !== "function") {
			if (!apiWarned) {
				apiWarned = true
				console.warn(logPrefix, "Mpris2Model.playerForLauncherUrl() is missing; the private mpris API has changed. Falling back to the active player.")
			}
			return null
		}
		try {
			return mpris.playerForLauncherUrl(url, 0) || null
		} catch (e) {
			if (!apiWarned) {
				apiWarned = true
				console.warn(logPrefix, "Mpris2Model.playerForLauncherUrl(" + url + ") threw:", String(e), "- falling back to the active player.")
			}
			return null
		}
	}

	function updatePlayer(reason) {
		var found = findAppPlayer()
		var source = found ? "app" : ""
		if (!found && !appOnly) {
			found = mpris.currentPlayer || null
			source = found ? "active" : ""
		}
		if (found && typeof found.playbackStatus === "undefined") {
			console.warn(logPrefix, "Player object has no playbackStatus property; the private mpris API has changed. Live face disabled.")
			found = null
		}
		if (found !== player) {
			logger.debug(logPrefix, "player ->", found ? ((found.identity || "<unnamed player>") + " (" + source + ")") : "none", "reason:", reason, "launcherUrl:", launcherUrl() || "<none>", "appOnly:", appOnly)
			player = found
		}
	}

	onLiveAvailableChanged: logger.debug(logPrefix, "liveAvailable:", liveAvailable, "status:", player ? player.playbackStatus : "<no player>")

	readonly property string track: player ? (player.track || "") : ""
	readonly property string artist: player ? (player.artist || "") : ""
	readonly property string artUrl: player ? (player.artUrl || "") : ""
	readonly property bool paused: player !== null && player.playbackStatus === Mpris.PlaybackStatus.Paused
	readonly property bool hasArt: artUrl !== "" && art.status !== Image.Error
	readonly property bool showText: appObj.tileW >= 2

	//--- Album art (full bleed)
	Image {
		id: art
		anchors.fill: parent
		visible: mediaLiveTile.hasArt
		source: mediaLiveTile.artUrl
		fillMode: Image.PreserveAspectCrop
		asynchronous: true
		smooth: true
		mipmap: true
		sourceSize.width: width * Screen.devicePixelRatio
		sourceSize.height: height * Screen.devicePixelRatio
		onStatusChanged: {
			if (status === Image.Error) {
				console.warn(mediaLiveTile.logPrefix, "Failed to load album art:", source.toString() || "<empty url>")
			}
		}
	}

	// No art: show the player's icon instead.
	Kirigami.Icon {
		visible: !mediaLiveTile.hasArt
		anchors.horizontalCenter: parent.horizontalCenter
		anchors.verticalCenter: parent.verticalCenter
		anchors.verticalCenterOffset: textColumn.visible ? -textColumn.height / 2 : 0
		width: Math.min(parent.width, parent.height - (textColumn.visible ? textColumn.height : 0)) / 2
		height: width
		source: mediaLiveTile.player && mediaLiveTile.player.iconName ? mediaLiveTile.player.iconName : "media-playback-start"
	}

	// Readability scrim under the text when it sits on top of artwork.
	Rectangle {
		visible: mediaLiveTile.hasArt && textColumn.visible
		anchors.left: parent.left
		anchors.right: parent.right
		anchors.bottom: parent.bottom
		height: textColumn.height + tileItemView.tilePadding * 4
		gradient: Gradient {
			GradientStop { position: 0.0; color: "transparent" }
			GradientStop { position: 1.0; color: "#b3000000" }
		}
	}

	Column {
		id: textColumn
		visible: mediaLiveTile.showText && (mediaLiveTile.track !== "" || mediaLiveTile.artist !== "")
		anchors.left: parent.left
		anchors.right: parent.right
		anchors.bottom: parent.bottom
		anchors.margins: tileItemView.tilePadding
		readonly property color textColor: mediaLiveTile.hasArt ? "white" : Kirigami.Theme.textColor

		PlasmaComponents3.Label {
			width: parent.width
			text: mediaLiveTile.track
			visible: text !== ""
			elide: Text.ElideRight
			font.bold: true
			color: textColumn.textColor
			renderType: Text.QtRendering
		}
		PlasmaComponents3.Label {
			width: parent.width
			text: mediaLiveTile.artist
			visible: text !== ""
			elide: Text.ElideRight
			font.pointSize: Kirigami.Theme.smallFont.pointSize
			color: textColumn.textColor
			opacity: 0.8
			renderType: Text.QtRendering
		}
	}

	// Paused badge.
	Rectangle {
		visible: mediaLiveTile.paused
		anchors.top: parent.top
		anchors.right: parent.right
		anchors.margins: tileItemView.tilePadding
		width: Math.max(16, Math.min(parent.width, parent.height) / 5)
		height: width
		radius: width / 2
		color: "#99000000"
		Kirigami.Icon {
			anchors.fill: parent
			anchors.margins: parent.width / 5
			source: "media-playback-pause"
			color: "white"
			isMask: true
		}
	}
}
