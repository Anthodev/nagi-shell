#include "notification_text.h"

#include <QXmlStreamReader>

namespace nagi::notifications {
namespace {

constexpr qsizetype MaxMarkupCodeUnits = 65'536;

bool isControl(uint codePoint)
{
    return codePoint == 0 || codePoint <= 0x1f || (codePoint >= 0x7f && codePoint <= 0x9f);
}

void appendCodePoint(QString &output, uint codePoint)
{
    if (codePoint <= 0xffff) {
        output.append(QChar(static_cast<ushort>(codePoint)));
        return;
    }

    output.append(QChar::highSurrogate(codePoint));
    output.append(QChar::lowSurrogate(codePoint));
}

int utf8Length(uint codePoint)
{
    if (codePoint <= 0x7f) {
        return 1;
    }
    if (codePoint <= 0x7ff) {
        return 2;
    }
    if (codePoint <= 0xffff) {
        return 3;
    }
    return 4;
}

QString boundedNormalized(const QString &value, qsizetype maxUtf8Bytes, bool preserveBodyWhitespace)
{
    QString output;
    output.reserve(qMin(value.size(), maxUtf8Bytes));
    qsizetype bytes = 0;

    for (qsizetype index = 0; index < value.size();) {
        uint codePoint = value.at(index).unicode();
        qsizetype consumed = 1;
        if (QChar::isHighSurrogate(codePoint) && index + 1 < value.size()
            && QChar::isLowSurrogate(value.at(index + 1).unicode())) {
            codePoint = QChar::surrogateToUcs4(value.at(index), value.at(index + 1));
            consumed = 2;
        } else if (QChar::isSurrogate(codePoint)) {
            codePoint = 0xfffd;
        }

        if (codePoint == '\r') {
            codePoint = '\n';
            if (index + consumed < value.size() && value.at(index + consumed) == QLatin1Char('\n')) {
                ++consumed;
            }
        } else if (isControl(codePoint)
                   && !(preserveBodyWhitespace && (codePoint == '\t' || codePoint == '\n'))) {
            codePoint = 0xfffd;
        }

        const int encodedBytes = utf8Length(codePoint);
        if (bytes + encodedBytes > maxUtf8Bytes) {
            break;
        }
        appendCodePoint(output, codePoint);
        bytes += encodedBytes;
        index += consumed;
    }

    return output;
}

QString stripTagSpans(const QString &value)
{
    QString output;
    output.reserve(qMin(value.size(), MaxMarkupCodeUnits));
    bool inTag = false;
    const qsizetype limit = qMin(value.size(), MaxMarkupCodeUnits);
    for (qsizetype index = 0; index < limit; ++index) {
        const QChar character = value.at(index);
        if (!inTag && character == QLatin1Char('<')) {
            inTag = true;
            continue;
        }
        if (inTag) {
            if (character == QLatin1Char('>')) {
                inTag = false;
            }
            continue;
        }
        output.append(character);
    }
    return output;
}

QString extractMarkupText(const QString &value)
{
    const QString boundedSource = value.left(MaxMarkupCodeUnits);
    QXmlStreamReader reader(QStringLiteral("<nagi-root>") + boundedSource
                            + QStringLiteral("</nagi-root>"));
    QString output;
    output.reserve(qMin(boundedSource.size(), qsizetype(4096)));
    bool unsafeMarkup = false;

    while (!reader.atEnd()) {
        const auto token = reader.readNext();
        if (token == QXmlStreamReader::DTD || token == QXmlStreamReader::EntityReference
            || token == QXmlStreamReader::ProcessingInstruction) {
            unsafeMarkup = true;
            break;
        }
        if (token == QXmlStreamReader::Characters) {
            output.append(reader.text());
            continue;
        }
        if (token == QXmlStreamReader::StartElement
            && reader.name().compare(QLatin1String("img"), Qt::CaseInsensitive) == 0) {
            output.append(reader.attributes().value(QLatin1String("alt")));
        }
    }

    if (unsafeMarkup || reader.hasError()) {
        return stripTagSpans(boundedSource);
    }
    return output;
}

bool containsForbiddenKeyCharacter(const QString &value)
{
    for (const QChar character : value) {
        const uint codePoint = character.unicode();
        if (isControl(codePoint) || character == QLatin1Char('/') || character == QLatin1Char('\\')
            || character == QLatin1Char(':')) {
            return true;
        }
    }
    return false;
}

} // namespace

QString normalizePlainText(const QString &value, qsizetype maxUtf8Bytes, bool preserveBodyWhitespace)
{
    return boundedNormalized(value, maxUtf8Bytes, preserveBodyWhitespace);
}

QString normalizeBody(const QString &value)
{
    return boundedNormalized(extractMarkupText(value), 4096, true);
}

QString normalizeDesktopEntry(const QString &value)
{
    if (value.isEmpty() || containsForbiddenKeyCharacter(value)) {
        return {};
    }
    return boundedNormalized(value, 512, false);
}

QString normalizeIconName(const QString &value)
{
    if (value.isEmpty() || value.startsWith(QLatin1Char('.')) || containsForbiddenKeyCharacter(value)) {
        return {};
    }
    return boundedNormalized(value, 512, false);
}

} // namespace nagi::notifications
