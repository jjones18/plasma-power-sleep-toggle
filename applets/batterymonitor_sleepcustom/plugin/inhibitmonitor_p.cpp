/*
 * SPDX-FileCopyrightText: 2024 Bohdan Onofriichuk <bogdan.onofriuchuk@gmail.com>
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#include "inhibitmonitor_p.h"

#include <QDBusConnectionInterface>
#include <QDBusInterface>
#include <QDBusMetaType>
#include <QDBusReply>
#include <QGuiApplication>

InhibitMonitor &InhibitMonitor::self()
{
    static InhibitMonitor inhibitMonitor;
    return inhibitMonitor;
}

InhibitMonitor::InhibitMonitor()
{
}

InhibitMonitor::~InhibitMonitor()
{
    if (m_sleepInhibitionCookie) {
        stopSuppressingSleep(true);
    }
    if (m_lockInhibitionCookie) {
        stopSuppressingScreenPowerManagement();
    }
}

bool InhibitMonitor::getInhibit()
{
    return m_manualMode == ManualInhibitMode::SleepAndLock;
}

bool InhibitMonitor::getInhibitSleepOnly()
{
    return m_manualMode == ManualInhibitMode::SleepOnly;
}

void InhibitMonitor::emitManualModeSignals()
{
    Q_EMIT isManuallyInhibitedChanged(getInhibit());
    Q_EMIT isManuallySleepOnlyInhibitedChanged(getInhibitSleepOnly());
}

void InhibitMonitor::inhibit(const QString &reason, bool isSilent)
{
    if (m_manualMode == ManualInhibitMode::SleepAndLock) {
        emitManualModeSignals();
        return;
    }

    if (m_manualMode == ManualInhibitMode::SleepOnly && m_sleepInhibitionCookie) {
        beginSuppressingScreenPowerManagement(reason, true, true);
        return;
    }

    beginSuppressingSleep(reason, isSilent, ManualInhibitMode::SleepAndLock, false);
    beginSuppressingScreenPowerManagement(reason, false, true);
}

void InhibitMonitor::inhibitSleepOnly(const QString &reason, bool isSilent)
{
    if (m_manualMode == ManualInhibitMode::SleepOnly) {
        emitManualModeSignals();
        return;
    }

    if (m_manualMode == ManualInhibitMode::SleepAndLock) {
        emitManualModeSignals();
        return;
    }

    beginSuppressingSleep(reason, isSilent, ManualInhibitMode::SleepOnly, true);
}

void InhibitMonitor::uninhibit(bool isSilent)
{
    stopSuppressingSleep(isSilent);
    stopSuppressingScreenPowerManagement();
}

void InhibitMonitor::uninhibitSleepOnly(bool isSilent)
{
    if (m_manualMode != ManualInhibitMode::SleepOnly) {
        emitManualModeSignals();
        return;
    }

    stopSuppressingSleep(isSilent);
}

void InhibitMonitor::beginSuppressingSleep(const QString &reason, bool isSilent, ManualInhibitMode successMode, bool reportSleepOnlyError)
{
    qDebug() << "Begin Suppressing sleep signal arrived";
    if (m_sleepInhibitionCookie) {
        if (successMode == ManualInhibitMode::SleepOnly && !m_lockInhibitionCookie) {
            m_manualMode = ManualInhibitMode::SleepOnly;
            emitManualModeSignals();
        }
        return;
    }

    QDBusMessage msg = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.PowerManagement.Inhibit"),
                                                      QStringLiteral("/org/freedesktop/PowerManagement/Inhibit"),
                                                      QStringLiteral("org.freedesktop.PowerManagement.Inhibit"),
                                                      QStringLiteral("Inhibit"));
    msg << QGuiApplication::desktopFileName() << reason;
    QDBusPendingCall call = QDBusConnection::sessionBus().asyncCall(msg);
    auto *watcher = new QDBusPendingCallWatcher(call, this);

    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, isSilent, successMode, reportSleepOnlyError](QDBusPendingCallWatcher *watcher) {
        QDBusReply<uint> reply = *watcher;
        if (reply.isValid()) {
            m_sleepInhibitionCookie = reply.value();
            if (!isSilent) {
                qDebug() << "Begin Suppressing sleep signal is used";
                QDBusMessage osdMsg = QDBusMessage::createMethodCall(QStringLiteral("org.kde.plasmashell"),
                                                                     QStringLiteral("/org/kde/osdService"),
                                                                     QStringLiteral("org.kde.osdService"),
                                                                     QStringLiteral("powerManagementInhibitedChanged"));
                osdMsg << true;
                QDBusConnection::sessionBus().asyncCall(osdMsg);
            }
            m_manualMode = successMode;
            emitManualModeSignals();
        } else {
            if (reportSleepOnlyError) {
                Q_EMIT isManuallySleepOnlyInhibitedChangeError(false);
            } else {
                Q_EMIT isManuallyInhibitedChangeError(false);
            }
        }
        watcher->deleteLater();
    });
}

void InhibitMonitor::stopSuppressingSleep(bool isSilent)
{
    qDebug() << "Stop Suppressing sleep signal arrived";
    if (!m_sleepInhibitionCookie) {
        m_manualMode = ManualInhibitMode::None;
        emitManualModeSignals();
        return;
    }

    QDBusMessage msg = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.PowerManagement.Inhibit"),
                                                      QStringLiteral("/org/freedesktop/PowerManagement/Inhibit"),
                                                      QStringLiteral("org.freedesktop.PowerManagement.Inhibit"),
                                                      QStringLiteral("UnInhibit"));
    msg << m_sleepInhibitionCookie.value();
    QDBusPendingCall call = QDBusConnection::sessionBus().asyncCall(msg);
    auto *watcher = new QDBusPendingCallWatcher(call, this);

    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, isSilent](QDBusPendingCallWatcher *watcher) {
        QDBusReply<void> reply = *watcher;
        if (reply.isValid()) {
            m_sleepInhibitionCookie.reset();
            if (!isSilent) {
                qDebug() << "Stop Suppressing sleep signal is used";
                QDBusMessage osdMsg = QDBusMessage::createMethodCall(QStringLiteral("org.kde.plasmashell"),
                                                                     QStringLiteral("/org/kde/osdService"),
                                                                     QStringLiteral("org.kde.osdService"),
                                                                     QStringLiteral("powerManagementInhibitedChanged"));
                osdMsg << false;
                QDBusConnection::sessionBus().asyncCall(osdMsg);
            }
            m_manualMode = ManualInhibitMode::None;
            emitManualModeSignals();
        } else {
            if (m_manualMode == ManualInhibitMode::SleepOnly) {
                Q_EMIT isManuallySleepOnlyInhibitedChangeError(true);
            } else {
                Q_EMIT isManuallyInhibitedChangeError(true);
            }
        }
        watcher->deleteLater();
    });
}

void InhibitMonitor::beginSuppressingScreenPowerManagement(const QString &reason, bool updateModeOnSuccess, bool reportFullErrorOnFailure)
{
    if (m_lockInhibitionCookie) {
        if (updateModeOnSuccess) {
            m_manualMode = ManualInhibitMode::SleepAndLock;
            emitManualModeSignals();
        }
        return;
    }

    QDBusMessage msg = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.ScreenSaver"),
                                                      QStringLiteral("/ScreenSaver"),
                                                      QStringLiteral("org.freedesktop.ScreenSaver"),
                                                      QStringLiteral("Inhibit"));
    msg << QGuiApplication::desktopFileName() << reason;
    QDBusPendingCall call = QDBusConnection::sessionBus().asyncCall(msg);
    auto *watcher = new QDBusPendingCallWatcher(call, this);

    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, updateModeOnSuccess, reportFullErrorOnFailure](QDBusPendingCallWatcher *watcher) {
        QDBusReply<uint> reply = *watcher;
        if (reply.isValid()) {
            m_lockInhibitionCookie = reply.value();
            if (updateModeOnSuccess) {
                m_manualMode = ManualInhibitMode::SleepAndLock;
                emitManualModeSignals();
            }
        } else if (reportFullErrorOnFailure) {
            Q_EMIT isManuallyInhibitedChangeError(false);
        }
        watcher->deleteLater();
    });
}

void InhibitMonitor::stopSuppressingScreenPowerManagement()
{
    if (!m_lockInhibitionCookie) {
        return;
    }

    QDBusMessage msg = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.ScreenSaver"),
                                                      QStringLiteral("/ScreenSaver"),
                                                      QStringLiteral("org.freedesktop.ScreenSaver"),
                                                      QStringLiteral("UnInhibit"));
    msg << m_lockInhibitionCookie.value();
    QDBusPendingCall call = QDBusConnection::sessionBus().asyncCall(msg);
    auto *watcher = new QDBusPendingCallWatcher(call, this);

    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *watcher) {
        QDBusReply<void> reply = *watcher;
        if (reply.isValid()) {
            m_lockInhibitionCookie.reset();
        }
        watcher->deleteLater();
    });
}

#include "moc_inhibitmonitor_p.cpp"
