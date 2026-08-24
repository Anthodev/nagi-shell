#pragma once

#include <QKeySequence>
#include <QList>

inline QList<QKeySequence> initialShortcutProposal(const QList<QKeySequence> &persisted,
                                                    const QKeySequence &preferred,
                                                    bool preferredAvailable)
{
    if (!persisted.isEmpty()) {
        return persisted;
    }
    return preferredAvailable ? QList<QKeySequence> {preferred} : QList<QKeySequence> {};
}
