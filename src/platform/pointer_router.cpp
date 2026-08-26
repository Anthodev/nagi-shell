#include "pointer_router.h"

#include <QCursor>
#include <QGuiApplication>
#include <QScreen>
#include <QWindow>

namespace nagi::platform {

PointerRouter::PointerRouter(QObject *parent)
    : QObject(parent)
{
}

bool PointerRouter::available() const
{
    return qobject_cast<QGuiApplication *>(QCoreApplication::instance()) != nullptr;
}

bool PointerRouter::isPointerOnWindowScreen(QObject *windowObject) const
{
    const auto *window = qobject_cast<QWindow *>(windowObject);
    if (window == nullptr || window->screen() == nullptr || !available()) {
        return false;
    }

    return QGuiApplication::screenAt(QCursor::pos()) == window->screen();
}

} // namespace nagi::platform
