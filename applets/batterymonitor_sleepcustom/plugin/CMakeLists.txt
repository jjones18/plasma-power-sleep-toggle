# SPDX-FileCopyrightText: 2024 Bohdan Onofriichuk <bogdan.onofriuchuk@gmail.com>
# SPDX-License-Identifier: BSD-3-Clause

ecm_add_qml_module(batterymonitor_sleepcustomplugin URI org.kde.plasma.private.batterymonitor.sleepcustom GENERATE_PLUGIN_SOURCE)

target_sources(batterymonitor_sleepcustomplugin PRIVATE
        powerprofilescontrol.cpp powerprofilescontrol.h
        inhibitioncontrol.cpp inhibitioncontrol.h
        applicationdata_p.cpp applicationdata_p.h
        inhibitmonitor_p.cpp inhibitmonitor_p.h
)

target_link_libraries(batterymonitor_sleepcustomplugin PRIVATE
        Qt::Core
        Qt::DBus
        Qt::Qml
        Qt::Gui
        KF6::Service
        KF6::I18n
)

ecm_qt_declare_logging_category(batterymonitor_sleepcustomplugin
        HEADER "batterymonitor_debug.h"
        IDENTIFIER "APPLETS::BATTERYMONITOR"
        CATEGORY_NAME org.kde.applets.batterymonitor
        DEFAULT_SEVERITY Warning
        DESCRIPTION "Battery Monitor applet" EXPORT "APPLETS::BATTERYMONITOR"
)

ecm_finalize_qml_module(batterymonitor_sleepcustomplugin)
