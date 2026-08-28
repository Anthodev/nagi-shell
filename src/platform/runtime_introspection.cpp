#include "runtime_introspection.h"

#include <QGuiApplication>
#if defined(__GLIBC__)
#include <malloc.h>
#endif

#include <QWindow>
#include <QQmlEngine>
#include <QTimer>

namespace nagi::platform {

RuntimeIntrospection::RuntimeIntrospection(QQmlEngine *engine, QObject *parent)
    : QObject(parent)
    , engine_(engine)
{
}

int RuntimeIntrospection::topLevelWindowCount() const
{
    return static_cast<int>(QGuiApplication::topLevelWindows().size());
}

bool RuntimeIntrospection::isTopLevelWindow(QObject *object) const
{
    auto *window = qobject_cast<QWindow *>(object);
    return window && QGuiApplication::topLevelWindows().contains(window);
}

int RuntimeIntrospection::resourceReleaseCount() const
{
    return resourceReleaseCount_;
}

void RuntimeIntrospection::releaseUnusedQmlResources()
{
    if (!engine_) {
        return;
    }
    ++resourceReleaseCount_;
    emit resourceReleaseCountChanged();
    engine_->collectGarbage();
    QPointer<QQmlEngine> engine = engine_;
    QTimer::singleShot(0, engine_, [engine]() {
        if (!engine) {
            return;
        }
        engine->trimComponentCache();
        engine->collectGarbage();
#if defined(__GLIBC__)
        malloc_trim(0);
#endif
    });
}

} // namespace nagi::platform
