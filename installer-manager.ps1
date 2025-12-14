param(
    [string]$InstallersDir = (Join-Path $PSScriptRoot 'installers'),
    [string]$ManifestPath = (Join-Path $PSScriptRoot 'installers-manifest.json')
)

function PromptText {
    param([string]$Label,[string]$Default = '')
    if([string]::IsNullOrWhiteSpace($Default)){ return Read-Host $Label }
    return Read-Host ("{0} [{1}]" -f $Label,$Default)
}

function SanitizeInput {
    param([string]$Value)
    if($null -eq $Value){ return '' }
    return $Value.Trim().Trim('"')
}

function DetectNameFromPath {
    param([string]$FilePath)
    if([string]::IsNullOrEmpty($FilePath)){ return $null }
    $name = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
    if([string]::IsNullOrWhiteSpace($name)){ return $null }
    return ($name -replace '[_\-]+',' ').Trim()
}

function DetectVersion {
    param([string]$FilePath)
    try {
        $info = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($FilePath)
        if($info.FileVersion){ return $info.FileVersion }
        if($info.ProductVersion){ return $info.ProductVersion }
    }
    catch {}
    return $null
}

function GetRelativePath {
    param([string]$BasePath,[string]$FullPath)
    try { return [System.IO.Path]::GetRelativePath($BasePath,$FullPath) }
    catch {
        $baseUri = New-Object System.Uri(($BasePath.TrimEnd('\') + '\'))
        $fullUri = New-Object System.Uri($FullPath)
        return $baseUri.MakeRelativeUri($fullUri).ToString().Replace('/', '\')
    }
}

function NormalizeManifest($entries){

    $result = @()

    foreach($entry in $entries){

        if(-not $entry.PSObject.Properties['Section']){ $entry | Add-Member Section '' -Force }

        $sectionValue = $entry.Section

        if(-not [string]::IsNullOrEmpty($sectionValue)){

            if($sectionValue -match '%'){

                try { $sectionValue = [System.Uri]::UnescapeDataString($sectionValue) }

                catch {}

            }

            $entry.Section = $sectionValue.Trim()

        }

        if(-not $entry.PSObject.Properties['RelativePath']){

            $rel = if([string]::IsNullOrEmpty($entry.Section)){ $entry.FileName } else { Join-Path $entry.Section $entry.FileName }

            $entry | Add-Member RelativePath $rel -Force

        }

        $relativePath = $entry.RelativePath

        if($relativePath){

            if($relativePath -match '%'){

                try { $relativePath = [System.Uri]::UnescapeDataString($relativePath) }

                catch {}

            }

            $relativePath = $relativePath.Trim()

            if(-not [string]::IsNullOrEmpty($relativePath)){

                $entry.RelativePath = $relativePath -replace '/', '\'

            }

        }

        $result += $entry

    }

    return $result

}
function LoadManifest {
    if(-not (Test-Path $ManifestPath)){ return @() }
    $json = Get-Content -Raw -Path $ManifestPath -ErrorAction SilentlyContinue
    if([string]::IsNullOrWhiteSpace($json)){ return @() }
    try { return NormalizeManifest (@($json | ConvertFrom-Json)) }
    catch { return @() }
}

function SaveManifest($items){
    ($items | ConvertTo-Json -Depth 4) | Set-Content -Path $ManifestPath -Encoding UTF8
}

function Build-ManifestEntry {
    param([string]$Name,[string]$Version,[string]$Section,[string]$FileName,[string]$RelativePath)
    [pscustomobject]@{
        Name = $Name
        Version = $Version
        FileName = $FileName
        Section = $Section
        RelativePath = $RelativePath
        AddedAt = (Get-Date)
    }
}

function GetCurrentManifest {
    $data = @(LoadManifest)
    $valid = @()
    $existing = @{}
    foreach($entry in $data){
        $full = Join-Path $InstallersDir $entry.RelativePath
        if(Test-Path $full){
            $key = $entry.RelativePath.ToLower()
            $existing[$key] = $true
            $valid += $entry
        }
    }

    $files = Get-ChildItem -Path $InstallersDir -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Extension -match '\.(exe|msi)$' }
    $changed = $false
    foreach($file in $files){
        $relative = GetRelativePath -BasePath $InstallersDir -FullPath $file.FullName
        $relative = $relative -replace '/', '\'
        $key = $relative.ToLower()
        if($existing.ContainsKey($key)){ continue }

        $sectionFolder = ''
        if($relative.Contains('\')){
            $sectionFolder = ($relative.Split('\')[0])
        }
        $name = DetectNameFromPath $file.FullName
        if(-not $name){ $name = $file.BaseName }
        $version = DetectVersion $file.FullName
        if(-not $version){ $version = 'unknown' }
        $entry = Build-ManifestEntry -Name $name -Version $version -Section $sectionFolder -FileName $file.Name -RelativePath $relative
        $valid += $entry
        $existing[$key] = $true
        $changed = $true
    }

    if($changed -or $valid.Count -ne $data.Count){ SaveManifest $valid }
    return $valid
}

function InitializeEnvironment {
    if(-not (Test-Path $InstallersDir)){ New-Item -ItemType Directory -Path $InstallersDir | Out-Null }
    if(-not (Test-Path $ManifestPath)){ '[]' | Set-Content -Path $ManifestPath -Encoding UTF8 }
    GetCurrentManifest | Out-Null
}

function ShowNotification {
    param([string]$Message,[ValidateSet('info','success','warning','error','accent')]$Type='info')
    $color = switch($Type){ 'success'{'Green'} 'warning'{'Yellow'} 'error'{'Red'} 'accent'{'Cyan'} default{'Gray'} }
    Write-Host " * $Message" -ForegroundColor $color
}

function GetInstallerSections {
    $sections = [System.Collections.Generic.List[pscustomobject]]::new()
    $sections.Add([pscustomobject]@{ DisplayName='Общий раздел'; FolderName=''; Path=$InstallersDir })
    $dirs = Get-ChildItem -Path $InstallersDir -Directory -ErrorAction SilentlyContinue
    foreach($dir in $dirs){ $sections.Add([pscustomobject]@{ DisplayName=$dir.Name; FolderName=$dir.Name; Path=$dir.FullName }) }
    return $sections
}

function ResolveSectionPath($sectionInput){
    $sectionName = SanitizeInput $sectionInput
    if([string]::IsNullOrWhiteSpace($sectionName)){ return '', $InstallersDir }
    $path = Join-Path $InstallersDir $sectionName
    if(-not (Test-Path $path)){ New-Item -ItemType Directory -Path $path | Out-Null }
    return $sectionName, $path
}

function Draw-Menu {
    param([string]$Title,[array]$Items,[int]$SelectedIndex)
    Clear-Host
    $maxLabel = ($Items | ForEach-Object { $_.Label.Length } | Measure-Object -Maximum).Maximum
    if(-not $maxLabel){ $maxLabel = 20 }
    $width = [Math]::Max(60,$maxLabel + 12)
    $border = '═' * ($width - 2)
    Write-Host "╔$border╗" -ForegroundColor Cyan
    $padding = [Math]::Max(0,$width - 2 - $Title.Length)
    $left = [Math]::Floor($padding / 2)
    $right = $padding - $left
    Write-Host ("║{0}{1}{2}║" -f (' ' * $left), $Title, (' ' * $right)) -ForegroundColor Cyan
    Write-Host "╠$border╣" -ForegroundColor Cyan
    for($i=0;$i -lt $Items.Count;$i++){
        $item = $Items[$i]
        $line = "║   [$($item.Key)] {0,-45} ║" -f $item.Label
        if($i -eq $SelectedIndex){ Write-Host $line -ForegroundColor Black -BackgroundColor Yellow }
        else { Write-Host $line -ForegroundColor White }
    }
    Write-Host "╠$border╣" -ForegroundColor Cyan
    Write-Host 'Стрелки – перемещение, Enter/цифра – выбор, Esc – назад/выход.' -ForegroundColor DarkGray
    Write-Host "╚$border╝" -ForegroundColor Cyan
}

function PromptInstallerSource {
    ShowNotification 'Укажите источник (URL, локальный путь или ключевые слова url/local).' 'accent'
    $raw = SanitizeInput (Read-Host 'Источник (url/local или путь/ссылка)')
    $mode, $value = $null, $null
    switch -Regex ($raw.ToLower()){
        '^(url|u)$' { $mode='url' }
        '^(local|l)$' { $mode='local' }
    }
    if(-not $mode -and $raw){
        if($raw -match '^(https?|ftp)://'){ $mode='url'; $value=$raw }
        elseif([System.IO.Path]::IsPathRooted($raw) -and (Test-Path $raw)){ $mode='local'; $value=$raw }
    }
    return $mode, $value
}

function Add-Or-UpdateInstaller {
    $manifest = @(GetCurrentManifest)
    $mode, $prefilled = PromptInstallerSource
    if(-not $mode){ ShowNotification 'Не удалось определить источник. Попробуйте снова.' 'warning'; return }

    $sectionInput = PromptText 'Раздел (Enter для корня, иначе имя папки)' ''
    $sectionFolder, $sectionPath = ResolveSectionPath $sectionInput

    if($mode -eq 'url'){
        $url = if($prefilled){ $prefilled } else { SanitizeInput (PromptText 'URL файла' '') }
        if(-not $url){ ShowNotification 'URL обязателен.' 'error'; return }
        $destFile = [System.IO.Path]::GetFileName(($url -split '\?')[0])
        if(-not $destFile){ ShowNotification 'Не удалось определить файл из URL.' 'error'; return }
        $destFull = Join-Path $sectionPath $destFile
        try {
            ShowNotification "Скачиваю $url ..." 'info'
            Invoke-WebRequest -Uri $url -OutFile $destFull -UseBasicParsing -ErrorAction Stop
        }
        catch { ShowNotification "Не удалось скачать: $($_.Exception.Message)" 'error'; return }
    }
    else {
        $path = if($prefilled){ $prefilled } else { SanitizeInput (PromptText 'Путь к локальному файлу' '') }
        if(-not ($path -and (Test-Path $path))){ ShowNotification 'Файл не найден.' 'error'; return }
        $destFile = [System.IO.Path]::GetFileName($path)
        $destFull = Join-Path $sectionPath $destFile
        try { Copy-Item -Path $path -Destination $destFull -Force }
        catch { ShowNotification "Ошибка копирования: $($_.Exception.Message)" 'error'; return }
    }

    if(-not (Test-Path $destFull)){ ShowNotification 'Файл не был создан/скопирован. Проверьте доступ.' 'error'; return }

    $name = SanitizeInput (PromptText 'Название программы' '')
    if(-not $name){ $name = DetectNameFromPath $destFull }
    if(-not $name){ ShowNotification 'Название не указано и не определено автоматически.' 'warning'; return }

    $version = SanitizeInput (PromptText 'Версия' '')
    if(-not $version){ $version = DetectVersion $destFull }
    if(-not $version){ ShowNotification 'Версия не указана и не определена автоматически.' 'warning'; return }

    $manifest = $manifest | Where-Object { !($_.Name -eq $name -and $_.Version -eq $version -and $_.Section -eq $sectionFolder) }

    $relativePath = if([string]::IsNullOrEmpty($sectionFolder)){ $destFile } else { Join-Path $sectionFolder $destFile }
    $manifest += Build-ManifestEntry -Name $name -Version $version -Section $sectionFolder -FileName $destFile -RelativePath $relativePath
    SaveManifest $manifest
    $displaySection = if([string]::IsNullOrEmpty($sectionFolder)){ 'Общий раздел' } else { $sectionFolder }
    ShowNotification "Установщик добавлен в раздел '$displaySection'." 'success'
}

function Invoke-InstallerFile {
    param([System.IO.FileInfo]$File)
    if(-not $File){ return }
    ShowNotification "Запуск $($File.Name)..." 'info'
    try {
        if($File.Extension -eq '.msi'){ Start-Process msiexec.exe -ArgumentList "/i `"$($File.FullName)`"" -Wait }
        else { Start-Process $File.FullName -Wait }
    }
    catch { ShowNotification "Ошибка запуска $($File.Name): $($_.Exception.Message)" 'error' }
}

function Install-Section {
    param([string]$SectionPath,[string]$DisplayName)
    $files = @(Get-ChildItem -Path $SectionPath -Filter *.exe -File -ErrorAction SilentlyContinue)
    $files += @(Get-ChildItem -Path $SectionPath -Filter *.msi -File -ErrorAction SilentlyContinue)
    if(-not $files){ ShowNotification "В разделе '$DisplayName' установщики не найдены." 'warning'; return }
    ShowNotification "Раздел '$DisplayName': найдено $($files.Count) файлов." 'accent'
    foreach($file in $files){ Invoke-InstallerFile -File $file }
}

function Install-AllSections {
    foreach($section in GetInstallerSections){ Install-Section -SectionPath $section.Path -DisplayName $section.DisplayName }
    ShowNotification 'Обработка всех разделов завершена.' 'success'
}

function Install-SelectedInstallers {
    $manifest = @(GetCurrentManifest | Sort-Object @{Expression={$_.Section}}, @{Expression={$_.Name}})
    if(-not $manifest){ ShowNotification 'Записей в манифесте нет.' 'warning'; return }
    $selected = [bool[]]::new($manifest.Count)
    $index = 0
    $statusMessage = ''
    while($true){
        Clear-Host
        Write-Host '=== ВЫБОР УСТАНОВЩИКОВ ===' -ForegroundColor Cyan
        Write-Host 'Стрелки – перемещение, Пробел/Enter – отметить, 1 – запуск, 0 – выход.' -ForegroundColor DarkGray
        if($statusMessage){ Write-Host $statusMessage -ForegroundColor Yellow }
        for($i=0;$i -lt $manifest.Count;$i++){
            $entry = $manifest[$i]
            $checkbox = if($selected[$i]){ '[x]' } else { '[ ]' }
            $sectionLabel = if([string]::IsNullOrEmpty($entry.Section)){ 'без раздела' } else { $entry.Section }
            $lineNumber = $i + 1
            $versionText = if([string]::IsNullOrEmpty($entry.Version)){ 'unknown' } else { $entry.Version.Trim() }
            $line = ("{0} {1,3}. {2} (версия {3}) [{4}] {5}" -f $checkbox, $lineNumber, $entry.Name, $versionText, $sectionLabel, $entry.FileName)
            if($i -eq $index){ Write-Host $line -ForegroundColor Black -BackgroundColor Yellow }
            else { Write-Host $line -ForegroundColor White }
        }
        $key = [System.Console]::ReadKey($true)
        if($key.KeyChar -eq '1'){
            $chosen = @()
            for($i=0;$i -lt $manifest.Count;$i++){
                if($selected[$i]){ $chosen += $manifest[$i] }
            }
            if(-not $chosen){ $statusMessage = 'Отметьте установщики перед запуском.'; continue }
            Clear-Host
            foreach($entry in $chosen){
                $fullPath = Join-Path $InstallersDir $entry.RelativePath
                if(-not (Test-Path $fullPath)){
                    ShowNotification "Файл $($entry.RelativePath) не найден." 'warning'
                    continue
                }
                $file = Get-Item -LiteralPath $fullPath -ErrorAction SilentlyContinue
                if($null -eq $file){
                    ShowNotification "Не удалось получить файл $($entry.RelativePath)." 'error'
                    continue
                }
                Invoke-InstallerFile -File $file
            }
            ShowNotification 'Выбранные установщики обработаны.' 'success'
            return
        }
        if($key.KeyChar -eq '0' -or $key.Key -eq 'Escape'){ return }
        switch($key.Key){
            'UpArrow' {
                if($index -gt 0){ $index-- } else { $index = $manifest.Count - 1 }
                $statusMessage = ''
            }
            'DownArrow' {
                if($index -lt $manifest.Count - 1){ $index++ } else { $index = 0 }
                $statusMessage = ''
            }
            'Enter' {
                if($manifest.Count){ $selected[$index] = -not $selected[$index] }
                $statusMessage = ''
            }
            'Spacebar' {
                if($manifest.Count){ $selected[$index] = -not $selected[$index] }
                $statusMessage = ''
            }
            default { }
        }
    }
}

function Show-Installers {

    $manifest = @(GetCurrentManifest)

    if(-not $manifest){ ShowNotification 'Записей в манифесте нет.' 'warning'; return }

    $sections = @(GetInstallerSections)

    $printedSections = [System.Collections.Generic.HashSet[string]]::new()

    $anyOutput = $false

    foreach($section in $sections){

        $sectionKey = if([string]::IsNullOrEmpty($section.FolderName)){ '' } else { $section.FolderName }

        $entries = $manifest | Where-Object {

            $current = if([string]::IsNullOrEmpty($_.Section)){ '' } else { $_.Section }

            $current -eq $sectionKey

        } | Sort-Object Name

        if(-not $entries){ continue }

        $null = $printedSections.Add($sectionKey)

        $anyOutput = $true

        Write-Host "\n=== Раздел: $($section.DisplayName) ===" -ForegroundColor Cyan

        $index = 1

        foreach($entry in $entries){

            Write-Host ("  {0}. {1} (версия {2})" -f $index, $entry.Name, $entry.Version) -ForegroundColor White

            Write-Host ("     Файл: {0}" -f $entry.RelativePath) -ForegroundColor DarkGray

            $index++

        }

    }

    $leftover = @()

    foreach($entry in $manifest){

        $key = if([string]::IsNullOrEmpty($entry.Section)){ '' } else { $entry.Section }

        if(-not $printedSections.Contains($key)){ $leftover += $entry }

    }

    if($leftover){

        $groups = $leftover | Group-Object { if([string]::IsNullOrEmpty($_.Section)){ '' } else { $_.Section } }

        foreach($group in $groups){

            $display = if([string]::IsNullOrEmpty($group.Name)){ 'Общий раздел (только в манифесте)' } else { "$($group.Name) (только в манифесте)" }

            Write-Host "\n=== Раздел: $display ===" -ForegroundColor Magenta

            $index = 1

            foreach($entry in ($group.Group | Sort-Object Name)){

                Write-Host ("  {0}. {1} (версия {2})" -f $index, $entry.Name, $entry.Version) -ForegroundColor White

                Write-Host ("     Файл: {0}" -f $entry.RelativePath) -ForegroundColor DarkGray

                $index++

            }

            $anyOutput = $true

        }

    }

    if(-not $anyOutput){ ShowNotification 'Не найдено записей для отображения.' 'warning' }

    $manifestPaths = $manifest.RelativePath

    $files = Get-ChildItem -Path $InstallersDir -File -Recurse -ErrorAction SilentlyContinue

    $orphans = @()

    foreach($file in $files){

        $rel = GetRelativePath -BasePath $InstallersDir -FullPath $file.FullName

        if(-not ($manifestPaths -contains $rel)){

            $orphans += [pscustomobject]@{ RelativePath=$rel; SizeMB=[Math]::Round($file.Length/1MB,2) }

        }

    }

    if($orphans){

        Write-Host '\nФайлы без записи в манифесте:' -ForegroundColor Yellow

        $i = 1

        foreach($item in $orphans){ Write-Host ("  {0}. {1} ({2} МБ)" -f $i, $item.RelativePath, $item.SizeMB) -ForegroundColor Yellow; $i++ }

    }

}

function Install-Menu {
    $sections = GetInstallerSections
    $items = [System.Collections.Generic.List[pscustomobject]]::new()
    $items.Add([pscustomobject]@{ Key='1'; Label='Установить все разделы'; Action={ Install-AllSections }; Args=@() })
    $items.Add([pscustomobject]@{ Key='2'; Label='Установить выборочно'; Action={ Install-SelectedInstallers }; Args=@() })
    $i = 3
    foreach($section in $sections){
        $items.Add([pscustomobject]@{
            Key = "$i"; Label = "Установить раздел: $($section.DisplayName)";
            Action = { param($path,$name) Install-Section -SectionPath $path -DisplayName $name };
            Args = @($section.Path,$section.DisplayName)
        })
        $i++
    }
    $items.Add([pscustomobject]@{ Key='0'; Label='Назад'; Action={ return -1 }; Args=@() })
    Show-InteractiveMenu -Title 'УСТАНОВКА' -Items $items -PauseMessage 'Нажмите любую клавишу, чтобы вернуться к меню установки...'
}

function Invoke-MenuAction {
    param([array]$Items,[int]$Index,[string]$PauseMessage)
    $item = $Items[$Index]
    $action, $args = $item.Action, $item.Args
    if($action){
        $result = if($args -and $args.Count){ & $action @args } else { & $action }
        if($result -eq -1){ return $false }
        if($PauseMessage){ ShowNotification $PauseMessage 'info'; [void][System.Console]::ReadKey($true) }
    }
    return $true
}

function Show-InteractiveMenu {
    param([string]$Title,[array]$Items,[string]$PauseMessage = 'Нажмите любую клавишу, чтобы вернуться в меню...')
    $selected = 0
    while($true){
        Draw-Menu -Title $Title -Items $Items -SelectedIndex $selected
        $key = [System.Console]::ReadKey($true)
        switch($key.Key){
            'UpArrow' { if($selected -gt 0){ $selected-- } else { $selected = $Items.Count - 1 } }
            'DownArrow' { if($selected -lt $Items.Count - 1){ $selected++ } else { $selected = 0 } }
            'Enter' { if(-not (Invoke-MenuAction -Items $Items -Index $selected -PauseMessage $PauseMessage)){ return } }
            'Escape' { return }
            default {
                $char = $key.KeyChar.ToString()
                for($i=0;$i -lt $Items.Count;$i++){
                    if($Items[$i].Key -eq $char){
                        $selected = $i
                        if(-not (Invoke-MenuAction -Items $Items -Index $selected -PauseMessage $PauseMessage)){ return }
                        break
                    }
                }
            }
        }
    }
}

InitializeEnvironment

$mainMenu = @(
    [pscustomobject]@{ Key='1'; Label='Установить (перейти к разделам)'; Action={ Install-Menu }; Args=@() },
    [pscustomobject]@{ Key='2'; Label='Добавить или скачать установщик'; Action={ Add-Or-UpdateInstaller }; Args=@() },
    [pscustomobject]@{ Key='3'; Label='Показать список установщиков по разделам'; Action={ Show-Installers }; Args=@() },
    [pscustomobject]@{ Key='4'; Label='Выход'; Action={ exit }; Args=@() }
)

Show-InteractiveMenu -Title 'МЕНЕДЖЕР УСТАНОВЩИКОВ' -Items $mainMenu -PauseMessage 'Нажмите любую клавишу, чтобы вернуться в главное меню...'

Write-Host 'До встречи!' -ForegroundColor Cyan


