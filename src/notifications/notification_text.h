#pragma once

#include <QString>

namespace nagi::notifications {

QString normalizePlainText(const QString &value, qsizetype maxUtf8Bytes, bool preserveBodyWhitespace);
QString normalizeBody(const QString &value);
QString normalizeDesktopEntry(const QString &value);
QString normalizeIconName(const QString &value);

} // namespace nagi::notifications
