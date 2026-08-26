#include "pointer_router.h"

#include <QCoreApplication>
#include <QQmlEngine>
#include <QQmlEngineExtensionPlugin>
#include <qqml.h>

namespace nagi::platform {
namespace {

PointerRouter *pointerRouterInstance()
{
    static auto *router = new PointerRouter;
    return router;
}

} // namespace

class PlatformPlugin final : public QQmlExtensionPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID "org.qt-project.Qt.QQmlExtensionInterface/1.0")

public:
    void registerTypes(const char *uri) override
    {
        Q_ASSERT(QByteArrayView(uri) == QByteArrayView("Nagi.Platform"));
        qmlRegisterSingletonType<PointerRouter>(
            uri, 1, 0, "PointerRouter", [](QQmlEngine *, QJSEngine *) -> QObject * {
                PointerRouter *router = pointerRouterInstance();
                QQmlEngine::setObjectOwnership(router, QQmlEngine::CppOwnership);
                return router;
            });
    }
};

} // namespace nagi::platform

#include "plugin.moc"
