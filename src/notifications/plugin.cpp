#include "runtime.h"

#include <QCoreApplication>
#include <QQmlEngine>
#include <QQmlEngineExtensionPlugin>
#include <qqml.h>

namespace nagi::notifications {
namespace {

NotificationRuntime *runtimeInstance()
{
    // Quickshell replaces QML engines during live reload. C++ ownership keeps
    // deadlines and private live associations scoped to the process instead.
    static auto *runtime = [] {
        auto *instance = new NotificationRuntime;
        if (QCoreApplication::instance() != nullptr
            && instance->thread() != QCoreApplication::instance()->thread()) {
            instance->moveToThread(QCoreApplication::instance()->thread());
        }
        return instance;
    }();
    return runtime;
}

} // namespace

class NotificationsPlugin final : public QQmlExtensionPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID "org.qt-project.Qt.QQmlExtensionInterface/1.0")

public:
    void registerTypes(const char *uri) override
    {
        Q_ASSERT(QByteArrayView(uri) == QByteArrayView("Nagi.Notifications"));
        qmlRegisterSingletonType<NotificationRuntime>(
            uri, 1, 0, "NotificationRuntime",
            [](QQmlEngine *, QJSEngine *) -> QObject * {
                NotificationRuntime *runtime = runtimeInstance();
                QQmlEngine::setObjectOwnership(runtime, QQmlEngine::CppOwnership);
                return runtime;
            });
    }
};

} // namespace nagi::notifications

#include "plugin.moc"
