/*
    SPDX-FileCopyrightText: 2011 Sebastian Kügler <sebas@kde.org>
    SPDX-FileCopyrightText: 2011 Viranch Mehta <viranch.mehta@gmail.com>
    SPDX-FileCopyrightText: 2013-2015 Kai Uwe Broulik <kde@privat.broulik.de>
    SPDX-FileCopyrightText: 2021-2022 ivan tkachenko <me@ratijas.tk>
    SPDX-FileCopyrightText: 2023 Natalie Clarius <natalie.clarius@kde.org>

    SPDX-License-Identifier: LGPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts

import org.kde.coreaddons as KCoreAddons
import org.kde.kcmutils as KCMUtils
import org.kde.config as KConfig
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import org.kde.kitemmodels as KItemModels

import org.kde.plasma.private.batterymonitor.sleepcustom
import org.kde.plasma.private.battery

PlasmoidItem {
    id: batterymonitor

    PowerProfilesControl {
        id: powerProfilesControl

        readonly property bool isInBalancedProfile: activeProfile === "balanced"
        readonly property bool isInPerformanceProfile: activeProfile === "performance"
        readonly property bool isInPowersaveProfile: activeProfile === "power-saver"
        readonly property bool isHeldOnPowerProfile: profileHolds.length > 0
        readonly property string defaultPowerProfile: configuredProfile ? configuredProfile : "balanced"
        readonly property bool isInDefaultPowerProfile: !activeProfile || activeProfile === defaultPowerProfile
    }

    BatteryControlModel {
        id: batteryControl

        readonly property int remainingTime: smoothedRemainingMsec
        readonly property bool isSomehowFullyCharged: pluggedIn && state === BatteryControlModel.FullyCharged
    }

    InhibitionControl {
        id: inhibitionControl
    }

    // The duration setting is remembered, but an active deadline is deliberately
    // runtime-only. Plasma already releases the DBus inhibitors if plasmashell exits.
    property double inhibitionDeadlineMsec: 0
    property int inhibitionRemainingSeconds: 0
    readonly property bool isAnyManualInhibitionActive: inhibitionControl.isManuallyInhibited || inhibitionControl.isManuallySleepOnlyInhibited

    function clearInhibitionCountdown(): void {
        inhibitionDeadlineMsec = 0;
        inhibitionRemainingSeconds = 0;
    }

    function restartInhibitionCountdown(): void {
        const durationMinutes = Plasmoid.configuration.inhibitionDurationMinutes;
        if (durationMinutes <= 0) {
            clearInhibitionCountdown();
            return;
        }

        inhibitionDeadlineMsec = Date.now() + durationMinutes * 60 * 1000;
        inhibitionRemainingSeconds = durationMinutes * 60;
    }

    function updateInhibitionCountdown(): void {
        if (inhibitionDeadlineMsec <= 0) {
            inhibitionRemainingSeconds = 0;
            return;
        }

        const remainingSeconds = Math.ceil((inhibitionDeadlineMsec - Date.now()) / 1000);
        if (remainingSeconds > 0) {
            inhibitionRemainingSeconds = remainingSeconds;
            return;
        }

        clearInhibitionCountdown();
        if (inhibitionControl.isManuallyInhibited) {
            inhibitionChangeRequested(false);
        } else if (inhibitionControl.isManuallySleepOnlyInhibited) {
            sleepOnlyInhibitionChangeRequested(false);
        }
    }

    Timer {
        id: inhibitionCountdownTimer
        interval: 1000
        repeat: true
        running: batterymonitor.inhibitionDeadlineMsec > 0 && batterymonitor.isAnyManualInhibitionActive
        onTriggered: batterymonitor.updateInhibitionCountdown()
    }

    readonly property bool kcmAuthorized: KConfig.KAuthorized.authorizeControlModule("kcm_powerdevilprofilesconfig")
    readonly property bool kcmEnergyInformationAuthorized: KConfig.KAuthorized.authorizeControlModule("kcm_energyinfo")

    readonly property bool inPanel: [
        PlasmaCore.Types.TopEdge,
        PlasmaCore.Types.RightEdge,
        PlasmaCore.Types.BottomEdge,
        PlasmaCore.Types.LeftEdge,
    ].includes(Plasmoid.location)
    readonly property bool compactInPanel: inPanel && !!compactRepresentationItem?.visible

    function symbolicizeIconName(iconName: string): string {
        const symbolicSuffix = "-symbolic";
        if (iconName.endsWith(symbolicSuffix)) {
            return iconName;
        }

        return iconName + symbolicSuffix;
    }

    signal inhibitionChangeRequested(bool inhibit)
    signal sleepOnlyInhibitionChangeRequested(bool inhibit)
    signal inhibitionDurationChangeRequested(int durationMinutes)

    onInhibitionChangeRequested: inhibit => {
        inhibitionControl.isSilent = expanded; // show OSD only when the plasmoid isn't expanded since the changing switch is feedback enough

        if (inhibit) {
            const reason = i18n("The battery applet has enabled suppressing sleep and screen locking");
            inhibitionControl.inhibit(reason)
            restartInhibitionCountdown();
        } else {
            clearInhibitionCountdown();
            inhibitionControl.uninhibit()
        }
    }

    onSleepOnlyInhibitionChangeRequested: inhibit => {
        inhibitionControl.isSilent = expanded;

        if (inhibit) {
            const reason = i18n("The battery applet has enabled suppressing sleep only");
            inhibitionControl.inhibitSleepOnly(reason)
            restartInhibitionCountdown();
        } else {
            clearInhibitionCountdown();
            inhibitionControl.uninhibitSleepOnly()
        }
    }

    onInhibitionDurationChangeRequested: durationMinutes => {
        Plasmoid.configuration.inhibitionDurationMinutes = Math.max(0, durationMinutes);
        if (isAnyManualInhibitionActive) {
            restartInhibitionCountdown();
        }
    }

    signal activateProfileRequested(string profile)

    onActivateProfileRequested: profile => {
        powerProfilesControl.isSilent = expanded;

        if (profile === powerProfilesControl.activeProfile) {
            return;
        }
        powerProfilesControl.setProfile(profile);
    }

    switchWidth: Kirigami.Units.gridUnit * 10
    switchHeight: Kirigami.Units.gridUnit * 10

    Plasmoid.title: batteryControl.hasBatteries ? i18n("Power & Battery") : i18n("Power Management")

    LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
    LayoutMirroring.childrenInherit: true

    Plasmoid.status: {
        if (inhibitionControl.isManuallyInhibited || inhibitionControl.isManuallySleepOnlyInhibited || !powerProfilesControl.isInDefaultPowerProfile) {
            return PlasmaCore.Types.ActiveStatus;
        }

        if (batteryControl.hasCumulative && (batteryControl.state === BatteryControlModel.Discharging || batteryControl.state === BatteryControlModel.Charging)) {
            return PlasmaCore.Types.ActiveStatus;
        }

        return PlasmaCore.Types.PassiveStatus;
    }

    toolTipMainText: {
        if (batteryControl.hasInternalBatteries && !batteryControl.hasCumulative) {
            return i18n("Battery is not present in the bay");
        }

        if (!batteryControl.hasInternalBatteries) {
            return Plasmoid.title
        } else if (batteryControl.isSomehowFullyCharged) {
            return i18n("Fully Charged");
        }

        const percent = batteryControl.percent;
        if (batteryControl.pluggedIn) {
            const state = batteryControl.state;
            if (state === BatteryControlModel.NoCharge) {
                return i18n("Battery at %1%, not Charging", percent);
            } else if (state === BatteryControlModel.Discharging) {
                return i18n("Battery at %1%, plugged in but still discharging", percent);
            } else if (state === BatteryControlModel.Charging) {
                return i18n("Battery at %1%, Charging", percent);
            }
        }
        return i18n("Battery at %1%", percent);
    }

    toolTipSubText: {
        const parts = [];

        // Add special text for the "plugged in but still discharging" case
        if (batteryControl.pluggedIn && batteryControl.state === BatteryControlModel.Discharging) {
            parts.push(i18n("The power supply is not powerful enough to charge the battery"));
        }

        if (!batteryControl.hasBatteries) {
            parts.push(i18n("No Batteries Available"));
        } else if (batteryControl.hasInternalBatteries) {
            if (batteryControl.remainingTime > 0) {
                const remainingTimeString = KCoreAddons.Format.formatDuration(batteryControl.remainingTime, KCoreAddons.FormatTypes.HideSeconds);
                if (batteryControl.state === BatteryControlModel.FullyCharged) {
                    // Don't add anything
                } else if (batteryControl.pluggedIn && batteryControl.state === BatteryControlModel.Charging) {
                    parts.push(i18nc("time until fully charged - HH:MM", "%1 until fully charged", remainingTimeString));
                } else {
                    parts.push(i18nc("remaining time left of battery usage - HH:MM", "%1 remaining", remainingTimeString));
                }
            } else if (batteryControl.state === BatteryControlModel.NoCharge && !batteryControl.isSomehowFullyCharged) {
                parts.push(i18n("Not charging"));
            } // otherwise, don't add anything
        }

        if (inhibitionControl.isManuallyInhibited) {
            parts.push(i18n("Automatic sleep and screen locking are disabled; middle-click to re-enable"));
        } else if (inhibitionControl.isManuallySleepOnlyInhibited) {
            parts.push(i18n("Automatic sleep is disabled; screen locking remains enabled"));
        } else {
            parts.push(i18n("Middle-click to disable automatic sleep and screen locking"));
        }

        if (powerProfilesControl.isInPerformanceProfile) {
            if (powerProfilesControl.isHeldOnPowerProfile) {
                parts.push(i18np("An application has requested activating Performance mode",
                                 "%1 applications have requested activating Performance mode",
                                 powerProfilesControl.profileHolds.length));
            } else {
                parts.push(i18n("System is in Performance mode; scroll to change"));
            }
        } else if (powerProfilesControl.isInPowersaveProfile) {
            if (powerProfilesControl.isHeldOnPowerProfile) {
                parts.push(i18np("An application has requested activating Power Save mode",
                                "%1 applications have requested activating Power Save mode",
                                powerProfilesControl.profileHolds.length));
            } else {
                parts.push(i18n("System is in Power Save mode; scroll to change"));
            }
        } else if (powerProfilesControl.isInBalancedProfile) {
            parts.push(i18n("System is in Balanced Power mode; scroll to change"));
        }

        return parts.join("\n");
    }

    Plasmoid.icon: {
        let iconName;
        if (batteryControl.hasBatteries) {
            iconName = "battery-full";
        } else {
            iconName = "speedometer";
        }

        if (inPanel) {
            return symbolicizeIconName(iconName);
        }

        return iconName;
    }

    compactRepresentation: CompactRepresentation {
        batteryPercent: batteryControl.percent
        batteryPluggedIn: batteryControl.pluggedIn
        hasBatteries: batteryControl.hasBatteries
        hasInternalBatteries: batteryControl.hasInternalBatteries
        hasCumulative: batteryControl.hasCumulative

        isSomehowFullyCharged: batteryControl.isSomehowFullyCharged
        isDischarging: !batteryControl.pluggedIn

        isManuallyInhibited: inhibitionControl.isManuallyInhibited || inhibitionControl.isManuallySleepOnlyInhibited
        isInDefaultPowerProfile: powerProfilesControl.isInDefaultPowerProfile
        isInPowersaveProfile: powerProfilesControl.isInPowersaveProfile
        isInBalancedProfile: powerProfilesControl.isInBalancedProfile
        isInPerformanceProfile: powerProfilesControl.isInPerformanceProfile

        model: batteryControl

        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        property bool wasExpanded: false
        onPressed: wasExpanded = batterymonitor.expanded
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton) {
                batterymonitor.inhibitionChangeRequested(!inhibitionControl.isManuallyInhibited);
            } else {
                batterymonitor.expanded = !wasExpanded;
            }
        }

        onWheel: wheel => {
            if (!powerProfilesControl.isPowerProfileDaemonInstalled) {
                return;
            }

            let { profiles } = powerProfilesControl;
            if (profiles.length === 0) {
                return;
            }

            let { activeProfile } = powerProfilesControl;
            let newProfile = activeProfile;

            const delta = (wheel.inverted ? -1 : 1) * (wheel.angleDelta.y ? wheel.angleDelta.y : -wheel.angleDelta.x);
            // Magic number 120 for common "one click"
            // See: https://qt-project.org/doc/qt-5/qml-qtquick-wheelevent.html#angleDelta-prop
            const steps = Math.round(delta/120);
            const newProfileIndex = Math.max(0, Math.min(profiles.length - 1, profiles.indexOf(activeProfile) + steps));
            batterymonitor.activateProfileRequested(profiles[newProfileIndex])
        }
    }

    fullRepresentation: PopupDialog {
        id: dialogItem

        readonly property var pmControl: inhibitionControl

        Layout.minimumWidth: (batterymonitor.inPanel && !batterymonitor.compactInPanel) ? -1 : Kirigami.Units.gridUnit * 10
        Layout.maximumWidth: Kirigami.Units.gridUnit * 80
        Layout.preferredWidth: Kirigami.Units.gridUnit * 20

        Layout.minimumHeight: (batterymonitor.inPanel && !batterymonitor.compactInPanel) ? -1 : Kirigami.Units.gridUnit * 10
        Layout.maximumHeight: Kirigami.Units.gridUnit * 40
        Layout.preferredHeight: (batterymonitor.inPanel && !batterymonitor.compactInPanel) ? -1 : implicitHeight

        model: batteryControl

        isManuallyInhibited: inhibitionControl.isManuallyInhibited
        isManuallyInhibitedError: inhibitionControl.isManuallyInhibitedError
        isManuallySleepOnlyInhibited: inhibitionControl.isManuallySleepOnlyInhibited
        isManuallySleepOnlyInhibitedError: inhibitionControl.isManuallySleepOnlyInhibitedError
        inhibitionDurationMinutes: Plasmoid.configuration.inhibitionDurationMinutes
        inhibitionRemainingSeconds: batterymonitor.inhibitionRemainingSeconds
        pluggedIn: batteryControl.pluggedIn
        chargeStopThreshold: batteryControl.chargeStopThreshold
        remainingTime: batteryControl.remainingTime
        activeProfile: powerProfilesControl.activeProfile
        activeProfileError: powerProfilesControl.profileError
        requestedInhibitions: inhibitionControl.requestedInhibitions
        inhibitsLidAction: inhibitionControl.isLidPresent && !inhibitionControl.triggersLidAction
        profilesInstalled: powerProfilesControl.isPowerProfileDaemonInstalled
        profiles: powerProfilesControl.profiles
        inhibitionReason: powerProfilesControl.inhibitionReason
        degradationReason: powerProfilesControl.degradationReason
        profileHolds: powerProfilesControl.profileHolds
        isTlpInstalled: powerProfilesControl.isTlpInstalled

        onActivateProfileRequested: profile => {
            batterymonitor.activateProfileRequested(profile);
        }

        onInhibitionChangeRequested: inhibit => {
            batterymonitor.inhibitionChangeRequested(inhibit);
        }

        onSleepOnlyInhibitionChangeRequested: inhibit => {
            batterymonitor.sleepOnlyInhibitionChangeRequested(inhibit);
        }

        onInhibitionDurationChangeRequested: durationMinutes => {
            batterymonitor.inhibitionDurationChangeRequested(durationMinutes);
        }
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("&Show Energy Information…")
            icon.name: "documentinfo"
            visible: batterymonitor.kcmEnergyInformationAuthorized
            onTriggered: checked => KCMUtils.KCMLauncher.openInfoCenter("kcm_energyinfo")
        },
        PlasmaCore.Action {
            text: i18n("Show Battery Percentage on Icon When Not Fully Charged")
            icon.name: "format-number-percent"
            visible: batteryControl.hasBatteries
            checkable: true
            checked: Plasmoid.configuration.showPercentage
            onTriggered: checked => {
                Plasmoid.configuration.showPercentage = checked;
            }
        }
    ]

    PlasmaCore.Action {
        id: configureAction
        text: i18n("&Configure Power Management…")
        icon.name: "configure"
        onTriggered: checked => {
            KCMUtils.KCMLauncher.openSystemSettings("kcm_powerdevilprofilesconfig");
        }
    }

    Component.onCompleted: {
        if (batterymonitor.kcmAuthorized) {
            Plasmoid.setInternalAction("configure", configureAction);
        } else {
            Plasmoid.removeInternalAction("configure");
        }
    }
}
