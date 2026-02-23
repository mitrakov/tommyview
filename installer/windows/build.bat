:: v1.0.0 (2026-02-23)
@echo off
cls

set BUILD_PATH=build\windows\x64\runner\Release

:: check tools
call :require flutter
if %ERRORLEVEL% neq 0 exit /b 1

call :require git
if %ERRORLEVEL% neq 0 exit /b 1

call :require iscc
if %ERRORLEVEL% neq 0 (
    echo Inno Setup Compiler iscc.exe not found in PATH. Install Inno Setup and add to PATH: "C:\Program Files (x86)\Inno Setup 6"
    exit /b 1
)

call :require signtool
if %ERRORLEVEL% neq 0 exit /b 1



:: switch to main flutter dir
set SCRIPT_DIR=%~dp0
set WORK_DIR=%SCRIPT_DIR%..\..
cd /d "%WORK_DIR%" && echo %cd%



:: get current version
if not exist "pubspec.yaml" (
    echo Error: pubspec.yaml not found
    exit /b 1
)
for /f "tokens=2 delims=: " %%a in ('findstr /b "version:" pubspec.yaml') do (
    set fullVersion=%%a
)
for /f "tokens=1 delims=+" %%a in ("%fullVersion%") do (
    set VERSION=%%a
)
echo Version from pubspec.yaml: %VERSION%



:: build
echo Building app...
call flutter -v build windows
if %ERRORLEVEL% neq 0 exit /b 1



:: code signing
echo Code signing...
if not exist "%BUILD_PATH%" (
    echo Error: Build directory missing at: %BUILD_PATH%
    exit /b 1
)
pushd "%WORK_DIR%\%BUILD_PATH%"
signtool sign /v /a /tr "http://timestamp.globalsign.com/tsa/r6advanced1" /td SHA256 /fd SHA256 "*.exe" "*.dll"
if %ERRORLEVEL% neq 0 exit /b 1
popd



:: copy other libraries
echo Copying libraries...
if not exist "installer\windows\vcruntime140_1.dll" (
    echo Error: Library missing: installer\windows\vcruntime140_1.dll
    exit /b 1
)
copy /v installer\windows\vcruntime140_1.dll "%BUILD_PATH%"



:: run Inno Setup compiler
echo Compiling Inno Setup installer...
pushd "%WORK_DIR%\installer\windows"
if not exist "inno-setup.iss" (
    echo Error: Inno Setup script not found: inno-setup.iss
    exit /b 1
)
if not exist "Tommyview" mkdir "Tommyview"
xcopy /v "%WORK_DIR%\%BUILD_PATH%" "Tommyview" /S
powershell -Command "(Get-Content 'inno-setup.iss') -replace '__THE_VERSION__', '%VERSION%' | Set-Content 'inno-setup-tmp.iss'"
iscc  "inno-setup-tmp.iss" /O"." /F"tommyview-win64-%VERSION%"
if %ERRORLEVEL% neq 0 exit /b 1

:: verify installer was created
set INSTALLER_NAME=tommyview-win64-%VERSION%.exe
if not exist "%INSTALLER_NAME%" (
    echo Error: Installer not found: %INSTALLER_NAME%
    exit /b 1
)



:: sign the installer itself
echo Signing the installer...
signtool sign /v /a /tr "http://timestamp.globalsign.com/tsa/r6advanced1" /td SHA256 /fd SHA256 "%INSTALLER_NAME%"
if %ERRORLEVEL% neq 0 exit /b 1
del "%WORK_DIR%/dist/tommyview-win64-*.exe"
move /y %INSTALLER_NAME% "%WORK_DIR%/dist"



:: clean-up
echo Cleaning up mess...
del "inno-setup-tmp.iss"
rmdir /s /q "Tommyview"
popd



:: finish
call flutter clean



:: git
git status
git add .
git status
git commit -m "Release %VERSION% for Windows"
git status
set /p PUSH_RESPONSE="Git push? (Y/n): "
if /i not "%PUSH_RESPONSE%"=="n" (
    git push
)
git status

echo Done...
exit /b 0



:: function: require()
:require
where %1 >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo "%1" not found. Make sure that "%1" is available in your PATH
    exit /b 1
)
exit /b 0
