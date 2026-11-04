import QtQuick
import QtQml
import org.kde.notificationmanager as NotificationManager

// The notification history shared by every notification live tile. Loaded once
// by main.qml, so it outlives the tiles.
//
// IMPORTANT: this must not live inside a tile. Tiles are destroyed and rebuilt
// whenever the tile grid refreshes (e.g. while using the tile editor), and a
// newly created Notifications model doesn't list notifications that arrived
// before it existed, so a rebuilt tile would lose its count.
Item {
	id: notificationHistory

	readonly property string logPrefix: "[tiledmenu:NotificationHistory]"

	// Newest first: [{desktopEntry, applicationName, notifyRcName, summary, body}].
	// Replaced (never mutated) on every change, so bindings on it update.
	property var rows: []

	// IMPORTANT: creating a Notifications model makes the library register
	// as the desktop's notification server (org.freedesktop.Notifications)
	// if nobody has yet. That's the system tray Notifications widget's job:
	// if we did it, a user without that widget (or with another daemon)
	// would silently lose their notifications. So the model only exists
	// once the server is already running in this process.
	Loader {
		id: modelLoader
		active: notificationHistory.serverValid
		// Unfiltered (the library can only filter on an exact desktop
		// entry); each tile picks out its own rows.
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
				console.warn(notificationHistory.logPrefix, "Failed to create the Notifications model; the notificationmanager API may have changed. Notification count disabled.")
			}
		}
	}

	// One lightweight object per notification in the history, so the row's
	// identity and text can be read and re-checked when it changes.
	Instantiator {
		id: rowObjects
		model: modelLoader.status === Loader.Ready ? modelLoader.item : null
		delegate: QtObject {
			readonly property string desktopEntry: model.desktopEntry || ""
			readonly property string applicationName: model.applicationName || ""
			readonly property string notifyRcName: typeof model.notifyRcName === "string" ? model.notifyRcName : ""
			readonly property string summary: model.summary || ""
			readonly property string body: model.body || ""
			onDesktopEntryChanged: notificationHistory.scheduleUpdate()
			onApplicationNameChanged: notificationHistory.scheduleUpdate()
			onNotifyRcNameChanged: notificationHistory.scheduleUpdate()
			onSummaryChanged: notificationHistory.scheduleUpdate()
			onBodyChanged: notificationHistory.scheduleUpdate()
		}
		onObjectAdded: notificationHistory.scheduleUpdate()
		onObjectRemoved: notificationHistory.scheduleUpdate()
	}

	function scheduleUpdate() {
		Qt.callLater(update)
	}
	function update() {
		var result = []
		for (var i = 0; i < rowObjects.count; i++) {
			var row = rowObjects.objectAt(i)
			if (row) {
				result.push({
					desktopEntry: row.desktopEntry,
					applicationName: row.applicationName,
					notifyRcName: row.notifyRcName,
					summary: row.summary,
					body: row.body,
				})
			}
		}
		if (result.length !== rows.length) {
			logger.debug(logPrefix, "notification history now has", result.length, "notification(s)")
		}
		rows = result
	}

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
		running: !notificationHistory.serverValid
		onTriggered: {
			var process = Qt.application.name || "<unknown>"
			if (process !== "plasmashell") {
				console.warn(notificationHistory.logPrefix, "Running in", "\"" + process + "\",", "not plasmashell. Plasma's notification history only exists inside plasmashell (current owner of the notification service:", notificationHistory.serverOwnerText() + "),", "so notification counts stay at 0 here. Test notification tiles in the real panel instead.")
			} else {
				console.warn(notificationHistory.logPrefix, "Plasma's notification server is not running in plasmashell (current owner of the notification service:", notificationHistory.serverOwnerText() + ").", "Is the Notifications widget in the system tray? This applet won't start the server itself; counts stay at 0 until it is running.")
			}
		}
	}
}
