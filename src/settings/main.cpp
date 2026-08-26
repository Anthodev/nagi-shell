#include <array>
#include <cerrno>
#include <cstdint>
#include <cstring>
#include <fcntl.h>
#include <iostream>
#include <limits>
#include <optional>
#include <string>
#include <string_view>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

namespace {
constexpr std::size_t MaximumSettingsBytes = 32 * 1024;
constexpr std::size_t MaximumLegacyBytes = 4 * 1024;
constexpr mode_t DirectoryMode = 0700;
constexpr mode_t FileMode = 0600;

constexpr std::string_view SettingsName = "settings.conf";
constexpr std::string_view LastGoodName = "settings.conf.last-good";
constexpr std::string_view LegacyName = "theme.conf";
constexpr std::string_view MigrationBackupName = "settings.conf.bak";
constexpr std::string_view InvalidBackupName = "settings.conf.invalid";

class FileDescriptor {
public:
    explicit FileDescriptor(int descriptor = -1) : descriptor_(descriptor) {}
    ~FileDescriptor()
    {
        if (descriptor_ >= 0) {
            close(descriptor_);
        }
    }
    FileDescriptor(const FileDescriptor &) = delete;
    FileDescriptor &operator=(const FileDescriptor &) = delete;
    FileDescriptor(FileDescriptor &&other) noexcept : descriptor_(other.descriptor_)
    {
        other.descriptor_ = -1;
    }
    int get() const { return descriptor_; }
    explicit operator bool() const { return descriptor_ >= 0; }

private:
    int descriptor_;
};

enum class PathKind { Missing, Regular, Unsafe };

const char *kindName(PathKind kind)
{
    switch (kind) {
    case PathKind::Missing:
        return "missing";
    case PathKind::Regular:
        return "regular";
    case PathKind::Unsafe:
        return "unsafe";
    }
    return "unsafe";
}

bool ensureDirectory(const std::string &path)
{
    struct stat status {};
    if (lstat(path.c_str(), &status) == 0) {
        if (!S_ISDIR(status.st_mode) || status.st_uid != getuid()) {
            return false;
        }
        return chmod(path.c_str(), DirectoryMode) == 0;
    }
    if (errno != ENOENT) {
        return false;
    }
    if (mkdir(path.c_str(), DirectoryMode) != 0) {
        return errno == EEXIST && ensureDirectory(path);
    }
    return true;
}

PathKind pathKind(int directory, std::string_view name)
{
    struct stat status {};
    const std::string path(name);
    if (fstatat(directory, path.c_str(), &status, AT_SYMLINK_NOFOLLOW) != 0) {
        return errno == ENOENT ? PathKind::Missing : PathKind::Unsafe;
    }
    return S_ISREG(status.st_mode) && status.st_uid == getuid() ? PathKind::Regular
                                                                : PathKind::Unsafe;
}


bool makePrivate(int directory, std::string_view name)
{
    const PathKind kind = pathKind(directory, name);
    if (kind == PathKind::Missing) {
        return true;
    }
    if (kind != PathKind::Regular) {
        return false;
    }
    const std::string path(name);
    FileDescriptor file(openat(directory, path.c_str(), O_RDONLY | O_CLOEXEC | O_NOFOLLOW));
    return file && fchmod(file.get(), FileMode) == 0;
}
std::optional<std::string> readFile(int directory, std::string_view name, std::size_t maximumBytes)
{
    if (pathKind(directory, name) != PathKind::Regular) {
        return std::nullopt;
    }
    const std::string path(name);
    FileDescriptor file(openat(directory, path.c_str(), O_RDONLY | O_CLOEXEC | O_NOFOLLOW));
    if (!file) {
        return std::nullopt;
    }
    struct stat status {};
    if (fstat(file.get(), &status) != 0 || !S_ISREG(status.st_mode) || status.st_uid != getuid()
        || status.st_size < 0 || static_cast<std::uintmax_t>(status.st_size) > maximumBytes) {
        return std::nullopt;
    }
    std::string content(static_cast<std::size_t>(status.st_size), '\0');
    std::size_t offset = 0;
    while (offset < content.size()) {
        const ssize_t count = read(file.get(), content.data() + offset, content.size() - offset);
        if (count <= 0) {
            return std::nullopt;
        }
        offset += static_cast<std::size_t>(count);
    }
    return content;
}

bool writeAll(int descriptor, std::string_view content)
{
    std::size_t offset = 0;
    while (offset < content.size()) {
        const ssize_t count = write(descriptor, content.data() + offset, content.size() - offset);
        if (count <= 0) {
            return false;
        }
        offset += static_cast<std::size_t>(count);
    }
    return true;
}

bool installNoReplace(int directory, const std::string &temporary, const std::string &target)
{
#ifdef SYS_renameat2
    if (syscall(SYS_renameat2, directory, temporary.c_str(), directory, target.c_str(),
                RENAME_NOREPLACE)
        == 0) {
        return true;
    }
    if (errno != ENOSYS && errno != EINVAL) {
        return false;
    }
#endif
    if (linkat(directory, temporary.c_str(), directory, target.c_str(), 0) != 0) {
        return false;
    }
    return unlinkat(directory, temporary.c_str(), 0) == 0;
}

bool writeAtomic(int directory, std::string_view name, std::string_view content, bool noReplace = false)
{
    const PathKind kind = pathKind(directory, name);
    if (kind == PathKind::Unsafe || (noReplace && kind != PathKind::Missing)) {
        return false;
    }

    static unsigned counter = 0;
    const std::string temporary = ".settings.conf.stage-" + std::to_string(getpid()) + "-"
        + std::to_string(++counter);
    FileDescriptor file(openat(directory, temporary.c_str(),
                               O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, FileMode));
    if (!file || !writeAll(file.get(), content) || fchmod(file.get(), FileMode) != 0
        || fsync(file.get()) != 0) {
        unlinkat(directory, temporary.c_str(), 0);
        return false;
    }

    const std::string target(name);
    const bool installed = noReplace
        ? installNoReplace(directory, temporary, target)
        : renameat(directory, temporary.c_str(), directory, target.c_str()) == 0;
    if (!installed) {
        unlinkat(directory, temporary.c_str(), 0);
        return false;
    }
    return fsync(directory) == 0;
}

bool restoreFile(int directory, std::string_view name, const std::optional<std::string> &content)
{
    if (content.has_value()) {
        return writeAtomic(directory, name, *content);
    }
    const std::string path(name);
    return unlinkat(directory, path.c_str(), 0) == 0 || errno == ENOENT;
}

bool writeBundle(int directory, std::string_view content, bool noReplace)
{
    const auto oldSettings = readFile(directory, SettingsName, MaximumSettingsBytes);
    const auto oldLastGood = readFile(directory, LastGoodName, MaximumSettingsBytes);
    if (!writeAtomic(directory, SettingsName, content, noReplace)) {
        return false;
    }
    if (writeAtomic(directory, LastGoodName, content)) {
        return true;
    }
    restoreFile(directory, SettingsName, oldSettings);
    restoreFile(directory, LastGoodName, oldLastGood);
    return false;
}

bool backupExact(int directory, std::string_view source, std::string_view target,
                 std::size_t maximumBytes, bool replace)
{
    const auto content = readFile(directory, source, maximumBytes);
    if (!content.has_value()) {
        return false;
    }
    if (!replace && pathKind(directory, target) == PathKind::Regular) {
        const auto existing = readFile(directory, target, maximumBytes);
        return existing.has_value() && *existing == *content;
    }
    return writeAtomic(directory, target, *content, !replace);
}

std::optional<std::string> readStandardInput(std::size_t byteCount)
{
    if (byteCount > MaximumSettingsBytes) {
        return std::nullopt;
    }
    std::string content(byteCount, '\0');
    std::size_t offset = 0;
    while (offset < content.size()) {
        const ssize_t count = read(STDIN_FILENO, content.data() + offset, content.size() - offset);
        if (count <= 0) {
            return std::nullopt;
        }
        offset += static_cast<std::size_t>(count);
    }
    return content;
}

std::optional<std::size_t> parseSize(const char *value)
{
    try {
        std::size_t consumed = 0;
        const unsigned long long parsed = std::stoull(value, &consumed, 10);
        if (consumed != std::strlen(value) || parsed > MaximumSettingsBytes) {
            return std::nullopt;
        }
        return static_cast<std::size_t>(parsed);
    } catch (...) {
        return std::nullopt;
    }
}

bool performOperation(int directory, std::string_view operation, std::string_view content)
{
    if (operation == "write") {
        return writeBundle(directory, content, false);
    }
    if (operation == "create") {
        return writeBundle(directory, content, true);
    }
    if (operation == "last-good") {
        return writeAtomic(directory, LastGoodName, content);
    }
    if (operation == "migrate") {
        bool success = backupExact(directory, LegacyName, MigrationBackupName, MaximumLegacyBytes,
                                   false)
            && writeBundle(directory, content, true);
        if (success) {
            success = unlinkat(directory, std::string(LegacyName).c_str(), 0) == 0
                && fsync(directory) == 0;
        }
        return success;
    }
    if (operation == "recover") {
        return backupExact(directory, SettingsName, InvalidBackupName, MaximumSettingsBytes, true)
            && writeBundle(directory, content, false);
    }
    return false;
}
std::optional<std::string> percentDecode(std::string_view encoded)
{
    if (encoded.size() > MaximumSettingsBytes * 3) {
        return std::nullopt;
    }
    auto hex = [](char value) -> int {
        if (value >= '0' && value <= '9') {
            return value - '0';
        }
        if (value >= 'A' && value <= 'F') {
            return value - 'A' + 10;
        }
        if (value >= 'a' && value <= 'f') {
            return value - 'a' + 10;
        }
        return -1;
    };
    std::string decoded;
    decoded.reserve(encoded.size());
    for (std::size_t index = 0; index < encoded.size(); ++index) {
        if (encoded[index] != '%') {
            decoded.push_back(encoded[index]);
            continue;
        }
        if (index + 2 >= encoded.size()) {
            return std::nullopt;
        }
        const int high = hex(encoded[index + 1]);
        const int low = hex(encoded[index + 2]);
        if (high < 0 || low < 0) {
            return std::nullopt;
        }
        decoded.push_back(static_cast<char>((high << 4) | low));
        index += 2;
    }
    return decoded.size() <= MaximumSettingsBytes ? std::optional<std::string>(std::move(decoded))
                                                   : std::nullopt;
}


int serve(int directory)
{
    std::string header;
    while (std::getline(std::cin, header)) {
        const std::size_t separator = header.find(' ');
        if (separator == std::string::npos) {
            std::cout << "ERR\n" << std::flush;
            continue;
        }
        const std::string operation = header.substr(0, separator);
        const auto content = percentDecode(std::string_view(header).substr(separator + 1));
        if (!content.has_value()) {
            std::cout << "ERR\n" << std::flush;
            continue;
        }
        std::cout << (performOperation(directory, operation, *content) ? "OK\n" : "ERR\n")
                  << std::flush;
    }
    return 0;
}

int fail(const char *message)
{
    std::cerr << message << '\n';
    return 1;
}
} // namespace

int main(int argc, char **argv)
{
    if (argc < 3) {
        return fail("usage: nagi-settings <operation> <config-directory> [byte-count]");
    }
    const std::string operation(argv[1]);
    const std::string directoryPath(argv[2]);
    if (directoryPath.empty() || directoryPath.front() != '/' || !ensureDirectory(directoryPath)) {
        return fail("configuration directory rejected");
    }
    FileDescriptor directory(
        open(directoryPath.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
    if (!directory) {
        return fail("configuration directory rejected");
    }

    if (operation == "inspect") {
        const PathKind settings = pathKind(directory.get(), SettingsName);
        const PathKind lastGood = pathKind(directory.get(), LastGoodName);
        const PathKind legacy = pathKind(directory.get(), LegacyName);
        const PathKind backup = pathKind(directory.get(), MigrationBackupName);
        const PathKind invalid = pathKind(directory.get(), InvalidBackupName);
        if ((settings == PathKind::Regular && !makePrivate(directory.get(), SettingsName))
                || (lastGood == PathKind::Regular && !makePrivate(directory.get(), LastGoodName))
                || (legacy == PathKind::Regular && !makePrivate(directory.get(), LegacyName))
                || (backup == PathKind::Regular
                    && !makePrivate(directory.get(), MigrationBackupName))
                || (invalid == PathKind::Regular
                    && !makePrivate(directory.get(), InvalidBackupName))) {
            return fail("settings permissions could not be secured");
        }
        std::cout << "{\"settings\":\"" << kindName(settings) << "\",\"lastGood\":\""
                  << kindName(lastGood) << "\",\"legacy\":\"" << kindName(legacy)
                  << "\",\"backup\":\"" << kindName(backup) << "\",\"invalid\":\""
                  << kindName(invalid) << "\"}\n";
        return 0;
    }
    if (operation == "serve") {
        return serve(directory.get());
    }


    if (argc != 4) {
        return fail("byte count required");
    }
    const auto byteCount = parseSize(argv[3]);
    const auto content = byteCount.has_value() ? readStandardInput(*byteCount) : std::nullopt;
    if (!content.has_value()) {
        return fail("settings payload rejected");
    }

    const bool success = performOperation(directory.get(), operation, *content);

    return success ? 0 : fail("settings operation failed");
}
