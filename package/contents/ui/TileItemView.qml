import QtQuick
import QtQuick.Window
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

Rectangle {
	id: tileItemView
	color: appObj.backgroundColor
	property color gradientBottomColor: Qt.darker(appObj.backgroundColor, 2.0)

	Component {
		id: tileGradient
		Gradient {
			GradientStop { position: 0.0; color: appObj.backgroundColor }
			GradientStop { position: 1.0; color: tileItemView.gradientBottomColor }
		}
	}
	gradient: appObj.backgroundGradient ? tileGradient.createObject(tileItemView) : null

	readonly property int tilePadding: 4 * config.scaleFactor
	readonly property int smallIconSize: config.smallTileIcons ? 24 : 32 * config.scaleFactor
	readonly property int mediumIconSize: config.smallTileIcons ? 48 : 72 * config.scaleFactor
	readonly property int largeIconSize: config.smallTileIcons ? 72 : 96 * config.scaleFactor

	readonly property int labelAlignment: appObj.isGroup ? config.groupLabelAlignment : config.tileLabelAlignment

	property bool hovered: false

	//--- Live tile
	// Only animate/poll while the menu window is actually shown, so live tiles
	// cost nothing while the menu is closed.
	readonly property bool liveActive: appObj.isLive && Window.window !== null && Window.window.visible
	property bool liveFaceToggle: true
	readonly property bool liveFaceShown: appObj.isLive && (!appObj.liveCycle || liveFaceToggle)
	readonly property real staticFaceOpacity: liveFaceShown ? 0 : 1
	clip: appObj.isLive

	Timer {
		// Stagger tiles so they don't all flip at the same moment.
		interval: 5000 + Math.floor(Math.random() * 4000)
		running: tileItemView.liveActive && appObj.liveCycle
		repeat: true
		onTriggered: tileItemView.liveFaceToggle = !tileItemView.liveFaceToggle
		onRunningChanged: if (!running) tileItemView.liveFaceToggle = true
	}

	// State conditions read appObj (QML properties) instead of modelData
	// (plain JS object): Qt >= 6.10 (Plasma 6.8) no longer tracks JS-object
	// property changes in bindings, so only QML-property dependencies update
	// after a tile is resized (see AppObject.updateFromTile).
	states: [
		State {
			when: appObj.tileW == 1 && appObj.tileH >= 1
			PropertyChanges { target: icon; size: smallIconSize }
			PropertyChanges { target: label; visible: false }
		},
		State {
			when: appObj.tileW >= 2 && appObj.tileH == 1
			AnchorChanges { target: icon
				anchors.horizontalCenter: undefined
				anchors.left: tileItemView.left
			}
			PropertyChanges { target: icon; anchors.leftMargin: tilePadding }
			PropertyChanges { target: label
				verticalAlignment: Text.AlignVCenter
			}
			AnchorChanges { target: label
				anchors.left: icon.right
			}
		},
		State {
			when: (appObj.tileW >= 2 && appObj.tileH == 2) || (appObj.tileW == 2 && appObj.tileH >= 2)
			PropertyChanges { target: icon; size: mediumIconSize }
		},
		State {
			when: appObj.tileW >= 3 && appObj.tileH >= 3
			PropertyChanges { target: icon; size: largeIconSize }
		}
	]

	Image {
		id: backgroundImage
		anchors.fill: parent
		visible: appObj.backgroundImage
		opacity: tileItemView.staticFaceOpacity
		Behavior on opacity { NumberAnimation { duration: 300 } }
		source: appObj.backgroundImage
		fillMode: Image.PreserveAspectCrop
		asynchronous: true
		smooth: true
		mipmap: true
	}

	Kirigami.Icon {
		id: icon
		visible: appObj.showIcon
		opacity: tileItemView.staticFaceOpacity
		Behavior on opacity { NumberAnimation { duration: 300 } }
		source: appObj.iconSource
		anchors.verticalCenter: parent.verticalCenter
		anchors.horizontalCenter: parent.horizontalCenter
		// property int size: 72 // Just a default, overriden in State change
		property int size: Math.min(parent.width, parent.height) / 2
		width: appObj.showIcon ? size : 0
		height: appObj.showIcon ? size : 0
		anchors.fill: appObj.iconFill ? parent : null
		smooth: appObj.iconFill || config.smallTileIcons
	}

	PlasmaComponents3.Label {
		id: label
		visible: appObj.showLabel
		opacity: tileItemView.staticFaceOpacity
		Behavior on opacity { NumberAnimation { duration: 300 } }
		text: appObj.labelText
		anchors.top: parent.top
		anchors.bottom: parent.bottom
		anchors.leftMargin: tilePadding
		anchors.rightMargin: tilePadding
		anchors.left: parent.left
		anchors.right: parent.right
		wrapMode: Text.Wrap
		horizontalAlignment: labelAlignment
		verticalAlignment: Text.AlignBottom
		width: parent.width
		renderType: Text.QtRendering // Fix pixelation when scaling. Plasma.Label uses NativeRendering.
		style: Text.Outline
		styleColor: appObj.backgroundGradient ? tileItemView.gradientBottomColor : appObj.backgroundColor
	}

	// Slides up over the static face (Windows-style "peek"). Live tile
	// components are loaded from live/ and can read `appObj` and
	// `tileItemView` (liveActive, tilePadding) from this context.
	Item {
		id: liveFace
		visible: appObj.isLive
		width: parent.width
		height: parent.height
		y: tileItemView.liveFaceShown ? 0 : height
		Behavior on y { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }

		Rectangle {
			id: liveBackground
			anchors.fill: parent
			color: appObj.backgroundColor
			gradient: appObj.backgroundGradient ? tileGradient.createObject(liveBackground) : null
		}

		Loader {
			id: liveLoader
			anchors.fill: parent
			anchors.margins: appObj.liveFullBleed ? 0 : tilePadding
			anchors.bottomMargin: appObj.liveFullBleed ? 0 : liveLabel.visible ? liveLabel.height + tilePadding : tilePadding
			active: appObj.isLive
			source: appObj.liveSource
		}

		Rectangle {
			// Keeps the label readable over full-bleed content (photos).
			visible: appObj.liveFullBleed && liveLabel.visible
			anchors.left: parent.left
			anchors.right: parent.right
			anchors.bottom: parent.bottom
			height: liveLabel.height + tilePadding * 4
			gradient: Gradient {
				GradientStop { position: 0.0; color: "transparent" }
				GradientStop { position: 1.0; color: "#99000000" }
			}
		}

		PlasmaComponents3.Label {
			id: liveLabel
			visible: appObj.showLabel && appObj.tileW >= 2 && appObj.tileH >= 2
			text: appObj.labelText
			anchors.left: parent.left
			anchors.right: parent.right
			anchors.bottom: parent.bottom
			anchors.margins: tilePadding
			elide: Text.ElideRight
			horizontalAlignment: labelAlignment
			font.pointSize: Kirigami.Theme.smallFont.pointSize
			renderType: Text.QtRendering
			color: appObj.liveFullBleed ? "white" : Kirigami.Theme.textColor
		}
	}
}
