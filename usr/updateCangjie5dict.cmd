:: 2025.05.27

@echo off
setlocal enabledelayedexpansion
title 倉頡五代碼表智能更新器
color 0a

pushd %~dp0

:: 下载工具配置
set "Curl_Download=curl -LJ --ssl-no-revoke --progress-bar --create-dirs"

:: 版本文件
set "version_file=versions_Cangjie5dict.txt"

::=======================================
:: 主流程
::=======================================
:menu

call :testGHmirror
call :tongwenfeng.trime.custom.yaml
call :check_version
if "%need_update%"=="1" (
    call :update_cangjie5_dict
    (echo|set /p="%latest_version%") > "%version_file%"
    echo 已更新到最新版本: %latest_version%
    call :deploy
) else (
    echo 当前已是最新版本: %latest_version%，无需更新
)
call :end
goto :eof

::=======================================
:: 子程序
::=======================================
:testGHmirror
CALL "%cd%\..\..\..\Profiles\BackupProfiles\Modules\testGHmirror.cmd"
goto :eof

:check_version
echo.&echo █ 正在检查cangjie5_dict版本...

:: GitHub API 地址
set "api_url=https://api.github.com/repos/Jackchows/Cangjie5/commits?path=Cangjie5.txt&page=1&per_page=1"

:: 获取最新 commit 时间（ISO 8601）
for /f "delims=" %%i in ('powershell -Command "(Invoke-WebRequest -Uri '%api_url%' -UseBasicParsing | ConvertFrom-Json).commit.committer.date" 2^>nul') do (
    set "latest_version=%%i"
)
if not defined latest_version (
    echo 错误：无法获取在线版本信息，请检查网络或代理设置。
    pause
    exit /b 1
)
echo 在线版本: %latest_version%

:: 读取本地版本
set "local_version="
if exist "%version_file%" (
    for /f "usebackq delims=" %%i in ("%version_file%") do set "local_version=%%i"
)
echo 本地版本: %local_version%

:: 比较
if "%latest_version%"=="%local_version%" (
    set "need_update=0"
) else (
    set "need_update=1"
)
echo 版本比较结果: %need_update%

goto :eof

:update_cangjie5_dict
echo. [下载] %GH_PROXY%/https://github.com/Jackchows/Cangjie5/raw/master/Cangjie5.txt
%Curl_Download% -O "%GH_PROXY%/https://github.com/Jackchows/Cangjie5/raw/master/Cangjie5.txt"

if not exist "Cangjie5.txt" (
    echo 错误：下载失败，Cangjie5.txt 未找到。
    pause
    exit /b 1
)

:: 生成头文件
(
    echo # encoding: utf-8
    echo # https://github.com/Jackchows/Cangjie5/raw/master/Cangjie5.txt
    echo ---
    echo name: "cangjie5"
    echo version: "%latest_version%"
    echo sort: original
    echo use_preset_vocabulary: false
    echo columns:
    echo   - text
    echo   - code
    echo   - stem
    echo encoder:
    echo   exclude_patterns:
    echo     - '^x.*$'
    echo     - '^z.*$'
    echo   rules:
    echo     - length_equal: 2
    echo       formula: "AaAzBaBbBz"
    echo     - length_equal: 3
    echo       formula: "AaAzBaBzCz"
    echo     - length_in_range: [4, 10]
    echo       formula: "AaBzCaYzZz"
    echo   tail_anchor: "'"
    echo ...
) > "header.tmp"

:: 更健壮的方法查找以"日	a"开头的行号
echo 正在查找数据起始位置...
for /f "delims=" %%i in ('powershell -Command ^
    "$content = Get-Content 'Cangjie5.txt' -Encoding UTF8;" ^
    "for ($i = 0; $i -lt $content.Length; $i++) {" ^
        "if ($content[$i] -match '^日\ta') {" ^
            "Write-Output $i;" ^
            "break;" ^
        "}" ^
    "}"') do (
    set /a "skip_lines=%%i"
)

if not defined skip_lines (
    echo 错误：未在 Cangjie5.txt 中找到以"日	a"开头的行（用于数据起始标识）。
    echo 正在尝试其他方法查找数据起始位置...
    
    :: 尝试查找第一个包含制表符的非空行
    for /f "delims=" %%i in ('powershell -Command ^
        "$content = Get-Content 'Cangjie5.txt' -Encoding UTF8;" ^
        "for ($i = 0; $i -lt $content.Length; $i++) {" ^
            "if ($content[$i] -match '\t' -and $content[$i].Trim() -ne '') {" ^
                "Write-Output $i;" ^
                "break;" ^
            "}" ^
        "}"') do (
        set /a "skip_lines=%%i"
    )
    
    if not defined skip_lines (
        echo 错误：无法找到数据起始位置。
        del "Cangjie5.txt" 2>nul
        del "header.tmp" 2>nul
        pause
        exit /b 1
    )
    echo 警告：使用备选方法找到数据起始位置，跳过前 %skip_lines% 行
) else (
    echo 找到数据起始位置，跳过前 %skip_lines% 行，从"日	a"字开始提取数据
)

:: 使用健壮的 PowerShell 脚本合并为无 BOM UTF-8
echo 正在生成 cangjie5.dict.yaml...
powershell -Command ^
    "$ErrorActionPreference = 'Stop';" ^
    "try {" ^
        "$enc = New-Object System.Text.UTF8Encoding($false);" ^
        "$writer = New-Object System.IO.StreamWriter('cangjie5.dict.yaml', $false, $enc);" ^
        "$header = Get-Content 'header.tmp' -Encoding UTF8;" ^
        "foreach ($line in $header) {" ^
            "$writer.WriteLine([string]$line);" ^
        "};" ^
        "$content = Get-Content 'Cangjie5.txt' -Encoding UTF8;" ^
        "for ($i = [int]%skip_lines%; $i -lt $content.Length; $i++) {" ^
            "$writer.WriteLine([string]$content[$i]);" ^
        "};" ^
        "$writer.Flush();" ^
        "$writer.Close();" ^
        "Write-Output '文件生成成功';" ^
    "} catch {" ^
        "Write-Error '文件生成失败: $($_.Exception.Message)';" ^
        "exit 1;" ^
    "}"

:: 验证输出
if not exist "cangjie5.dict.yaml" (
    echo 错误：未能生成 cangjie5.dict.yaml！
    del "header.tmp" 2>nul
    del "Cangjie5.txt" 2>nul
    exit /b 1
)

:: 检查生成的文件是否包含数据
for /f %%i in ('powershell -Command "(Get-Content 'cangjie5.dict.yaml' -Encoding UTF8 ^| Select-String '^日\s').Length"') do (
    set "data_lines=%%i"
)
if "!data_lines!"=="0" (
    echo 警告：生成的文件可能不包含有效数据
) else (
    echo 生成的文件包含 !data_lines! 行有效数据
)

:: 清理
del "header.tmp" 2>nul
del "Cangjie5.txt" 2>nul
echo 处理完成，文件已保存为 cangjie5.dict.yaml（UTF-8 无 BOM）
goto :eof

:deploy
if exist "%cd%\..\weasel\WeaselDeployer.exe" (
    start "" "%cd%\..\weasel\WeaselDeployer.exe" /deploy
    echo 已重新布署
) else (
    echo 警告：WeaselDeployer.exe 未找到，跳过部署。
)
goto :eof

:tongwenfeng.trime.custom.yaml
echo 下载 tongwenfeng.trime.custom.yaml
%Curl_Download% -O "%GH_PROXY%/https://github.com/goodaniu/rime-aniu/raw/refs/heads/main/tongwenfeng.trime.custom.yaml"
goto :eof

:end
timeout /t 3 /nobreak >nul
popd
exit