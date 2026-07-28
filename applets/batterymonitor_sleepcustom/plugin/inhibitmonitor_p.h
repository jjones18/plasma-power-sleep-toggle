/*
 * SPDX-FileCopyrightText: 2024 Bohdan Onofriichuk <bogdan.onofriuchuk@gmail.com>
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#pragma once

#include <QObject>
#include <QString>
#include <qtypes.h>

class InhibitMonitor : public QObject
{
    Q_OBJECT
public:
    explicit InhibitMonitor();
    ~InhibitMonitor() override;

    static InhibitMonitor &self();

    bool getInhibit();
    bool getInhibitSleepOnly();

    void inhibit(const QString &reason, bool isSilent);
    void inhibitSleepOnly(const QString &reason, bool isSilent);
    void uninhibit(bool isSilent);
    void uninhibitSleepOnly(bool isSilent);

private:
    enum class ManualInhibitMode {
        None,
        SleepOnly,
        SleepAndLock,
    };

    void emitManualModeSignals();
    void beginSuppressingSleep(const QString &reason, bool isSilent, ManualInhibitMode successMode, bool reportSleepOnlyError);
    void stopSuppressingSleep(bool isSilent);
    void beginSuppressingScreenPowerManagement(const QString &reason, bool updateModeOnSuccess, bool reportFullErrorOnFailure);
    void stopSuppressingScreenPowerManagement();

Q_SIGNALS:
    void isManuallyInhibitedChanged(bool status);
    void isManuallyInhibitedChangeError(bool status);
    void isManuallySleepOnlyInhibitedChanged(bool status);
    void isManuallySleepOnlyInhibitedChangeError(bool status);

private:
    std::optional<uint> m_sleepInhibitionCookie;
    std::optional<uint> m_lockInhibitionCookie;
    ManualInhibitMode m_manualMode = ManualInhibitMode::None;
};
