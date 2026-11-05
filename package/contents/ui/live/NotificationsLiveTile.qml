import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.notificationmanager as NotificationManager

// Tile fields: liveNotificationPreview (bool) - show summary/body text.
Item {
	id: notificationsLiveTile

	// Interface read by TileItemView
	readonly property bool liveAvailable: canMatch && !blacklisted && count > 0
	readonly property bool hideTileLabel: previewShown

	readonly property string logPrefix: "[tiledmenu:NotificationsLiveTile " + (appObj.favoriteId || "<no app>") + "]"

	// Tile URLs can be "foo.desktop", "applications:foo.desktop" or a path
	// to the .desktop file; the resolved app URL covers aliases like
	// "preferred://browser". Returns the desktop entry without ".desktop".
	function desktopEntryFrom(url) {
		var s = (url || "").toString()
		if (s.indexOf("://") !== -1 && s.indexOf("file://") !== 0) {
			return "" // preferred://browser etc.
		}
		s = s.replace(/^applications:/, "").replace(/^file:\/\//, "")
		s = s.substring(s.lastIndexOf("/") + 1)
		s = s.split("?")[0]
		if (!/\.desktop$/.test(s)) {
			return ""
		}
		return s.replace(/\.desktop$/, "")
	}
	readonly property string desktopEntry: desktopEntryFrom(appObj.appUrl) || desktopEntryFrom(appObj.favoriteId)

	// Apps rarely tag notifications with exactly their installed desktop
	// entry: a snap's launcher is "discord_discord" but Discord (Electron)
	// sends "discord"; others send no desktop entry at all, only an app name
	// like "Whatsie". So match against a few variants of the entry, plus the
	// app's display name. All lower case.
	function appIdsFor(entry) {
		var e = (entry || "").toLowerCase()
		if (!e) {
			return []
		}
		var ids = [e]
		if (e.indexOf(".") === -1 && e.indexOf("_") !== -1) {
			// Snap: <snap>_<app>
			e.split("_").forEach(function(part) { if (part) ids.push(part) })
		}
		var parts = e.split(".")
		if (parts.length >= 3) {
			// Reverse DNS (Flatpak style): com.discordapp.Discord -> discord
			ids.push(parts[parts.length - 1])
		}
		return ids.filter(function(id, i) { return ids.indexOf(id) === i })
	}
	readonly property var appIds: appIdsFor(desktopEntry)
	readonly property string appName: (appObj.appLabel || "").toLowerCase()
	readonly property bool canMatch: appIds.length > 0 || appName !== ""
	onAppIdsChanged: {
		logger.debug(logPrefix, "matching desktop entries:", JSON.stringify(appIds), "app name:", JSON.stringify(appName))
		scheduleRecount()
	}
	onCanMatchChanged: {
		if (!canMatch) {
			console.warn(logPrefix, "Could not work out an app ID or name from tile URL", "\"" + (appObj.favoriteId || "") + "\"", "or app URL", "\"" + (appObj.appUrl || "") + "\"", "- notification count disabled for this tile.")
		}
	}
	Component.onCompleted: {
		if (!canMatch) {
			canMatchChanged()
		}
		scheduleRecount()
	}

	function normalizeEntry(s) {
		return (s || "").toString().toLowerCase().replace(/\.desktop$/, "")
	}
	function matches(n) {
		var entry = normalizeEntry(n.desktopEntry)
		if (entry && appIds.indexOf(entry) !== -1) {
			return true
		}
		var rc = normalizeEntry(n.notifyRcName)
		if (rc && appIds.indexOf(rc) !== -1) {
			return true
		}
		var name = (n.applicationName || "").toLowerCase()
		return name !== "" && (name === appName || appIds.indexOf(name) !== -1)
	}

	// Respect System Settings > Notifications > <app> > "Show in task manager".
	NotificationManager.Settings {
		id: notificationSettings
	}
	readonly property bool blacklisted: {
		var list = notificationSettings.badgeBlacklistedApplications || []
		for (var i = 0; i < appIds.length; i++) {
			if (list.indexOf(appIds[i]) !== -1) {
				return true
			}
		}
		return false
	}
	onBlacklistedChanged: logger.debug(logPrefix, "badge blacklisted in Notification settings:", blacklisted)

	// The shared history (see NotificationHistory.qml), owned by main.qml because
	// this tile can be destroyed and rebuilt at any time.
	readonly property var historyRows: notificationHistoryLoader.item ? notificationHistoryLoader.item.rows : []
	onHistoryRowsChanged: scheduleRecount()
	onAppNameChanged: scheduleRecount()

	property int count: 0
	property var previewItems: [] // newest first: [{summary, body}]
	readonly property int maxPreviewItems: 10
	// Identities already logged, so debug output isn't repeated per recount.
	property var loggedIdentities: ({})

	function scheduleRecount() {
		Qt.callLater(recount)
	}
	function recount() {
		var matched = 0
		var items = []
		for (var i = 0; i < historyRows.length; i++) {
			var n = historyRows[i]
			var isMatch = matches(n)
			// Log how each app identifies itself (never the notification
			// text), to diagnose apps that don't get counted.
			var identity = (isMatch ? "counted" : "not counted") + " desktopEntry: " + JSON.stringify(n.desktopEntry) + " applicationName: " + JSON.stringify(n.applicationName) + " notifyRcName: " + JSON.stringify(n.notifyRcName)
			if (!loggedIdentities[identity]) {
				loggedIdentities[identity] = true
				logger.debug(logPrefix, "notification", identity)
			}
			if (isMatch) {
				matched++
				if (items.length < maxPreviewItems) {
					items.push({ summary: n.summary, body: n.body })
				}
			}
		}
		count = matched
		previewItems = items
	}
	onCountChanged: logger.debug(logPrefix, "count:", count)

	// View
	readonly property bool previewShown: appObj.liveNotificationPreview && appObj.tileW >= 2 && appObj.tileH >= 2
	readonly property string countText: count > 99 ? "99+" : String(count)

	function plainText(s) {
		// Bodies may contain basic markup; show it as plain text.
		return (s || "").replace(/<[^>]*>/g, " ").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, "\"").replace(/&#39;/g, "'").replace(/&amp;/g, "&").replace(/\s+/g, " ").trim()
	}

	// Count only: bell + big number, centered.
	Row {
		visible: !notificationsLiveTile.previewShown
		anchors.centerIn: parent
		spacing: tileItemView.tilePadding
		readonly property real size: Math.min(notificationsLiveTile.width, notificationsLiveTile.height) * 0.45

		Kirigami.Icon {
			visible: appObj.tileW >= 2
			anchors.verticalCenter: parent.verticalCenter
			width: parent.size * 0.7
			height: width
			source: "notifications"
		}
		PlasmaComponents3.Label {
			anchors.verticalCenter: parent.verticalCenter
			text: notificationsLiveTile.countText
			font.pixelSize: parent.size
			font.bold: true
			renderType: Text.QtRendering
		}
	}

	// Preview: small count header, then the latest notifications.
	Row {
		id: previewHeader
		visible: notificationsLiveTile.previewShown
		anchors.top: parent.top
		anchors.left: parent.left
		spacing: tileItemView.tilePadding
		Kirigami.Icon {
			anchors.verticalCenter: parent.verticalCenter
			width: headerLabel.height
			height: width
			source: "notifications"
		}
		PlasmaComponents3.Label {
			id: headerLabel
			text: notificationsLiveTile.countText
			font.bold: true
			renderType: Text.QtRendering
		}
	}

	ListView {
		visible: notificationsLiveTile.previewShown
		anchors.top: previewHeader.bottom
		anchors.topMargin: tileItemView.tilePadding
		anchors.left: parent.left
		anchors.right: parent.right
		anchors.bottom: parent.bottom
		clip: true
		interactive: false
		spacing: tileItemView.tilePadding
		model: notificationsLiveTile.previewShown ? notificationsLiveTile.previewItems : []
		delegate: Column {
			width: ListView.view.width
			PlasmaComponents3.Label {
				width: parent.width
				text: notificationsLiveTile.plainText(modelData.summary)
				visible: text !== ""
				elide: Text.ElideRight
				font.bold: true
				textFormat: Text.PlainText
				renderType: Text.QtRendering
			}
			PlasmaComponents3.Label {
				width: parent.width
				text: notificationsLiveTile.plainText(modelData.body)
				visible: text !== ""
				elide: Text.ElideRight
				maximumLineCount: 2
				wrapMode: Text.Wrap
				font.pointSize: Kirigami.Theme.smallFont.pointSize
				opacity: 0.8
				textFormat: Text.PlainText
				renderType: Text.QtRendering
			}
		}
	}
}
