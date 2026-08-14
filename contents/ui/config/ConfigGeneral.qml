import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import "../org/punchi/dock" as Punchi
import org.kde.taskmanager as TaskManager
import "components"

KCM.SimpleKCM {
    id: page
    implicitWidth: layoutMetrics.pageImplicitWidth

    ConfigLayoutMetrics {
        id: layoutMetrics
        availableWidth: page.width
    }

    // Variables prefixed with "cfg_" map automatically to KConfig (main.xml).
    property alias cfg_iconSize: iconSizeSlider.value
    property alias cfg_iconSpacing: iconSpacingSlider.value
    property string cfg_virtualDesktopMode: "all"
    property string cfg_targetVirtualDesktop: ""
    property string cfg_panelLengthMode: "content"
    property string cfg_panelAlignmentMode: "start"
    property alias cfg_panelFitMaxLengthPercent: fitMaxLengthSlider.value
    property alias cfg_panelAlignmentOffset: alignmentOffsetSlider.value
    property string cfg_panelAlignmentOffsetReference: "panel"
    property alias cfg_dockContentHorizontalPadding: horizontalPaddingSlider.value
    property alias cfg_dockContentVerticalPadding: verticalPaddingSlider.value
    readonly property bool interactiveCursorEnabled: !!Plasmoid.configuration.globalMouseCursor
    readonly property bool inPanel: Plasmoid.formFactor === PlasmaCore.Types.Horizontal || Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property bool verticalPanel: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property int contentWidthHint: layoutMetrics.contentWidth
    readonly property int selectorWidthHint: layoutMetrics.selectorWidth
    // Plasma::Containment exposes its visual geometry at runtime, although the
    // generated QML type metadata does not declare width/height.
    // qmllint disable missing-property
    readonly property int detectedPanelThickness: {
        try {
            var containment = Plasmoid.containment
            if (!containment) {
                return 0
            }

            var thickness = verticalPanel
                ? Math.max(0, Number(containment["width"] || 0))
                : Math.max(0, Number(containment["height"] || 0))
            return thickness > 0 ? thickness : 0
        } catch (error) {
            return 0
        }
    }
    // qmllint enable missing-property
    // Mirror DockGeometryState.panelCrossAxisPadding so the icon-size limit
    // shown here matches what runtime geometry actually reserves: the cross
    // axis uses horizontal padding on a vertical panel and vice versa.
    readonly property int panelCrossAxisPadding: verticalPanel
        ? Math.round(Number(cfg_dockContentHorizontalPadding)) * 2
        : Math.round(Number(cfg_dockContentVerticalPadding)) * 2
    readonly property int safePanelIconSizeMax: detectedPanelThickness > 0
        ? Math.max(32, detectedPanelThickness - panelCrossAxisPadding - 12)
        : 96
    readonly property bool flexiblePanelLengthAvailable: inPanel
    readonly property var panelLengthOptions: [
        { "text": i18n("Fit content"), "value": "content" },
        { "text": i18n("Fill free panel space"), "value": "fill" }
    ]
    // qmllint disable unqualified
    readonly property var panelAlignmentOptions: verticalPanel ? [
        { "text": i18n("Top to bottom"), "value": "start" },
        { "text": i18n("Center"), "value": "center" },
        { "text": i18n("Bottom to top"), "value": "end" }
    ] : [
        { "text": i18n("Left to right"), "value": "start" },
        { "text": i18n("Center"), "value": "center" },
        { "text": i18n("Right to left"), "value": "end" }
    ]
    // qmllint enable unqualified
    readonly property var virtualDesktopModel: {
        var result = []
        var ids = virtualDesktopInfo.desktopIds
        var names = virtualDesktopInfo.desktopNames
        for (var index = 0; index < ids.length; index++) {
            result.push({
                "id": String(ids[index]),
                "name": index < names.length ? names[index] : i18n("Desktop %1", index + 1)
            })
        }
        return result
    }
    readonly property string defaultTargetVirtualDesktopId: {
        if (virtualDesktopModel.length === 0) {
            return ""
        }

        var currentDesktopId = String(virtualDesktopInfo.currentDesktop || "")
        if (currentDesktopId.length > 0) {
            for (var index = 0; index < virtualDesktopModel.length; index++) {
                if (virtualDesktopModel[index].id === currentDesktopId) {
                    return currentDesktopId
                }
            }
        }

        return virtualDesktopModel[0].id
    }
    readonly property bool targetVirtualDesktopAvailable: cfg_targetVirtualDesktop === ""
        || virtualDesktopInfo.desktopIds.map(function(desktopId) { return String(desktopId) }).indexOf(cfg_targetVirtualDesktop) !== -1

    TaskManager.VirtualDesktopInfo {
        id: virtualDesktopInfo
    }
    Punchi.PanelLengthModeBridge {
        id: panelLengthModeBridge
        containmentId: Plasmoid.containment ? Plasmoid.containment.id : 0
    }

    Connections {
        target: virtualDesktopInfo

        function ensureTargetDesktopSelection() {
            if (page.cfg_virtualDesktopMode === "single"
                    && page.cfg_targetVirtualDesktop === ""
                    && page.defaultTargetVirtualDesktopId !== "") {
                page.cfg_targetVirtualDesktop = page.defaultTargetVirtualDesktopId
            }
        }

        function onDesktopIdsChanged() {
            ensureTargetDesktopSelection()
        }

        function onCurrentDesktopChanged() {
            ensureTargetDesktopSelection()
        }
    }

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing
        Layout.fillWidth: true

        Kirigami.FormLayout {
            Layout.fillWidth: true

            RowLayout {
                visible: page.flexiblePanelLengthAvailable
                Kirigami.FormData.label: i18n("Panel length:")
                Layout.maximumWidth: page.contentWidthHint

                Controls.ComboBox {
                    id: panelLengthModeCombo
                    Layout.preferredWidth: page.selectorWidthHint
                    Layout.maximumWidth: page.selectorWidthHint
                    textRole: "text"
                    valueRole: "value"
                    model: page.panelLengthOptions
                    currentIndex: Math.max(0, indexOfValue(page.cfg_panelLengthMode))
                    onActivated: page.cfg_panelLengthMode = currentValue
                    Accessible.name: i18n("Panel length")

                    ConfigCursorBehavior {
                        cursorEnabled: page.interactiveCursorEnabled
                    }
                }
            }

            // Applies only in Fit content mode: caps how much of the screen axis
            // dynamic tasks may use before overflowing. It bounds the growing
            // (task) part of the dock, not fixed launchers/media/separators.
            RowLayout {
                visible: page.inPanel && page.cfg_panelLengthMode === "content"
                Kirigami.FormData.label: i18n("Maximum task length:")
                Layout.maximumWidth: page.contentWidthHint

                Controls.Slider {
                    id: fitMaxLengthSlider
                    from: 0
                    to: 100
                    stepSize: 5
                    Layout.fillWidth: true
                    Layout.preferredWidth: page.contentWidthHint - 90
                    Accessible.name: i18n("Maximum dynamic task length")
                    Accessible.description: i18n("Limits how much of the screen axis dynamic tasks may use before overflowing, as a percentage. Pinned launchers and other fixed items are not affected. Zero means no limit.")

                    ConfigCursorBehavior {
                        cursorEnabled: page.interactiveCursorEnabled
                        role: "slider"
                    }
                }

                Controls.Label {
                    text: page.cfg_panelFitMaxLengthPercent <= 0
                        ? i18nc("@label no maximum dock length", "Unlimited")
                        : i18nc("@label percentage of the screen axis", "%1%", Math.round(page.cfg_panelFitMaxLengthPercent))
                    font.bold: true
                    Layout.preferredWidth: 80
                }
            }

            // qmllint disable unqualified
            RowLayout {
                visible: page.inPanel
                Kirigami.FormData.label: page.verticalPanel ? i18n("Vertical alignment:") : i18n("Horizontal alignment:")
                Layout.maximumWidth: page.contentWidthHint

                Controls.ComboBox {
                    id: panelAlignmentModeCombo
                    Layout.preferredWidth: page.selectorWidthHint
                    Layout.maximumWidth: page.selectorWidthHint
                    textRole: "text"
                    valueRole: "value"
                    model: page.panelAlignmentOptions
                    currentIndex: Math.max(0, indexOfValue(page.cfg_panelAlignmentMode))
                    onActivated: page.cfg_panelAlignmentMode = currentValue
                    Accessible.name: page.verticalPanel ? i18n("Vertical alignment") : i18n("Horizontal alignment")

                    ConfigCursorBehavior {
                        cursorEnabled: page.interactiveCursorEnabled
                    }
                }
            }

            // Center relative to the whole screen instead of the applet's slice
            // of the panel. Only meaningful for centered alignment; matters when
            // the dock shares a Fill panel with other applets.
            RowLayout {
                visible: page.inPanel && page.cfg_panelLengthMode === "content"
                    && page.cfg_panelAlignmentMode === "center"
                Kirigami.FormData.label: i18n("Center relative to:")
                Layout.maximumWidth: page.contentWidthHint

                Controls.ComboBox {
                    id: alignmentReferenceCombo
                    Layout.preferredWidth: page.selectorWidthHint
                    Layout.maximumWidth: page.selectorWidthHint
                    textRole: "text"
                    valueRole: "value"
                    model: [
                        { "text": i18n("Panel"), "value": "panel" },
                        { "text": i18n("Screen"), "value": "screen" }
                    ]
                    currentIndex: Math.max(0, indexOfValue(page.cfg_panelAlignmentOffsetReference))
                    onActivated: page.cfg_panelAlignmentOffsetReference = currentValue
                    Accessible.name: i18n("Center relative to")

                    ConfigCursorBehavior {
                        cursorEnabled: page.interactiveCursorEnabled
                    }
                }
            }

            // Fine-tune shift of the aligned dock along the panel, in pixels.
            RowLayout {
                visible: page.inPanel && page.cfg_panelLengthMode === "content"
                Kirigami.FormData.label: i18n("Alignment offset:")
                Layout.maximumWidth: page.contentWidthHint

                Controls.Slider {
                    id: alignmentOffsetSlider
                    from: -256
                    to: 256
                    stepSize: 2
                    Layout.fillWidth: true
                    Layout.preferredWidth: page.contentWidthHint - 90
                    Accessible.name: i18n("Alignment offset")
                    Accessible.description: i18n("Shifts the aligned dock along the panel, in pixels. Positive moves it toward the end edge.")

                    ConfigCursorBehavior {
                        cursorEnabled: page.interactiveCursorEnabled
                        role: "slider"
                    }
                }

                Controls.Label {
                    text: i18nc("@label pixel offset", "%1 px", Math.round(page.cfg_panelAlignmentOffset))
                    font.bold: true
                    Layout.preferredWidth: 80
                }
            }

            // Alignment (Center/End) and "Fill free panel space" need the host
            // Plasma panel to offer free length. When it does not, the choices
            // are stored but inert, so explain how to unlock them.
            Kirigami.InlineMessage {
                Layout.fillWidth: true
                Layout.maximumWidth: page.contentWidthHint
                visible: page.inPanel && !panelLengthModeBridge.fillAvailable
                    && (page.cfg_panelAlignmentMode !== "start"
                        || page.cfg_panelLengthMode === "fill")
                type: Kirigami.MessageType.Information
                text: page.verticalPanel
                    ? i18nc("@info", "Alignment and “Fill free panel space” take effect only when this Plasma panel’s height is set to fill its screen edge. Enter the panel’s Edit Mode and set its height to Fill.")
                    : i18nc("@info", "Alignment and “Fill free panel space” take effect only when this Plasma panel’s width is set to fill its screen edge. Enter the panel’s Edit Mode and set its width to Fill.")
                Accessible.name: text.replace(/“|”/g, "")
            }
            // qmllint enable unqualified

            // Icon size control.
            RowLayout {
                Kirigami.FormData.label: page.inPanel ? i18n("Panel icon size:") : i18n("Floating icon size:")
                Layout.maximumWidth: page.contentWidthHint

                Controls.Slider {
                    id: iconSizeSlider
                    from: 32
                    to: page.inPanel ? page.safePanelIconSizeMax : 96
                    stepSize: 2
                    Layout.fillWidth: true
                    Layout.preferredWidth: page.contentWidthHint - 60

                    ConfigCursorBehavior {
                        cursorEnabled: page.interactiveCursorEnabled
                        role: "slider"
                    }
                }

                Controls.Label {
                    text: iconSizeSlider.value + " px"
                    font.bold: true
                    Layout.preferredWidth: 50
                }
            }

            // qmllint disable unqualified
            RowLayout {
                Kirigami.FormData.label: i18n("Icon spacing:")
                Layout.maximumWidth: page.contentWidthHint

                Controls.Slider {
                    id: iconSpacingSlider
                    from: 0
                    to: 24
                    stepSize: 1
                    Layout.fillWidth: true
                    Layout.preferredWidth: page.contentWidthHint - 60
                    Accessible.name: i18n("Icon spacing")
                    Accessible.description: i18n("Adjusts the spacing between dock icons from 0 to 24 pixels.")

                    ConfigCursorBehavior {
                        cursorEnabled: page.interactiveCursorEnabled
                        role: "slider"
                    }
                }

                Controls.Label {
                    text: Math.round(iconSpacingSlider.value) + " px"
                    font.bold: true
                    Layout.preferredWidth: 50
                }
            }
            // qmllint enable unqualified

            // Dock background padding along and across the dock. Bounded 0-32;
            // defaults (10/12) preserve the original spacing.
            RowLayout {
                visible: page.inPanel
                Kirigami.FormData.label: i18n("Horizontal padding:")
                Layout.maximumWidth: page.contentWidthHint

                Controls.Slider {
                    id: horizontalPaddingSlider
                    from: 0
                    to: 32
                    stepSize: 1
                    Layout.fillWidth: true
                    Layout.preferredWidth: page.contentWidthHint - 60
                    Accessible.name: i18n("Horizontal padding")
                    Accessible.description: i18n("Padding on the left and right of the dock background, from 0 to 32 pixels.")

                    ConfigCursorBehavior {
                        cursorEnabled: page.interactiveCursorEnabled
                        role: "slider"
                    }
                }

                Controls.Label {
                    text: Math.round(page.cfg_dockContentHorizontalPadding) + " px"
                    font.bold: true
                    Layout.preferredWidth: 50
                }
            }

            RowLayout {
                visible: page.inPanel
                Kirigami.FormData.label: i18n("Vertical padding:")
                Layout.maximumWidth: page.contentWidthHint

                Controls.Slider {
                    id: verticalPaddingSlider
                    from: 0
                    to: 32
                    stepSize: 1
                    Layout.fillWidth: true
                    Layout.preferredWidth: page.contentWidthHint - 60
                    Accessible.name: i18n("Vertical padding")
                    Accessible.description: i18n("Padding above and below the dock background, from 0 to 32 pixels.")

                    ConfigCursorBehavior {
                        cursorEnabled: page.interactiveCursorEnabled
                        role: "slider"
                    }
                }

                Controls.Label {
                    text: Math.round(page.cfg_dockContentVerticalPadding) + " px"
                    font.bold: true
                    Layout.preferredWidth: 50
                }
            }

            Kirigami.InlineMessage {
                Kirigami.FormData.label: page.inPanel ? i18n("Limit:") : ""
                Layout.fillWidth: true
                Layout.maximumWidth: page.contentWidthHint
                visible: page.inPanel
                type: Kirigami.MessageType.Information
                text: page.detectedPanelThickness > 0
                    ? i18n("Estimated panel-safe maximum: %1 px", page.safePanelIconSizeMax)
                    : i18n("The real panel thickness is not available in this view, so a safe fallback limit is being used.")
            }

            // Virtual desktop visibility control.
            RowLayout {
                Kirigami.FormData.label: i18n("Desktop visibility:")
                Layout.maximumWidth: page.contentWidthHint

                Controls.ComboBox {
                    id: desktopModeCombo
                    Layout.preferredWidth: page.selectorWidthHint
                    Layout.maximumWidth: page.selectorWidthHint
                    textRole: "text"
                    valueRole: "value"
                    model: [
                        { "text": i18n("All desktops"), "value": "all" },
                        { "text": i18n("Single desktop"), "value": "single" }
                    ]

                    currentIndex: Math.max(0, indexOfValue(page.cfg_virtualDesktopMode))
                    onActivated: {
                        page.cfg_virtualDesktopMode = currentValue
                        if (currentValue === "single"
                                && page.cfg_targetVirtualDesktop === ""
                                && page.defaultTargetVirtualDesktopId !== "") {
                            page.cfg_targetVirtualDesktop = page.defaultTargetVirtualDesktopId
                        }
                    }

                    ConfigCursorBehavior {
                        cursorEnabled: page.interactiveCursorEnabled
                    }
                }
            }

            // Target virtual desktop selector.
            RowLayout {
                Kirigami.FormData.label: i18n("Target desktop:")
                visible: page.cfg_virtualDesktopMode === "single"
                Layout.maximumWidth: page.contentWidthHint

                Controls.ComboBox {
                    id: desktopCombo
                    Layout.preferredWidth: page.selectorWidthHint
                    Layout.maximumWidth: page.selectorWidthHint
                    textRole: "name"
                    valueRole: "id"
                    model: page.virtualDesktopModel
                    enabled: count > 0
                    currentIndex: {
                        if (count === 0) {
                            return -1
                        }
                        var targetDesktopId = page.cfg_targetVirtualDesktop || page.defaultTargetVirtualDesktopId
                        return indexOfValue(targetDesktopId)
                    }
                    onActivated: {
                        page.cfg_targetVirtualDesktop = currentValue
                    }

                    ConfigCursorBehavior {
                        cursorEnabled: page.interactiveCursorEnabled
                    }
                }
            }

            Kirigami.InlineMessage {
                Kirigami.FormData.isSection: true
                Layout.fillWidth: true
                Layout.maximumWidth: page.contentWidthHint
                visible: page.cfg_virtualDesktopMode === "single"
                    && (page.virtualDesktopModel.length === 0 || !page.targetVirtualDesktopAvailable)
                type: Kirigami.MessageType.Warning
                text: page.virtualDesktopModel.length === 0
                    ? i18n("No virtual desktops were found.")
                    : i18n("The selected desktop no longer exists. Choose another desktop.")
            }
        }

        Kirigami.InlineMessage {
            id: statusInlineMessage
            visible: true
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            type: Kirigami.MessageType.Information
            showCloseButton: false
            text: !page.inPanel
                ? i18nc("@info:status <b> marks the current dock mode", "Current dock state: <b>Floating mode</b>.<br>Panel-only sizing and integration options are unavailable.")
                : page.verticalPanel
                    ? i18nc("@info:status <b> marks the current dock mode", "Current dock state: <b>Vertical panel</b>.<br>Fill free panel space is active only when the Plasma panel is set to Fill available; otherwise Punchi Dock remains compact.")
                    : i18nc("@info:status <b> marks the current dock mode", "Current dock state: <b>Horizontal panel</b>.<br>Fill free panel space is active only when the Plasma panel is set to Fill available; otherwise Punchi Dock remains compact.")
            Accessible.name: text.replace("<br>", " ").replace("<b>", "").replace("</b>", "")
        }

        // Auto-hide and always-on-top are panel-level behaviors owned by Plasma,
        // not by the applet, so point users at the panel's own settings.
        Kirigami.InlineMessage {
            id: panelBehaviorInlineMessage
            visible: page.inPanel
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            type: Kirigami.MessageType.Information
            showCloseButton: true
            text: i18nc("@info", "Auto-hide and always-on-top are provided by Plasma’s panel settings, not the dock. Right-click the panel, enter Edit Mode, and open Visibility: choose Auto Hide, or Windows Go Below / Always Visible to keep the dock above windows.")
            Accessible.name: text
        }
    }
}
