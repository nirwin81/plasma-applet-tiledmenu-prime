import QtQuick
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.plasma5support as P5Support

// Live tile: shows the output of a shell command, re-run every
// `liveInterval` seconds while the menu is open.
// Tile fields: liveCommand, liveInterval (seconds, default 60).
Item {
	id: commandLiveTile

	property string output: ""
	property bool failed: false

	P5Support.DataSource {
		id: executable
		engine: "executable"
		connectedSources: []
		onNewData: function(sourceName, data) {
			var stdout = (data["stdout"] || "").trim()
			var stderr = (data["stderr"] || "").trim()
			commandLiveTile.failed = data["exit code"] !== 0 && !stdout
			commandLiveTile.output = stdout || stderr
			// Disconnect so the next connectSource() runs the command again.
			disconnectSource(sourceName)
		}
	}

	function run() {
		var cmd = appObj.liveCommand
		if (cmd && executable.connectedSources.indexOf(cmd) === -1) {
			executable.connectSource(cmd)
		}
	}

	Timer {
		interval: appObj.liveInterval * 1000
		running: tileItemView.liveActive && appObj.liveCommand !== ""
		repeat: true
		triggeredOnStart: true
		onTriggered: commandLiveTile.run()
	}

	PlasmaComponents3.Label {
		anchors.fill: parent
		text: appObj.liveCommand ? commandLiveTile.output : i18n("No command set")
		font.pixelSize: 200
		minimumPixelSize: 8
		fontSizeMode: Text.Fit
		wrapMode: Text.Wrap
		horizontalAlignment: Text.AlignHCenter
		verticalAlignment: Text.AlignVCenter
		renderType: Text.QtRendering
		opacity: commandLiveTile.failed || !appObj.liveCommand ? 0.6 : 1
	}
}
