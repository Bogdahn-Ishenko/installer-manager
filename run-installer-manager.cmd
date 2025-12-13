@echo off
setlocal ENABLEEXTENSIONS ENABLEDELAYEDEXPANSION
set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%installer-manager.ps1"

call :find_ps
if not errorlevel 1 goto launch

echo PowerShell was not found.
set /p CONSENT="Download and install PowerShell 7 automatically? (y/n): "
if /I not "%CONSENT%"=="Y" (
    echo Installation cancelled by user. Please install PowerShell manually.
    goto end
)

echo Attempting to install PowerShell 7...
call :install_ps
if errorlevel 1 (
    echo Failed to install PowerShell automatically. Please install it manually and rerun.
    goto end
)
call :find_ps
if errorlevel 1 (
    echo PowerShell still not available after installation. Please reboot or install manually.
    goto end
)

:launch
"%PS_BIN%" -ExecutionPolicy Bypass -File "%PS_SCRIPT%"
goto end

:find_ps
set "PS_BIN="
for %%G in (pwsh powershell) do (
    for /f "delims=" %%I in ('where %%G 2^>nul') do (
        set "PS_BIN=%%I"
        goto found_ps_bin
    )
)
:found_ps_bin
if defined PS_BIN (
    exit /b 0
) else (
    exit /b 1
)

:install_ps
set "PS_VERSION=7.4.1"
set "PS_ARCH=x64"
if /I "%PROCESSOR_ARCHITECTURE%"=="x86" (
    if "%PROCESSOR_ARCHITEW6432%"=="" set "PS_ARCH=x86"
)
set "PS_MSI=PowerShell-%PS_VERSION%-win-%PS_ARCH%.msi"
set "PS_URL=https://github.com/PowerShell/PowerShell/releases/download/v%PS_VERSION%/%PS_MSI%"
set "PS_TEMP=%TEMP%\%PS_MSI%"

echo Downloading %PS_URL%
call :download_file "%PS_URL%" "%PS_TEMP%"
if errorlevel 1 (
    echo Could not download PowerShell installer.
    exit /b 1
)

echo Installing PowerShell silently (this may take a minute)...
msiexec /i "%PS_TEMP%" /qn ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ENABLE_PSREMOTING=1
set "MSI_RESULT=%ERRORLEVEL%"
del /f "%PS_TEMP%" >nul 2>nul
if not "%MSI_RESULT%"=="0" (
    echo msiexec returned error %MSI_RESULT%.
    exit /b 1
)
exit /b 0

:download_file
set "DL_URL=%~1"
set "DL_DEST=%~2"
if exist "%DL_DEST%" del /f "%DL_DEST%" >nul 2>nul
for %%C in (curl.exe bitsadmin.exe certutil.exe) do (
    where %%C >nul 2>nul && goto have_downloader
)
echo Failed to find a downloader utility.
exit /b 1

:have_downloader
where curl >nul 2>nul && curl.exe -L "%DL_URL%" -o "%DL_DEST%" && exit /b 0
where bitsadmin >nul 2>nul && bitsadmin /transfer DLPS /download /priority normal "%DL_URL%" "%DL_DEST%" && exit /b 0
where certutil >nul 2>nul && certutil -urlcache -split -f "%DL_URL%" "%DL_DEST%" && exit /b 0
echo Failed to download %DL_URL%
exit /b 1

:end
endlocal

