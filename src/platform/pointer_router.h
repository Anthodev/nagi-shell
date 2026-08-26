#pragma once

#include <QObject>

namespace nagi::platform {

class PointerRouter final : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool available READ available CONSTANT)

public:
    explicit PointerRouter(QObject *parent = nullptr);

    [[nodiscard]] bool available() const;
    Q_INVOKABLE [[nodiscard]] bool isPointerOnWindowScreen(QObject *windowObject) const;
};

} // namespace nagi::platform
