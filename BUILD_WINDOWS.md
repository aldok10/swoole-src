# Building Swoole for Windows

This guide explains how to build the Swoole PHP extension for Windows, resulting in a `php_swoole.dll` file.

## Prerequisites

1. **Windows SDK** with build tools (MSVC)
2. **PHP Development Package** (matching your target PHP version and architecture)
   - Download from: https://windows.php.net/downloads/php-sdk/
   - Choose the appropriate PHP version (e.g., PHP 8.4) and architecture (x64)
   - Extract to a directory like `C:\phpdev`
3. **Required Libraries** (for optional features):
   - OpenSSL
   - libcurl
   - libssh2
   - zlib
   - nghttp2
   - libzstd
   - brotli
   - c-ares (optional)
   - PostgreSQL client libraries (optional)
   - etc.

## Step-by-Step Build Instructions

### 1. Prepare the Build Environment

Extract the PHP development package to `C:\phpdev` (or another location). The structure should be:
```
C:\phpdev
├── deps
│   ├── include
│   └── lib
└── php-8.4.0-Win32-vs16-x64
    ├── bin
    ├── include
    ├── lib
    └── share
```

### 2. Set Up the Environment

Open the appropriate command prompt for your target architecture (e.g., "x64 Native Tools Command Prompt for VS 2019").

Set the PHP SDK path:
```cmd
set PHPSDK_PATH=C:\phpdev
set PHP_VERSION=8.4
set PHP_ARCH=x64
```

### 3. Clone Swoole Source

```cmd
git clone https://github.com/swoole/swoole-src.git
cd swoole-src
```

### 4. Configure the Build

Run `configure.bat` with desired options. Example:
```cmd
configure.bat --enable-swoole --enable-swoole-curl --enable-swoole-thread --with-openssl-dir=C:\path\to\openssl
```

Common options:
- `--enable-swoole`: Enable Swoole extension
- `--enable-swoole-curl`: Enable cURL support
- `--enable-swoole-thread`: Enable thread support (requires PHP ZTS)
- `--enable-swoole-pgsql`: Enable PostgreSQL support
- `--enable-swoole-sqlite`: Enable SQLite support
- `--enable-swoole-odbc`: Enable ODBC support
- `--enable-swoole-dev`: Enable developer flags (ASAN, debug logs)

### 5. Build the Extension

```cmd
nmake
```

### 6. Install the Extension

```cmd
nmake install
```

This will copy `php_swoole.dll` to the PHP extension directory.

### 7. Verify the Build

```cmd
php -d extension=php_swoole --ri swoole
```

## Expected Artifact

The successful build produces:
- **File**: `php_swoole.dll`
- **Location**: The PHP extension directory (typically `C:\phpdev\php-8.4.0-Win32-vs16-x64\ext` or as shown by `php -i | grep extension_dir`)

## Troubleshooting

### Missing Libraries
If you encounter errors about missing libraries (e.g., `libssl.lib`), ensure:
1. The libraries are built for the same Visual Studio version and architecture as PHP.
2. The library directories are in the `LIB` environment variable or specified via `--with-[lib]-dir`.

### Build Fails
Check:
1. You are using the correct PHP SDK (matching PHP version and architecture).
2. All required dependencies are available.
3. You are using the appropriate Visual Studio command prompt.

## CI Reference

See `.github/workflows/windows.yml` for the exact build process used in continuous integration.

## Notes

- The resulting `php_swoole.dll` is thread-safe if built with a thread-safe PHP (ZTS).
- For non-thread-safe PHP, omit `--enable-swoole-thread`.
- The DLL depends on the runtime libraries of the libraries it was built against (e.g., OpenSSL DLLs). Ensure these are in your system PATH when using the extension.