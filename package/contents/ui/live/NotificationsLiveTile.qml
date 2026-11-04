import QtQuick
import QtQml
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
	Component.onCompleted: if (!canMatch) canMatchChanged()

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

	// IMPORTANT: creating a Notifications model makes the library register
	// as the desktop's notification server (org.freedesktop.Notifications)
	// if nobody has yet. That's the system tray Notifications widget's job:
	// if we did it, a user without that widget (or with another daemon)
	// would silently lose their notifications. So the model only exists
	// once the server is already running in this process.
	Loader {
		id: modelLoader
		active: notificationsLiveTile.serverValid && notificationsLiveTile.canMatch
		// Unfiltered (the library can only filter on an exact desktop
		// entry); matching happens per row below.
		sourceComponent: NotificationManager.Notifications {
			showNotifications: true
			showJobs: false
			showExpired: true // popups that timed out are still in the history
			showDismissed: false
			showAddedDuringInhibition: true
			groupMode: NotificationManager.Notifications.GroupDisabled
			sortMode: NotificationManager.Notifications.SortByDate
			sortOrder: Qt.DescendingOrder
			urgencies: NotificationManager.Notifications.LowUrgency
				| NotificationManager.Notifications.NormalUrgency
				| NotificationManager.Notifications.CriticalUrgency
		}
		onStatusChanged: {
			if (status === Loader.Error) {
				console.warn(notificationsLiveTile.logPrefix, "Failed to create the Notifications model; the notificationmanager API may have changed. Notification count disabled.")
			}
		}
	}
	readonly property var notificationsModel: modelLoader.status === Loader.Ready ? modelLoader.item : null

	// One lightweight object per notification in the history, so the row's
	// identity and text can be read and re-checked when it changes.
	Instantiator {
		id: rows
		model: notificationsLiveTile.notificationsModel
		delegate: QtObject {
			readonly property string desktopEntry: model.desktopEntry || ""
			readonly property string applicationName: model.applicationName || ""
			readonly property string notifyRcName: typeof model.notifyRcName === "string" ? model.notifyRcName : ""
			readonly property string summary: model.summary || ""
			readonly property string body: model.body || ""
			onDesktopEntryChanged: notificationsLiveTile.scheduleRecount()
			onApplicationNameChanged: notificationsLiveTile.scheduleRecount()
			onSummaryChanged: notificationsLiveTile.scheduleRecount()
			onBodyChanged: notificationsLiveTile.scheduleRecount()
		}
		onObjectAdded: notificationsLiveTile.scheduleRecount()
		onObjectRemoved: notificationsLiveTile.scheduleRecount()
	}
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
		for (var i = 0; i < rows.count; i++) {
			var n = rows.objectAt(i)
			if (!n) {
				continue
			}
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
		if (rows.count !== lastLoggedRowCount) {
			lastLoggedRowCount = rows.count
			logger.debug(logPrefix, "notification history now has", rows.count, "notification(s),", matched, "counted for this tile")
		}
		count = matched
		previewItems = items
	}
	property int lastLoggedRowCount: -1
	onCountChanged: logger.debug(logPrefix, "count:", count)

	// Notification server health
	// The server runs inside plasmashell once the Notifications widget (system
	// tray) starts it. Without it the history is empty and the count stays 0.
	readonly property bool serverValid: NotificationManager.Server.valid
	onServerValidChanged: logger.debug(logPrefix, "notification server valid:", serverValid)
	function serverOwnerText() {
		var owner = NotificationManager.Server.currentOwner
		var text = owner ? [owner.vendor, owner.name, owner.version].filter(function(v) { return !!v }).join(" ") : ""
		return text || "<none>"
	}
	Timer {
		// Give the system tray time to start the server before complaining.
		interval: 10000
		running: !notificationsLiveTile.serverValid
		onTriggered: {
			var process = Qt.application.name || "<unknown>"
			if (process !== "plasmashell") {
				console.warn(notificationsLiveTile.logPrefix, "Running in", "\"" + process + "\",", "not plasmashell. Plasma's notification history only exists inside plasmashell (current owner of the notification service:", notificationsLiveTile.serverOwnerText() + "),", "so the notification count stays at 0 here. Test this tile in the real panel instead.")
			} else {
				console.warn(notificationsLiveTile.logPrefix, "Plasma's notification server is not running in plasmashell (current owner of the notification service:", notificationsLiveTile.serverOwnerText() + ").", "Is the Notifications widget in the system tray? This tile won't start the server itself; counts stay at 0 until it is running.")
			}
		}
	}

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
