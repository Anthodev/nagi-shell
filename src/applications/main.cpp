#define QT_NO_KEYWORDS

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSet>
#include <QStringList>
#include <QSocketNotifier>
#include <QStringDecoder>

#include <gio/gdesktopappinfo.h>
#include <gio/gio.h>

#include <algorithm>
#include <array>
#include <cerrno>
#include <fcntl.h>
#include <limits>
#include <sys/stat.h>
#include <unistd.h>

namespace {
constexpr qint64 kMaximumStoreBytes = 128 * 1024;
constexpr qsizetype kMaximumInputLineBytes = 8192;
constexpr qsizetype kMaximumApplications = 4096;
constexpr qsizetype kMaximumDesktopIdBytes = 4096;

struct StoreInspection {
    bool available = false;
    QString category = QStringLiteral("unavailable");
    QString text;
};

bool isPrivateRegularFile(const struct stat &status)
{
    return S_ISREG(status.st_mode) && status.st_uid == getuid()
        && (status.st_mode & 0777) == 0600;
}

bool validDesktopId(const QString &id)
{
    const QByteArray bytes = id.toUtf8();
    return !id.isEmpty() && id.endsWith(QStringLiteral(".desktop"))
        && bytes.size() <= kMaximumDesktopIdBytes && !bytes.contains('\0');
}

bool validExecFieldCodes(const char *exec)
{
    if (exec == nullptr || *exec == '\0') {
        return false;
    }

    constexpr char allowed[] = "fFuUick%";
    for (const char *cursor = exec; *cursor != '\0'; ++cursor) {
        if (*cursor != '%') {
            continue;
        }
        ++cursor;
        if (*cursor == '\0' || std::find(std::begin(allowed), std::end(allowed) - 1, *cursor)
                == std::end(allowed) - 1) {
            return false;
        }
    }
    return true;
}

bool validDbusActivation(GDesktopAppInfo *info, const QString &id)
{
    if (!g_desktop_app_info_get_boolean(info, G_KEY_FILE_DESKTOP_KEY_DBUS_ACTIVATABLE)) {
        return false;
    }
    const QString busName = id.chopped(QStringLiteral(".desktop").size());
    return !busName.isEmpty() && g_dbus_is_name(busName.toUtf8().constData())
        && !busName.startsWith(u':');
}

bool eligibleDesktopInfo(GDesktopAppInfo *info, const QString &id)
{
    if (info == nullptr || !validDesktopId(id) || !g_app_info_should_show(G_APP_INFO(info))) {
        return false;
    }

    const char *rawId = g_app_info_get_id(G_APP_INFO(info));
    if (rawId == nullptr || !g_utf8_validate(rawId, -1, nullptr)
        || QString::fromUtf8(rawId) != id) {
        return false;
    }

    const bool terminal =
        g_desktop_app_info_get_boolean(info, G_KEY_FILE_DESKTOP_KEY_TERMINAL);
    char *exec = g_desktop_app_info_get_string(info, G_KEY_FILE_DESKTOP_KEY_EXEC);
    const bool hasExec = exec != nullptr && *exec != '\0';
    const bool launchable =
        !terminal && (hasExec ? validExecFieldCodes(exec) : validDbusActivation(info, id));
    g_free(exec);
    return launchable;
}

QJsonObject launchApplication(qint64 requestId, const QString &id)
{
    QJsonObject response {
        {QStringLiteral("type"), QStringLiteral("launch-result")},
        {QStringLiteral("requestId"), requestId},
        {QStringLiteral("accepted"), false},
        {QStringLiteral("category"), QStringLiteral("ineligible")},
    };
    if (!validDesktopId(id)) {
        return response;
    }

    const QByteArray encodedId = id.toUtf8();
    GDesktopAppInfo *info = g_desktop_app_info_new(encodedId.constData());
    if (!eligibleDesktopInfo(info, id)) {
        if (info != nullptr) {
            g_object_unref(info);
        }
        return response;
    }

    GError *error = nullptr;
    const bool accepted = g_app_info_launch(G_APP_INFO(info), nullptr, nullptr, &error);
    g_clear_error(&error);
    g_object_unref(info);
    response.insert(QStringLiteral("accepted"), accepted);
    response.insert(QStringLiteral("category"),
                    accepted ? QStringLiteral("none") : QStringLiteral("launch"));
    return response;
}

bool discoveryPathsAccessible()
{
    QStringList roots;
    QString dataHome = qEnvironmentVariable("XDG_DATA_HOME");
    if (!dataHome.startsWith(u'/')) {
        const QString home = qEnvironmentVariable("HOME");
        dataHome = home.startsWith(u'/') ? home + QStringLiteral("/.local/share") : QString();
    }
    if (!dataHome.isEmpty()) {
        roots.append(dataHome);
    }

    const QString configuredDataDirs = qEnvironmentVariable("XDG_DATA_DIRS");
    const QStringList dataDirs = configuredDataDirs.isEmpty()
        ? QStringList {QStringLiteral("/usr/local/share"), QStringLiteral("/usr/share")}
        : configuredDataDirs.split(u':', Qt::SkipEmptyParts);
    for (const QString &dataDir : dataDirs) {
        if (dataDir.startsWith(u'/')) {
            roots.append(dataDir);
        }
    }

    for (const QString &root : roots) {
        const QByteArray path = QFile::encodeName(root + QStringLiteral("/applications"));
        struct stat status {};
        if (::stat(path.constData(), &status) != 0) {
            if (errno == ENOENT) {
                continue;
            }
            return false;
        }
        if (!S_ISDIR(status.st_mode) || ::access(path.constData(), R_OK | X_OK) != 0) {
            return false;
        }
    }
    return true;
}

QJsonObject discoveryGeneration(qint64 generation)
{
    QJsonObject response {{QStringLiteral("type"), QStringLiteral("generation")},
                          {QStringLiteral("generation"), generation},
                          {QStringLiteral("complete"), false}};
    if (!discoveryPathsAccessible()) {
        response.insert(QStringLiteral("failure"), QStringLiteral("discovery"));
        return response;
    }
    QVector<QJsonObject> records;
    QSet<QString> seen;
    GList *applications = g_app_info_get_all();

    bool valid = true;
    qsizetype count = 0;
    for (GList *node = applications; node != nullptr; node = node->next) {
        GAppInfo *appInfo = G_APP_INFO(node->data);
        if (!G_IS_DESKTOP_APP_INFO(appInfo)) {
            continue;
        }

        auto *desktopInfo = G_DESKTOP_APP_INFO(appInfo);
        const char *rawId = g_app_info_get_id(appInfo);
        if (rawId == nullptr || !g_utf8_validate(rawId, -1, nullptr)) {
            valid = false;
            break;
        }
        const QString id = QString::fromUtf8(rawId);
        if (!validDesktopId(id)) {
            valid = false;
            break;
        }
        if (seen.contains(id)) {
            valid = false;
            break;
        }
        if (!eligibleDesktopInfo(desktopInfo, id)) {
            continue;
        }

        if (++count > kMaximumApplications) {
            valid = false;
            break;
        }
        seen.insert(id);
        records.append(QJsonObject {
            {QStringLiteral("id"), id},
            {QStringLiteral("quickshellId"), id.chopped(QStringLiteral(".desktop").size())},
        });
    }
    g_list_free_full(applications, g_object_unref);

    if (!valid) {
        response.insert(QStringLiteral("failure"), QStringLiteral("discovery"));
        return response;
    }

    std::sort(records.begin(), records.end(), [](const QJsonObject &left, const QJsonObject &right) {
        return left[QStringLiteral("id")].toString().toUtf8()
            < right[QStringLiteral("id")].toString().toUtf8();
    });
    QJsonArray entries;
    for (const QJsonObject &record : records) {
        entries.append(record);
    }
    response.insert(QStringLiteral("complete"), true);
    response.insert(QStringLiteral("entries"), entries);
    return response;
}

bool ensureStoreDirectory(const QString &filePath, QString *category)
{
    const QFileInfo file(filePath);
    if (!file.isAbsolute()) {
        *category = QStringLiteral("path");
        return false;
    }

    const QString parentPath = file.absolutePath();
    if (QFileInfo(parentPath).fileName() != QStringLiteral("nagi-shell")) {
        *category = QStringLiteral("path");
        return false;
    }

    struct stat status {};
    const QByteArray nativeParent = QFile::encodeName(parentPath);
    if (::lstat(nativeParent.constData(), &status) != 0) {
        if (errno != ENOENT || !QDir().mkpath(parentPath)
            || ::chmod(nativeParent.constData(), 0700) != 0
            || ::lstat(nativeParent.constData(), &status) != 0) {
            *category = QStringLiteral("directory");
            return false;
        }
    }

    if (!S_ISDIR(status.st_mode) || status.st_uid != getuid()
        || ::access(nativeParent.constData(), W_OK | X_OK) != 0) {
        *category = QStringLiteral("directory");
        return false;
    }
    return true;
}

StoreInspection inspectStore(const QString &filePath)
{
    StoreInspection result;
    if (!ensureStoreDirectory(filePath, &result.category)) {
        return result;
    }

    const QByteArray nativePath = QFile::encodeName(filePath);
    struct stat before {};
    if (::lstat(nativePath.constData(), &before) != 0) {
        if (errno == ENOENT) {
            result.available = true;
            result.category = QStringLiteral("missing");
        } else {
            result.category = QStringLiteral("read");
        }
        return result;
    }

    if (!isPrivateRegularFile(before)) {
        result.category = S_ISLNK(before.st_mode) ? QStringLiteral("symlink")
                                                  : QStringLiteral("permissions");
        return result;
    }
    result.available = true;
    if (before.st_size > kMaximumStoreBytes) {
        result.category = QStringLiteral("oversized");
        return result;
    }

    const int descriptor = ::open(nativePath.constData(), O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (descriptor < 0) {
        result.available = false;
        result.category = QStringLiteral("read");
        return result;
    }

    struct stat after {};
    QByteArray bytes;
    bytes.resize(static_cast<qsizetype>(before.st_size));
    qsizetype offset = 0;
    while (offset < bytes.size()) {
        const ssize_t readCount = ::read(descriptor, bytes.data() + offset,
                                         static_cast<size_t>(bytes.size() - offset));
        if (readCount <= 0) {
            result.available = false;
            result.category = QStringLiteral("read");
            break;
        }
        offset += readCount;
    }
    const bool stable = ::fstat(descriptor, &after) == 0 && isPrivateRegularFile(after)
        && before.st_dev == after.st_dev && before.st_ino == after.st_ino
        && after.st_size == before.st_size;
    ::close(descriptor);
    if (!result.available || !stable) {
        result.available = false;
        result.category = QStringLiteral("read");
        result.text.clear();
        return result;
    }

    QStringDecoder decoder(QStringDecoder::Utf8);
    result.text = decoder.decode(bytes);
    if (decoder.hasError()) {
        result.text.clear();
        result.category = QStringLiteral("utf8");
        return result;
    }
    result.category = bytes.isEmpty() ? QStringLiteral("empty") : QStringLiteral("loaded");
    return result;
}

bool prepareWrite(const QString &filePath, QString *category)
{
    if (!ensureStoreDirectory(filePath, category)) {
        return false;
    }

    const QByteArray nativePath = QFile::encodeName(filePath);
    struct stat status {};
    if (::lstat(nativePath.constData(), &status) == 0) {
        if (!isPrivateRegularFile(status)) {
            *category = S_ISLNK(status.st_mode) ? QStringLiteral("symlink")
                                                : QStringLiteral("permissions");
            return false;
        }
        if (::access(nativePath.constData(), W_OK) != 0) {
            *category = QStringLiteral("write");
            return false;
        }
        return true;
    }
    if (errno != ENOENT) {
        *category = QStringLiteral("write");
        return false;
    }

    const int descriptor = ::open(nativePath.constData(), O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC
                                      | O_NOFOLLOW,
                                  0600);
    if (descriptor < 0) {
        *category = QStringLiteral("write");
        return false;
    }
    const bool secured = ::fchmod(descriptor, 0600) == 0;
    ::close(descriptor);
    if (!secured) {
        *category = QStringLiteral("permissions");
        return false;
    }
    return true;
}

bool verifyWrite(const QString &filePath, QString *category)
{
    const StoreInspection inspection = inspectStore(filePath);
    if (!inspection.available || inspection.category == QStringLiteral("oversized")) {
        *category = inspection.category;
        return false;
    }
    return true;
}

QJsonObject storeJson(const StoreInspection &inspection)
{
    QJsonObject store {{QStringLiteral("available"), inspection.available},
                       {QStringLiteral("category"), inspection.category}};
    if (inspection.category == QStringLiteral("loaded")
        || inspection.category == QStringLiteral("empty")) {
        store.insert(QStringLiteral("text"), inspection.text);
    }
    return store;
}

class Helper final : public QObject {
public:
    Helper(QString pinsPath, QString recencyPath, QObject *parent = nullptr)
        : QObject(parent)
        , m_pinsPath(std::move(pinsPath))
        , m_recencyPath(std::move(recencyPath))
        , m_input()
        , m_output()
        , m_notifier(STDIN_FILENO, QSocketNotifier::Read, this)
    {
        if (!m_input.open(STDIN_FILENO, QIODevice::ReadOnly, QFileDevice::DontCloseHandle)
            || !m_output.open(STDOUT_FILENO, QIODevice::WriteOnly, QFileDevice::DontCloseHandle)) {
            QCoreApplication::exit(2);
            return;
        }
        connect(&m_notifier, &QSocketNotifier::activated, this, [this] { readInput(); });

        write(QJsonObject {
            {QStringLiteral("type"), QStringLiteral("initialized")},
            {QStringLiteral("stores"),
             QJsonObject {{QStringLiteral("pins"), storeJson(inspectStore(m_pinsPath))},
                          {QStringLiteral("recency"), storeJson(inspectStore(m_recencyPath))}}},
        });
    }

private:
    void write(const QJsonObject &message)
    {
        m_output.write(QJsonDocument(message).toJson(QJsonDocument::Compact));
        m_output.write("\n");
        m_output.flush();
    }

    void readInput()
    {
        std::array<char, kMaximumInputLineBytes> bytes {};
        const ssize_t count = ::read(STDIN_FILENO, bytes.data(), bytes.size());
        if (count == 0) {
            QCoreApplication::quit();
            return;
        }
        if (count < 0) {
            if (errno != EINTR && errno != EAGAIN) {
                QCoreApplication::exit(2);
            }
            return;
        }
        m_buffer.append(bytes.data(), count);
        if (m_buffer.size() > kMaximumInputLineBytes && !m_buffer.contains('\n')) {
            QCoreApplication::exit(2);
            return;
        }

        qsizetype newline = -1;
        while ((newline = m_buffer.indexOf('\n')) >= 0) {
            const QByteArray line = m_buffer.first(newline);
            m_buffer.remove(0, newline + 1);
            if (line.isEmpty() || line.size() > kMaximumInputLineBytes) {
                write(QJsonObject {{QStringLiteral("type"), QStringLiteral("error")},
                                   {QStringLiteral("category"), QStringLiteral("protocol")}});
                continue;
            }
            QJsonParseError error {};
            const QJsonDocument document = QJsonDocument::fromJson(line, &error);
            if (error.error != QJsonParseError::NoError || !document.isObject()) {
                write(QJsonObject {{QStringLiteral("type"), QStringLiteral("error")},
                                   {QStringLiteral("category"), QStringLiteral("protocol")}});
                continue;
            }
            handle(document.object());
        }
    }

    void handle(const QJsonObject &command)
    {
        const QString operation = command.value(QStringLiteral("op")).toString();
        if (operation == QStringLiteral("shutdown")) {
            QCoreApplication::quit();
            return;
        }
        if (operation == QStringLiteral("scan")) {
            const QJsonValue value = command.value(QStringLiteral("generation"));
            const qint64 generation = value.isDouble() ? value.toInteger(-1) : -1;
            if (generation < 0 || generation > std::numeric_limits<int>::max()) {
                write(QJsonObject {{QStringLiteral("type"), QStringLiteral("error")},
                                   {QStringLiteral("category"), QStringLiteral("protocol")}});
            } else {
                write(discoveryGeneration(generation));
            }
            return;
        }
        if (operation == QStringLiteral("launch")) {
            const qint64 requestId =
                command.value(QStringLiteral("requestId")).toInteger(-1);
            const QString desktopFileId =
                command.value(QStringLiteral("desktopFileId")).toString();
            if (requestId <= 0 || requestId > std::numeric_limits<int>::max()
                || !validDesktopId(desktopFileId)) {
                write(QJsonObject {{QStringLiteral("type"), QStringLiteral("error")},
                                   {QStringLiteral("category"), QStringLiteral("protocol")}});
            } else {
                write(launchApplication(requestId, desktopFileId));
            }
            return;
        }
        if (operation == QStringLiteral("prepare-write")
            || operation == QStringLiteral("verify-write")) {
            const QString store = command.value(QStringLiteral("store")).toString();
            const qint64 serial = command.value(QStringLiteral("serial")).toInteger(-1);
            const QString *path = store == QStringLiteral("pins") ? &m_pinsPath
                : store == QStringLiteral("recency")             ? &m_recencyPath
                                                                  : nullptr;
            QString category = QStringLiteral("protocol");
            const bool success = path != nullptr && serial >= 0
                && (operation == QStringLiteral("prepare-write") ? prepareWrite(*path, &category)
                                                                  : verifyWrite(*path, &category));
            write(QJsonObject {
                {QStringLiteral("type"),
                 operation == QStringLiteral("prepare-write") ? QStringLiteral("write-ready")
                                                               : QStringLiteral("write-verified")},
                {QStringLiteral("store"), store},
                {QStringLiteral("serial"), serial},
                {QStringLiteral("success"), success},
                {QStringLiteral("category"), success ? QStringLiteral("none") : category},
            });
            return;
        }

        write(QJsonObject {{QStringLiteral("type"), QStringLiteral("error")},
                           {QStringLiteral("category"), QStringLiteral("protocol")}});
    }

    QString m_pinsPath;
    QString m_recencyPath;
    QFile m_input;
    QFile m_output;
    QSocketNotifier m_notifier;
    QByteArray m_buffer;
};
}

int main(int argc, char **argv)
{
    QCoreApplication application(argc, argv);
    if (application.arguments().size() != 3) {
        return 2;
    }

    Helper helper(application.arguments().at(1), application.arguments().at(2));
    return application.exec();
}
