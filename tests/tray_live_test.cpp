#include <QAction>
#include <QApplication>
#include <QColor>
#include <QIcon>
#include <QMenu>
#include <QPainter>
#include <QProcess>
#include <QSystemTrayIcon>
#include <QTimer>

#include <iostream>

namespace {

QIcon icon(const QColor &color)
{
    QPixmap pixmap(32, 32);
    pixmap.fill(Qt::transparent);
    QPainter painter(&pixmap);
    painter.setRenderHint(QPainter::Antialiasing);
    painter.setPen(Qt::NoPen);
    painter.setBrush(color);
    painter.drawEllipse(3, 3, 26, 26);
    return QIcon(pixmap);
}

int runItem(QApplication &application)
{
    QApplication::setApplicationName(QStringLiteral("Nagi Tray Integration Test"));
    QApplication::setQuitOnLastWindowClosed(false);
    if (!QSystemTrayIcon::isSystemTrayAvailable()) {
        std::cerr << "system tray unavailable\n";
        return 3;
    }

    bool activated = false;
    bool menuExposed = false;

    QMenu menu;
    QAction action(QStringLiteral("Invoke controlled tray action"), &menu);
    menu.addAction(&action);

    QSystemTrayIcon tray(icon(QColor(QStringLiteral("#7aa2f7"))));
    tray.setToolTip(QStringLiteral("Nagi tray initial"));
    tray.setContextMenu(&menu);

    QObject::connect(&tray, &QSystemTrayIcon::activated, &application,
                     [&](QSystemTrayIcon::ActivationReason reason) {
        if (reason != QSystemTrayIcon::Trigger) {
            return;
        }
        if (!activated) {
            activated = true;
            tray.setIcon(icon(QColor(QStringLiteral("#f26d7e"))));
            tray.setToolTip(QStringLiteral("Nagi tray activated"));
            std::cerr << "primary activation observed\n";
            return;
        }
        std::cerr << "tray helper exiting\n";
        QTimer::singleShot(0, &application, &QCoreApplication::quit);
    });

    QObject::connect(&menu, &QMenu::aboutToShow, &application, [&] {
        if (menuExposed) {
            return;
        }
        menuExposed = true;
        std::cerr << "menu exposed\n";
        QTimer::singleShot(100, &action, &QAction::trigger);
    });
    QObject::connect(&action, &QAction::triggered, &application, [&] {
        tray.setToolTip(QStringLiteral("Nagi tray menu invoked"));
        std::cerr << "menu action invoked\n";
    });

    tray.show();
    std::cerr << "tray helper registered\n";
    return application.exec();
}

int runController(QApplication &application, const QString &qs, const QString &configDirectory)
{
    QProcess item;
    item.setProgram(application.applicationFilePath());
    item.setArguments({QStringLiteral("--item")});
    item.setProcessChannelMode(QProcess::ForwardedChannels);

    QProcess shell;
    shell.setProgram(qs);
    shell.setArguments({QStringLiteral("-p"), configDirectory, QStringLiteral("--no-duplicate")});
    shell.setProcessChannelMode(QProcess::ForwardedChannels);

    int result = 1;
    QObject::connect(&item, &QProcess::started, &application, [&] { shell.start(); });
    QObject::connect(&item, &QProcess::errorOccurred, &application,
                     [&](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            std::cerr << "tray helper failed to start\n";
            application.quit();
        }
    });
    QObject::connect(&shell, &QProcess::errorOccurred, &application,
                     [&](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            std::cerr << "tray QML probe failed to start\n";
            item.kill();
            application.quit();
        }
    });
    QObject::connect(&shell, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), &application,
                     [&](int exitCode, QProcess::ExitStatus status) {
        result = status == QProcess::NormalExit && exitCode == 0 ? 0 : 1;
        if (result != 0) {
            std::cerr << "tray QML probe failed: exit=" << exitCode << '\n';
        }
        if (item.state() != QProcess::NotRunning) {
            item.kill();
        }
        application.quit();
    });

    QTimer timeout;
    timeout.setSingleShot(true);
    timeout.setInterval(15000);
    QObject::connect(&timeout, &QTimer::timeout, &application, [&] {
        std::cerr << "live tray test timed out\n";
        if (shell.state() != QProcess::NotRunning) {
            shell.kill();
        }
        if (item.state() != QProcess::NotRunning) {
            item.kill();
        }
        application.quit();
    });

    item.start();
    timeout.start();
    const int eventLoopResult = application.exec();
    shell.waitForFinished(1000);
    item.waitForFinished(1000);
    return eventLoopResult == 0 ? result : eventLoopResult;
}

} // namespace

int main(int argc, char **argv)
{
    QApplication application(argc, argv);
    if (argc == 2 && QString::fromLocal8Bit(argv[1]) == QStringLiteral("--item")) {
        return runItem(application);
    }
    if (argc != 3) {
        std::cerr << "usage: tray-live-test <qs> <config-dir>\n";
        return 2;
    }
    return runController(application, QString::fromLocal8Bit(argv[1]),
                         QString::fromLocal8Bit(argv[2]));
}
