#pragma once

#include <QObject>
#include <QPointer>

class QQmlEngine;

namespace nagi::platform {

class RuntimeIntrospection final : public QObject {
    Q_OBJECT
    Q_PROPERTY(int resourceReleaseCount READ resourceReleaseCount NOTIFY resourceReleaseCountChanged)

public:
    explicit RuntimeIntrospection(QQmlEngine *engine, QObject *parent = nullptr);

    int resourceReleaseCount() const;
    Q_INVOKABLE int topLevelWindowCount() const;
    Q_INVOKABLE bool isTopLevelWindow(QObject *object) const;
    Q_INVOKABLE void releaseUnusedQmlResources();

signals:
    void resourceReleaseCountChanged();

private:
    int resourceReleaseCount_ = 0;
    QPointer<QQmlEngine> engine_;
};

} // namespace nagi::platform
