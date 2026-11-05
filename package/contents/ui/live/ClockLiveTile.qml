import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3

// Live tile: current time (and date when there's room).
// Tile fields: liveFormat — optional Qt time format (e.g. "hh:mm:ss"),
// defaults to the locale's short time format.
ColumnLayout {
	id: clockLiveTile
	spacing: 0

	property date now: new Date()
	readonly property bool showDate: height >= width * 0.6 && width > 80

	Timer {
		interval: 1000
		running: tileItemView.liveActive
		repeat: true
		triggeredOnStart: true
		onTriggered: clockLiveTile.now = new Date()
	}

	PlasmaComponents3.Label {
		Layout.fillWidth: true
		Layout.fillHeight: true
		text: appObj.liveFormat
			? Qt.formatTime(clockLiveTile.now, appObj.liveFormat)
			: clockLiveTile.now.toLocaleTimeString(Qt.locale(), Locale.ShortFormat)
		font.pixelSize: 200
		minimumPixelSize: 8
		fontSizeMode: Text.Fit
		horizontalAlignment: Text.AlignHCenter
		verticalAlignment: Text.AlignVCenter
		renderType: Text.QtRendering
	}

	PlasmaComponents3.Label {
		Layout.fillWidth: true
		visible: clockLiveTile.showDate
		text: clockLiveTile.now.toLocaleDateString(Qt.locale(), "dddd, d MMMM")
		elide: Text.ElideRight
		horizontalAlignment: Text.AlignHCenter
		renderType: Text.QtRendering
		opacity: 0.8
	}
}
