#include <windows.h>
#include <bcrypt.h>

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <optional>
#include <sstream>
#include <string>
#include <vector>

#ifndef HYDROBLADE_SOURCE_DIR
#define HYDROBLADE_SOURCE_DIR "."
#endif

#ifndef HYDROBLADE_CXX_COMPILER
#define HYDROBLADE_CXX_COMPILER "g++.exe"
#endif

namespace fs = std::filesystem;

std::wstring Widen(const std::string& value) {
    if (value.empty()) {
        return L"";
    }
    const int size = MultiByteToWideChar(CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()), nullptr, 0);
    std::wstring result(static_cast<size_t>(size), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()), result.data(), size);
    return result;
}

std::wstring Quote(const fs::path& value) {
    std::wstring text = value.wstring();
    std::wstring escaped;
    escaped.reserve(text.size() + 2);
    escaped.push_back(L'"');
    for (wchar_t ch : text) {
        if (ch == L'"') {
            escaped += L"\\\"";
        } else {
            escaped.push_back(ch);
        }
    }
    escaped.push_back(L'"');
    return escaped;
}

fs::path ExecutablePath() {
    std::vector<wchar_t> buffer(MAX_PATH);
    DWORD size = 0;
    for (;;) {
        size = GetModuleFileNameW(nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
        if (size == 0) {
            return {};
        }
        if (size < buffer.size() - 1) {
            return fs::path(std::wstring(buffer.data(), size));
        }
        buffer.resize(buffer.size() * 2);
    }
}

bool RunCommand(const std::wstring& command) {
    std::vector<wchar_t> mutable_command(command.begin(), command.end());
    mutable_command.push_back(L'\0');

    STARTUPINFOW startup{};
    PROCESS_INFORMATION process{};
    startup.cb = sizeof(startup);

    if (!CreateProcessW(nullptr, mutable_command.data(), nullptr, nullptr, FALSE, 0, nullptr, nullptr, &startup, &process)) {
        return false;
    }

    WaitForSingleObject(process.hProcess, INFINITE);
    DWORD exit_code = 1;
    GetExitCodeProcess(process.hProcess, &exit_code);
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    return exit_code == 0;
}

std::optional<std::vector<unsigned char>> ReadFileBytes(const fs::path& path) {
    std::ifstream file(path, std::ios::binary);
    if (!file) {
        return std::nullopt;
    }
    return std::vector<unsigned char>(std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>());
}

std::optional<std::vector<unsigned char>> Sha256(const fs::path& path) {
    auto bytes = ReadFileBytes(path);
    if (!bytes) {
        return std::nullopt;
    }

    BCRYPT_ALG_HANDLE alg = nullptr;
    BCRYPT_HASH_HANDLE hash = nullptr;
    DWORD object_size = 0;
    DWORD hash_size = 0;
    DWORD written = 0;

    if (BCryptOpenAlgorithmProvider(&alg, BCRYPT_SHA256_ALGORITHM, nullptr, 0) != 0) {
        return std::nullopt;
    }
    auto close_alg = [&]() {
        if (alg) BCryptCloseAlgorithmProvider(alg, 0);
    };

    if (BCryptGetProperty(alg, BCRYPT_OBJECT_LENGTH, reinterpret_cast<PUCHAR>(&object_size), sizeof(object_size), &written, 0) != 0 ||
        BCryptGetProperty(alg, BCRYPT_HASH_LENGTH, reinterpret_cast<PUCHAR>(&hash_size), sizeof(hash_size), &written, 0) != 0) {
        close_alg();
        return std::nullopt;
    }

    std::vector<unsigned char> object(object_size);
    std::vector<unsigned char> digest(hash_size);
    if (BCryptCreateHash(alg, &hash, object.data(), object_size, nullptr, 0, 0) != 0) {
        close_alg();
        return std::nullopt;
    }

    const NTSTATUS update_status = BCryptHashData(hash, bytes->data(), static_cast<ULONG>(bytes->size()), 0);
    const NTSTATUS finish_status = BCryptFinishHash(hash, digest.data(), hash_size, 0);
    BCryptDestroyHash(hash);
    close_alg();
    if (update_status != 0 || finish_status != 0) {
        return std::nullopt;
    }
    return digest;
}

std::wstring Hex(const std::vector<unsigned char>& bytes) {
    std::wostringstream out;
    out << std::hex << std::setfill(L'0');
    for (unsigned char byte : bytes) {
        out << std::setw(2) << static_cast<unsigned int>(byte);
    }
    return out.str();
}

bool CopyAssets(const fs::path& source_dir, const fs::path& output_dir) {
    const fs::path source_assets = source_dir / L"assets";
    const fs::path output_assets = output_dir / L"assets";
    std::error_code ec;
    if (!fs::exists(source_assets, ec)) {
        return true;
    }
    fs::create_directories(output_assets, ec);
    fs::copy(source_assets, output_assets, fs::copy_options::recursive | fs::copy_options::overwrite_existing, ec);
    return !ec;
}

bool ReplaceExecutable(const fs::path& candidate, const fs::path& target) {
    std::error_code ec;
    if (!fs::exists(target, ec)) {
        fs::rename(candidate, target, ec);
        return !ec;
    }

    fs::path backup = target;
    backup += L".bak";
    fs::remove(backup, ec);

    if (!MoveFileExW(target.c_str(), backup.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
        return false;
    }
    if (!MoveFileExW(candidate.c_str(), target.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
        MoveFileExW(backup.c_str(), target.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH);
        return false;
    }
    fs::remove(backup, ec);
    return true;
}

fs::path CompilerPath() {
    wchar_t env_value[MAX_PATH * 2]{};
    const DWORD length = GetEnvironmentVariableW(L"HYDROBLADE_CXX", env_value, static_cast<DWORD>(std::size(env_value)));
    if (length > 0 && length < std::size(env_value)) {
        return fs::path(env_value);
    }

    fs::path configured = Widen(HYDROBLADE_CXX_COMPILER);
    if (!configured.empty() && fs::exists(configured)) {
        return configured;
    }

    fs::path msys = L"C:\\msys64\\mingw64\\bin\\g++.exe";
    if (fs::exists(msys)) {
        return msys;
    }

    return L"g++.exe";
}

bool BuildLatest(const fs::path& source_dir, const fs::path& output) {
    const fs::path compiler = CompilerPath();
    const fs::path source = source_dir / L"src" / L"main.cpp";
    std::wstring command =
        Quote(compiler) +
        L" -std=c++17 -municode -mwindows -DUNICODE -D_UNICODE -DNOMINMAX -DWIN32_LEAN_AND_MEAN " +
        Quote(source) +
        L" -o " +
        Quote(output) +
        L" -Wl,--no-insert-timestamp -lcomctl32 -lwinhttp -lshell32 -lshlwapi -lws2_32 -liphlpapi -lgdi32 -lbcrypt -lgdiplus -lole32";
    return RunCommand(command);
}

void TryGitPull(const fs::path& source_dir) {
    const fs::path repo = source_dir.parent_path();
    std::error_code ec;
    if (!fs::exists(repo / L".git", ec)) {
        return;
    }
    std::wcout << L"Checking git for latest source..." << std::endl;
    const std::wstring command = L"git -C " + Quote(repo) + L" pull --ff-only";
    if (!RunCommand(command)) {
        std::wcout << L"Git update skipped or failed; continuing with local source." << std::endl;
    }
}

int wmain(int argc, wchar_t** argv) {
    const bool verify_only = argc > 1 && _wcsicmp(argv[1], L"--verify-only") == 0;
    const auto finish = [&](int code) {
        if (!verify_only) {
            std::wcout << L"Press Enter to close." << std::endl;
            std::wstring line;
            std::getline(std::wcin, line);
        }
        return code;
    };
    const fs::path self = ExecutablePath();
    const fs::path output_dir = self.parent_path();
    const fs::path source_dir = fs::path(Widen(HYDROBLADE_SOURCE_DIR));
    const fs::path target = output_dir / L"HydroBlade.exe";
    const fs::path candidate = output_dir / L"HydroBlade.latest.exe";

    std::wcout << L"HydroBlade updater" << std::endl;
    std::wcout << L"Source: " << source_dir.wstring() << std::endl;
    std::wcout << L"Target: " << target.wstring() << std::endl;

    TryGitPull(source_dir);

    std::error_code ec;
    fs::remove(candidate, ec);

    std::wcout << L"Building latest HydroBlade.exe..." << std::endl;
    if (!BuildLatest(source_dir, candidate) || !fs::exists(candidate)) {
        std::wcerr << L"Build failed. Set HYDROBLADE_CXX to your MinGW g++.exe path if the compiler was not found." << std::endl;
        return finish(1);
    }

    const auto current_hash = Sha256(target);
    const auto latest_hash = Sha256(candidate);
    if (!latest_hash) {
        std::wcerr << L"Could not hash latest build." << std::endl;
        fs::remove(candidate, ec);
        return finish(1);
    }

    if (current_hash) {
        std::wcout << L"Current: " << Hex(*current_hash) << std::endl;
    } else {
        std::wcout << L"Current: missing" << std::endl;
    }
    std::wcout << L"Latest:  " << Hex(*latest_hash) << std::endl;

    if (current_hash && *current_hash == *latest_hash) {
        std::wcout << L"HydroBlade.exe is already up to date." << std::endl;
        CopyAssets(source_dir, output_dir);
        fs::remove(candidate, ec);
        return finish(0);
    }

    if (verify_only) {
        std::wcout << L"HydroBlade.exe is not up to date. Run update.exe without --verify-only to replace it." << std::endl;
        fs::remove(candidate, ec);
        return finish(2);
    }

    if (!ReplaceExecutable(candidate, target)) {
        std::wcerr << L"Could not replace HydroBlade.exe. Close HydroBlade and rerun update.exe." << std::endl;
        fs::remove(candidate, ec);
        return finish(1);
    }

    if (!CopyAssets(source_dir, output_dir)) {
        std::wcerr << L"HydroBlade.exe was updated, but assets could not be copied." << std::endl;
        return finish(1);
    }

    std::wcout << L"HydroBlade.exe updated to the latest local build." << std::endl;
    return finish(0);
}
