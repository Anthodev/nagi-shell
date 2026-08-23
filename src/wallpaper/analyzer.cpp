#include "analyzer.h"

#include <QColor>
#include <QCryptographicHash>
#include <QFile>
#include <QFileInfo>
#include <QImage>
#include <QImageReader>
#include <QSize>

#include <array>
#include <cmath>

namespace nagi::wallpaper {
namespace {

constexpr int HueBinCount = 24;
constexpr double MinimumSaturation = 0.30;
constexpr double MinimumLuminance = 0.08;
constexpr double MaximumLuminance = 0.82;
constexpr double MinimumValue = 0.20;
constexpr double MaximumValue = 0.97;
constexpr double MinimumEligibleFraction = 0.01;

struct HueBin {
    double weight = 0;
    double red = 0;
    double green = 0;
    double blue = 0;
    int count = 0;
};

double linearChannel(double channel)
{
    channel /= 255.0;
    return channel <= 0.04045 ? channel / 12.92 : std::pow((channel + 0.055) / 1.055, 2.4);
}

double luminance(const QColor &color)
{
    return 0.2126 * linearChannel(color.red()) + 0.7152 * linearChannel(color.green())
        + 0.0722 * linearChannel(color.blue());
}

AnalysisResult reject(const char *status)
{
    return {false, {}, QString::fromLatin1(status)};
}

AnalysisResult chooseAccent(const QImage &source, const std::function<bool()> &cancelled)
{
    const QImage image = source.convertToFormat(QImage::Format_RGB32);
    if (image.isNull()) {
        return reject("Malformed");
    }

    std::array<HueBin, HueBinCount> bins{};
    const int totalPixels = image.width() * image.height();
    int eligiblePixels = 0;

    for (int y = 0; y < image.height(); ++y) {
        if (cancelled && cancelled()) {
            return reject("Cancelled");
        }
        const auto *row = reinterpret_cast<const QRgb *>(image.constScanLine(y));
        for (int x = 0; x < image.width(); ++x) {
            const QColor color(row[x]);
            float hue = 0;
            float saturation = 0;
            float value = 0;
            color.getHsvF(&hue, &saturation, &value);
            const double light = luminance(color);
            if (hue < 0 || saturation < MinimumSaturation || value < MinimumValue
                || value > MaximumValue || light < MinimumLuminance || light > MaximumLuminance) {
                continue;
            }

            const int index = std::min(HueBinCount - 1, static_cast<int>(hue * HueBinCount));
            const double lightBalance = 1.0 - std::min(1.0, std::abs(light - 0.45) / 0.45);
            const double weight = saturation * saturation * (0.35 + 0.65 * lightBalance);
            HueBin &bin = bins[static_cast<size_t>(index)];
            bin.weight += weight;
            bin.red += color.red() * weight;
            bin.green += color.green() * weight;
            bin.blue += color.blue() * weight;
            bin.count += 1;
            eligiblePixels += 1;
        }
    }

    if (eligiblePixels < std::max(1, static_cast<int>(std::ceil(totalPixels * MinimumEligibleFraction)))) {
        return reject("Unsuitable");
    }

    const HueBin *selected = &bins.front();
    for (const HueBin &bin : bins) {
        if (bin.weight > selected->weight) {
            selected = &bin;
        }
    }
    if (selected->weight <= 0 || selected->count == 0) {
        return reject("Unsuitable");
    }

    const QColor accent(
        qBound(0, qRound(selected->red / selected->weight), 255),
        qBound(0, qRound(selected->green / selected->weight), 255),
        qBound(0, qRound(selected->blue / selected->weight), 255));
    return {true, accent.name(QColor::HexRgb).toUpper(), QStringLiteral("Ready")};
}

} // namespace

FingerprintResult fingerprintSource(const QString &path, const std::function<bool()> &cancelled)
{
    const QFileInfo info(path);
    if (!info.exists() || !info.isFile()) {
        return {reject("Missing"), {}};
    }
    if (!info.isReadable()) {
        return {reject("Unreadable"), {}};
    }
    if (info.size() <= 0 || info.size() > MaximumImageBytes) {
        return {reject("Oversized"), {}};
    }

    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        return {reject("Unreadable"), {}};
    }
    QCryptographicHash hash(QCryptographicHash::Sha256);
    std::array<char, 64 * 1024> buffer{};
    while (!file.atEnd()) {
        if (cancelled && cancelled()) {
            return {reject("Cancelled"), {}};
        }
        const qint64 count = file.read(buffer.data(), static_cast<qint64>(buffer.size()));
        if (count <= 0) {
            return {reject("Unreadable"), {}};
        }
        hash.addData(QByteArrayView(buffer.data(), count));
    }
    if (cancelled && cancelled()) {
        return {reject("Cancelled"), {}};
    }
    return {{true, {}, QStringLiteral("Verified")}, hash.result()};
}

SourceResult analyzeVerifiedSource(
    const QString &path,
    const QByteArray &expectedDigest,
    const std::function<bool()> &cancelled,
    const std::function<void()> &extractionStarted)
{
    const FingerprintResult initial = fingerprintSource(path, cancelled);
    if (!initial.validation.accepted) {
        return {initial.validation, {}};
    }
    if (initial.digest != expectedDigest) {
        return {reject("Changed"), initial.digest};
    }
    if (extractionStarted) {
        extractionStarted();
    }
    if (cancelled && cancelled()) {
        return {reject("Cancelled"), {}};
    }

    QImageReader reader(path);
    reader.setDecideFormatFromContent(true);
    if (!reader.canRead() || reader.supportsAnimation()) {
        return {reject(reader.supportsAnimation() ? "Unsupported" : "Malformed"), expectedDigest};
    }
    const QSize originalSize = reader.size();
    if (!originalSize.isValid() || originalSize.isEmpty()) {
        return {reject("Malformed"), expectedDigest};
    }
    if (originalSize.width() > MaximumDecodeEdge || originalSize.height() > MaximumDecodeEdge) {
        reader.setScaledSize(originalSize.scaled(
            QSize(MaximumDecodeEdge, MaximumDecodeEdge), Qt::KeepAspectRatio));
    }
    const QImage image = reader.read();
    if (image.isNull() || image.width() > MaximumDecodeEdge || image.height() > MaximumDecodeEdge) {
        return {reject("Malformed"), expectedDigest};
    }
    const AnalysisResult analysis = chooseAccent(image, cancelled);
    if (analysis.status == QStringLiteral("Cancelled")) {
        return {analysis, {}};
    }

    const FingerprintResult confirmed = fingerprintSource(path, cancelled);
    if (!confirmed.validation.accepted) {
        return {confirmed.validation, {}};
    }
    if (confirmed.digest != expectedDigest) {
        return {reject("Changed"), confirmed.digest};
    }
    return {analysis, expectedDigest};
}

SourceResult analyzeSource(
    const QString &path,
    const std::function<bool()> &cancelled,
    const std::function<void()> &extractionStarted)
{
    const FingerprintResult fingerprint = fingerprintSource(path, cancelled);
    if (!fingerprint.validation.accepted) {
        return {fingerprint.validation, {}};
    }
    return analyzeVerifiedSource(path, fingerprint.digest, cancelled, extractionStarted);
}

} // namespace nagi::wallpaper
