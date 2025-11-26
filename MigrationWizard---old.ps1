#requires -version 5.1
function Save-DesktopLayout {
param([string]$OutDir)
if (-not (Test-Path -LiteralPath $OutDir)) {
  New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
}
# Garantir System.Drawing/Windows.Forms avant d'utiliser Graphics/Screen (PS 5.1)
try { Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue } catch {}
try { Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue } catch {}
$g = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
try {
  [pscustomobject]@{
    Width  = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width
    Height = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height
    DpiX   = [int]$g.DpiX
    DpiY   = [int]$g.DpiY
  } | ConvertTo-Json | Set-Content -Path (Join-Path $OutDir 'screen.json') -Encoding UTF8
} finally {
  $g.Dispose()
}
# Mettre les exports dans .\Registry pour correspondre à l'import
$regOut = Join-Path $OutDir 'Registry'
New-Item -ItemType Directory -Force -Path $regOut | Out-Null

function Export-RegIfHasValues {
  param([Parameter(Mandatory)][string]$PsPath,[Parameter(Mandatory)][string]$RawPath,[Parameter(Mandatory)][string]$DestFile)
  try {
    if (Test-Path $PsPath) {
      $props = Get-ItemProperty -Path $PsPath -ErrorAction SilentlyContinue
      if ($props -and ($props.PSObject.Properties.Count -gt 0)) {
        & reg.exe export $RawPath $DestFile /y 2>$null | Out-Null
        Log ("Reg export → {0}" -f $DestFile)
      } else {
        Log ("Reg présent mais vide → {0} (export ignoré)" -f $RawPath)
      }
    } else {
      Log ("Reg absent → {0} (export ignoré)" -f $RawPath)
    }
  } catch { Log ("Reg export {0} : {1}" -f $RawPath, $_.Exception.Message) }
}

Export-RegIfHasValues -PsPath "HKCU:\Software\Microsoft\Windows\Shell\Bags"               -RawPath "HKCU\Software\Microsoft\Windows\Shell\Bags"               -DestFile (Join-Path $regOut 'bags.reg')
Export-RegIfHasValues -PsPath "HKCU:\Software\Microsoft\Windows\Shell\BagMRU"             -RawPath "HKCU\Software\Microsoft\Windows\Shell\BagMRU"             -DestFile (Join-Path $regOut 'bagmru.reg')
Export-RegIfHasValues -PsPath "HKCU:\Software\Microsoft\Windows\Shell\Bags\1\Desktop"     -RawPath "HKCU\Software\Microsoft\Windows\Shell\Bags\1\Desktop"     -DestFile (Join-Path $regOut 'desktopbag.reg')
Export-RegIfHasValues -PsPath "HKCU:\Software\Microsoft\Windows\Shell\Streams\Desktop"    -RawPath "HKCU\Software\Microsoft\Windows\Shell\Streams\Desktop"    -DestFile (Join-Path $regOut 'streamsdesk.reg')
Export-RegIfHasValues -PsPath "HKCU:\Control Panel\Desktop\WindowMetrics"                 -RawPath "HKCU\Control Panel\Desktop\WindowMetrics"                 -DestFile (Join-Path $regOut 'windowmetrics.reg')
# Marqueur de compat (utilisé par la détection)
try { '1' | Set-Content -Path (Join-Path $regOut 'UserDesktop.marker') -Encoding ASCII } catch {}
$pub = 'C:\Users\Public\Desktop'
$usr = Join-Path $env:USERPROFILE 'Desktop'
Get-ChildItem -LiteralPath $pub,$usr -Force |
  Sort-Object FullName |
  Select-Object FullName,Name,PSIsContainer |
  Export-Csv -NoTypeInformation -Encoding UTF8 -UseCulture -Path (Join-Path $OutDir 'desktop_files.csv')
}
function Restore-DesktopLayout {
  param(
    [Parameter(Mandatory=$true)][string]$InDir
  )
  # 1) Désactiver l’auto-arrange le temps de la pose (évite le ré-alignement)
  try {
    New-Item -Path "HKCU:\Software\Microsoft\Windows\Shell\Bags\1\Desktop" -Force | Out-Null
    # FFlags: on force AlignToGrid ON, AutoArrange OFF (valeur sûre)
New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\Shell\Bags\1\Desktop" -Name "FFlags" -Value 0x43000000 -PropertyType DWord -Force | Out-Null
  } catch {}
# 2) Arrêter Explorer avant import (évite les caches d’Explorer pendant l’écriture)
Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Wait-Process -Name explorer -Timeout 3 -ErrorAction SilentlyContinue
# 3) Importer toutes les branches liées au layout (depuis .\Registry)
$regDir = Join-Path $InDir 'Registry'
# Nettoyage prudent des caches d'Explorer (évite les merges hasardeux)
try {
  reg.exe delete "HKCU\Software\Microsoft\Windows\Shell\Bags"   /f | Out-Null
reg.exe delete "HKCU\Software\Microsoft\Windows\Shell\BagMRU" /f | Out-Null
reg.exe delete "HKCU\Software\Microsoft\Windows\Shell\Streams\Desktop" /f | Out-Null
} catch {}
foreach($f in 'bags.reg','bagmru.reg','desktopbag.reg','streamsdesk.reg','windowmetrics.reg'){
  $p = Join-Path $regDir $f
  if (Test-Path $p) { & reg.exe import "$p" 2>$null | Out-Null }
}
# 4) Redémarrer proprement Explorer (une passe suffit en général)
try {
  Start-Process explorer.exe
  Start-Sleep -Seconds 2
  if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) {
    Start-Process explorer.exe
  }
} catch {}
}
<#
  MigrationWizard.ps1 — Assistant portable d’export/import (Windows 11)
  - UI WPF à thème sombre
  - Sélection de dossiers (arbre tri-état), Wi-Fi, Imprimantes + pilotes (PrintBRM avec repli ciblé),
    Barre des tâches / Menu Démarrer (sans Import-StartLayout), fond d’écran + positions d’icônes,
    lecteurs réseau
  - Manifestes JSON/XML, logs, suivi de progression, lien « ouvrir le log »
  - Sélecteur de dossier amélioré : "Ce PC" (shell:Drives), repli WinForms
  - Résumé avant exécution + confirmation obligatoire
  - Page « Mots de passe navigateurs » (Chrome/Firefox/Edge) avant le résumé (Export) et après l’Import
  - OneDrive/KFM : export depuis OneDrive si redirection active, import vers dossiers locaux
#>
# --------- DEBUG ----------
$DebugUI = $false
$global:__KeepOpen = $false
trap {
  if (Get-Command -Name Log -CommandType Function -ErrorAction SilentlyContinue) {
    Log "TRAP: $($_.Exception.Message)"
    if ($_.InvocationInfo.PositionMessage){ Log ($_.InvocationInfo.PositionMessage) }
  } else {
    Write-Warning ("TRAP (early): " + $_.Exception.Message)
    if ($_.InvocationInfo.PositionMessage){ Write-Warning $_.InvocationInfo.PositionMessage }
  }
  continue
}
$ErrorActionPreference = 'Stop'
$script:EnableAclFix = $false
# --- Bootstrap : forcer Windows PowerShell 5.1 + STA + Admin (robuste et compatible ISE) ---
$ScriptPath = $PSCommandPath
if (-not $ScriptPath -or -not (Test-Path $ScriptPath)) { $ScriptPath = $MyInvocation.MyCommand.Path }
$curr    = [Security.Principal.WindowsIdentity]::GetCurrent()
$princ   = [Security.Principal.WindowsPrincipal]::new($curr)
$IsAdmin = $princ.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
# Vérification PS 5.1 (Desktop)
$IsPS51 = ($PSVersionTable.PSEdition -eq 'Desktop' -and $PSVersionTable.PSVersion.Major -eq 5)
$NeedSta = ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA')
$CanReinvoke = $ScriptPath -and (Test-Path $ScriptPath)
if ( ($NeedSta -or -not $IsAdmin -or -not $IsPS51) -and $CanReinvoke ) {
  try {
    $ps51 = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
    if (-not (Test-Path $ps51)) { $ps51 = "powershell.exe" } # Repli
    $args = @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-File',"`"$ScriptPath`"")
    $wd   = Split-Path -Path $ScriptPath -Parent
    # IMPORTANT : toujours RunAs ⇒ on garantit l’élévation (même si on l’était déjà)
    Start-Process -FilePath $ps51 -ArgumentList $args -Verb RunAs -WorkingDirectory $wd | Out-Null
    return  # pas de exit → n’interrompt pas ISE/Console
  } catch {
    Write-Warning "Relance PS5.1/STA/Admin impossible : $($_.Exception.Message). Poursuite sans réinvocation."
  }
} elseif (($NeedSta -or -not $IsAdmin -or -not $IsPS51) -and -not $CanReinvoke) {
  Write-Warning "Impossible de se relancer proprement (chemin du script inconnu). Poursuite sans réinvocation."
}
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Drawing
try { [void][System.Windows.Forms.Application] } catch { Add-Type -AssemblyName System.Windows.Forms }
# ---------- Helpers UI / Externes ----------
$Global:LogLines = New-Object System.Collections.ArrayList
$Global:LastLogPath = $null
function Invoke-UI { param([scriptblock]$Action)
  if ($null -eq $window) { & $Action; return }
  if ($window.Dispatcher.CheckAccess()) { & $Action }
  else { $window.Dispatcher.Invoke([Action]{ & $Action }) }
}
function Pump-UI { try { [System.Windows.Forms.Application]::DoEvents() } catch {} }
function New-ImageSourceFromBytes {
  param([Parameter(Mandatory)][byte[]]$Bytes)
  try {
    $ms = New-Object System.IO.MemoryStream
    $ms.Write($Bytes, 0, $Bytes.Length)
    $ms.Seek(0, [System.IO.SeekOrigin]::Begin) | Out-Null
    $img = New-Object System.Windows.Media.Imaging.BitmapImage
    $img.BeginInit()
    $img.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $img.StreamSource = $ms
    $img.EndInit()
    $img.Freeze()
    $ms.Dispose()
    return $img
  } catch {
    try { if ($ms) { $ms.Dispose() } } catch {}
    return $null
  }
}
function Run-External {
  param(
    [Parameter(Mandatory)] [string]$FilePath,
    [Parameter(Mandatory)] [string]$Arguments
  )
  try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = $Arguments
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow  = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    if (-not $p) {
      Log "Run-External: échec démarrage '$FilePath' avec args '$Arguments'"
      return 1
    }
    while(-not $p.HasExited){ Pump-UI; Start-Sleep -Milliseconds 100 }
    return $p.ExitCode
  } catch {
    Log "Run-External: exception '$FilePath' ($($_.Exception.Message))"
    return 1
  }
}
function Get-Options {
  try {
    return @{
      Wifi            = [bool]$cbWifi.IsChecked
      Printers        = [bool]$cbPrinters.IsChecked
      PrinterDrivers  = [bool]$cbPrinterDrivers.IsChecked
      Taskbar         = [bool]$cbTaskbar.IsChecked
      StartMenu       = [bool]$cbStartMenu.IsChecked
      Wallpaper       = [bool]$cbWallpaper.IsChecked
      DesktopPos      = [bool]$cbDesktopPos.IsChecked
      NetDrives       = [bool]$cbNetDrives.IsChecked
      QuickAccess     = if ($cbQuickAccess) { [bool]$cbQuickAccess.IsChecked } else { $false }
      RDP             = if ($cbRDP) { [bool]$cbRDP.IsChecked } else { $false }
      SkipCopy        = [bool]$cbSkipCopy.IsChecked
      FilterBig       = [bool]$cbFilterBig.IsChecked
      AppDataChrome   = [bool]$cbAppChrome.IsChecked
      AppDataEdge     = [bool]$cbAppEdge.IsChecked
      AppDataFirefox  = [bool]$cbAppFirefox.IsChecked
      AppDataOutlook  = if ($cbAppOutlook) { [bool]$cbAppOutlook.IsChecked } else { $false }
    }
  } catch {
    Log "Get-Options : $($_.Exception.Message)"
    return @{}
  }
}
function Log([string]$m){
  $line = "$(Get-Date -Format 's') - $m"
  $null = $Global:LogLines.Add($line)
  # --- Ajout en direct au fichier si déjà défini ---
  try {
    if ($Global:LastLogPath) {
      Add-Content -Path $Global:LastLogPath -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    }
  } catch {}
  Invoke-UI {
    if ($script:txtLog) {
      if (-not $script:txtLog.Document) { $script:txtLog.Document = New-Object System.Windows.Documents.FlowDocument }
      $p = New-Object System.Windows.Documents.Paragraph
      $p.Inlines.Add($line)
      $script:txtLog.Document.Blocks.Add($p)
      $script:txtLog.ScrollToEnd()
    }
  }
}
function Set-Progress([double]$v,[string]$t){
  Invoke-UI {
    if ($script:progressBar) { $script:progressBar.IsIndeterminate = $false; $script:progressBar.Value = [math]::Max(0,[math]::Min(100,$v)) }
    if ($script:lblProgress) { $script:lblProgress.Content = $t }
  }
}
# --------- Chemins de log robustes ----------
function Get-WritableLogPath {
  param([Parameter(Mandatory)] [string]$PreferredPath, [string]$FallbackKey = "import")
  try {
    $dir = Split-Path -Parent $PreferredPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    "test" | Set-Content -Path $PreferredPath -Encoding UTF8
    Remove-Item $PreferredPath -Force -ErrorAction SilentlyContinue
    return $PreferredPath
  } catch {
    $base = Join-Path $env:ProgramData "MigrationWizard\Logs"
    $leaf = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $name = "${FallbackKey}_$leaf.txt"
    New-Item -ItemType Directory -Force -Path $base | Out-Null
    return (Join-Path $base $name)
  }
}
function Write-LogToDisk {
  param([Parameter(Mandatory)] [string]$PrimaryPath,
        [Parameter(Mandatory)] [string]$FallbackKey)
  $final = Get-WritableLogPath -PreferredPath $PrimaryPath -FallbackKey $FallbackKey
try {
  $Global:LogLines | Set-Content -Path $final -Encoding UTF8
} catch {
  $final = Join-Path $env:TEMP ("MigrationWizard_" + [guid]::NewGuid().ToString("N") + ".txt")
  $Global:LogLines | Set-Content -Path $final -Encoding UTF8
  Log "ATTENTION: ProgramData inaccessible, log écrit dans %TEMP% -> $final"
}
  $Global:LastLogPath = $final
  return $final
}
function Update-LogLink {
  param([string]$Path)
  try {
    if ($lblLogPath) { $lblLogPath.Text = $Path }
    if ($hlLog) { $hlLog.NavigateUri = [Uri]"about:blank" } # click handler ouvre le fichier
  } catch {}
}
try {
  if ($hlLog) {
    $null = $hlLog.Add_Click({
      try {
        $p = $Global:LastLogPath
        if ($p -and (Test-Path $p)) { Start-Process -FilePath $p -ErrorAction SilentlyContinue }
      } catch { Log "Ouverture log : $($_.Exception.Message)" }
    })
  }
} catch {}
# --------- Profil interactif ----------
function Get-InteractiveUser {
  try {
    $sid = (Get-Process -Id $PID).SessionId
    $p = Get-Process explorer -IncludeUserName -ErrorAction SilentlyContinue |
         Where-Object { $_.SessionId -eq $sid } | Select-Object -First 1
    if ($p) { return $p.UserName }
  } catch {}
  try { return (Get-CimInstance Win32_ComputerSystem).UserName } catch { return $env:USERNAME }
}
$Account = Get-InteractiveUser
try {
  $Sid = (New-Object System.Security.Principal.NTAccount($Account)).Translate([System.Security.Principal.SecurityIdentifier]).Value
  $ProfilePath = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$Sid").ProfileImagePath
} catch { $ProfilePath = $env:USERPROFILE }
# --------- Helpers Shell Folders (conscients de KFM/OneDrive) ----------
function Get-UserShellFoldersRaw {
  try { Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' }
  catch { $null }
}
function Expand-Env {
  param([string]$s)
  if ([string]::IsNullOrWhiteSpace($s)) { return $s }
  return [Environment]::ExpandEnvironmentVariables($s)
}
function Get-KnownFolderPath {
  param([ValidateSet('Desktop','Documents','Downloads','Pictures','Music','Videos','Favorites','Links','Contacts')] [string]$Name)
  $raw = Get-UserShellFoldersRaw
  if (-not $raw) { return $null }
  $val = $null
  switch ($Name) {
    'Desktop'   { $val = $raw.Desktop }
    'Documents' { $val = $raw.Personal }
    'Downloads' { $val = $raw.'{374DE290-123F-4565-9164-39C4925E467B}' } # Downloads
    'Pictures'  { $val = $raw.'My Pictures' }
    'Music'     { $val = $raw.'My Music' }
    'Videos'    { $val = if ($raw.PSObject.Properties.Name -contains 'My Videos') { $raw.'My Videos' } else { $raw.'My Video' } }
    'Favorites' { $val = $raw.Favorites }
    'Links'     { $val = $raw.Links }
    'Contacts'  { $val = $raw.Contacts }
  }
  if ($val) { return (Expand-Env $val) }
  return $null
}
function Is-UnderOneDrive {
  param([string]$Path)
  try {
    if (-not $Path) { return $false }
    $p = (Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue)
    if ($p) { $Path = $p.Path }
  } catch {}
  $ods = @()
  if ($env:OneDrive) { $ods += $env:OneDrive }
  if ($env:OneDriveCommercial) { $ods += $env:OneDriveCommercial }
  if ($env:OneDriveConsumer) { $ods += $env:OneDriveConsumer }
  $accKeys = Get-ChildItem 'HKCU:\Software\Microsoft\OneDrive\Accounts' -ErrorAction SilentlyContinue
  foreach($k in $accKeys){
    try {
      $rp = (Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue).UserFolder
      if ($rp) { $ods += (Expand-Env $rp) }
    } catch {}
  }
  foreach($od in $ods){
    if ($od -and $Path -like "$od*") { return $true }
  }
  return $false
}
function Get-OneDriveRoots {
  $roots = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($v in @($env:OneDrive, $env:OneDriveCommercial, $env:OneDriveConsumer)) {
    if ($v) {
      $rp = Resolve-Path -LiteralPath $v -ErrorAction SilentlyContinue
      if ($rp) { [void]$roots.Add($rp.Path.TrimEnd('\')) }
    }
  }
  $acc = Get-ChildItem 'HKCU:\Software\Microsoft\OneDrive\Accounts' -ErrorAction SilentlyContinue
  foreach ($k in $acc) {
    try {
      $uf = (Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue).UserFolder
      if ($uf) {
        $uf = [Environment]::ExpandEnvironmentVariables($uf)
        $ru = Resolve-Path -LiteralPath $uf -ErrorAction SilentlyContinue
        if ($ru) { [void]$roots.Add($ru.Path.TrimEnd('\')) }
      }
    } catch {}
  }
  return $roots.ToArray()
}
function Resolve-OneDriveSubFolder {
  param([string]$Root,[string[]]$Names)
  foreach ($n in $Names) {
    $p = Join-Path $Root $n
    if (Test-Path -LiteralPath $p) { return (Resolve-Path -LiteralPath $p -ErrorAction SilentlyContinue).Path }
  }
  return $null
}
function Ensure-OneDriveHydrated {
  param([string]$Path,[int]$MaxSeconds = 180)
  try {
    $deadline = (Get-Date).AddSeconds($MaxSeconds)
    foreach ($f in Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue) {
  if ((Get-Date) -ge $deadline) { break }
  try {
    if ($f.Attributes.ToString() -match 'ReparsePoint|Offline') {
  $fs = [System.IO.File]::Open($f.FullName,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,[System.IO.FileShare]::ReadWrite)
  try { $buf = New-Object byte[] 1; $null = $fs.Read($buf,0,1) } finally { $fs.Dispose() }
}
      } catch { Log "OneDrive hydrate: $($_.FullName) -> $($_.Exception.Message)" }
    }
  } catch { Log "OneDrive hydrate root: $($_.Exception.Message)" }
}
function Export-OneDriveTrees {
  param([string]$OutDir)
  $map = @(
    @{ Names = @('Documents','Mes documents'); Target = 'Documents' }
    @{ Names = @('Pictures','Images','Photos'); Target = 'Pictures' }
    @{ Names = @('Desktop','Bureau');          Target = 'Desktop'  }
    @{ Names = @('Music','Musique');           Target = 'Music'    }
    @{ Names = @('Videos','Vidéos');           Target = 'Videos'   }
    @{ Names = @('Downloads','Téléchargements'); Target = 'Downloads' }
  )
  foreach ($root in Get-OneDriveRoots) {
    foreach ($m in $map) {
      $src = Resolve-OneDriveSubFolder -Root $root -Names $m.Names
      if ($src) {
        $dst = Join-Path $OutDir ("OneDrive\" + $m.Target)
        New-Item -ItemType Directory -Force -Path $dst | Out-Null
        Ensure-OneDriveHydrated -Path $src -MaxSeconds 180
        $rc = Run-External -FilePath "robocopy.exe" -Arguments ("`"$src`" `"$dst`" /E /COPY:DAT /DCOPY:T /ZB /FFT /R:1 /W:1 /XJ /SL /NFL /NDL /NP /MT:16")
if ($rc -ge 8) { Log "robocopy OneDrive export: code $rc ($src -> $dst)" } else { Log "Export OneDrive: $src -> $dst (rc=$rc)" }
      }
    }
  }
}
function Ensure-FreeSpace {
  param(
    [Parameter(Mandatory)][string]$TargetPath,
    [Parameter(Mandatory)][long]$NeededBytes
  )
  try {
$qual    = Split-Path -Path $TargetPath -Qualifier
# Si UNC, on ne sait pas mesurer proprement -> on journalise et on laisse passer
if ($qual -like '\\*') {
  Log "Check espace disque ignoré (UNC: $qual)"
  return $true
}
$drvName = $qual.TrimEnd(':')
$drive   = Get-PSDrive -Name $drvName -ErrorAction Stop
$free  = $drive.Free
    if ($free -lt $NeededBytes) {
      throw "Espace disque insuffisant sur $($drive.Name): libre=$([math]::Round($free/1GB,2)) GB, requis=$([math]::Round($NeededBytes/1GB,2)) GB"
    }
    return $true
  } catch {
    Log "Check espace disque : $($_.Exception.Message)"
    return $false
  }
}
function Import-OneDriveTrees {
  param([string]$InDir)
  $map = @{
    'Documents'  = Join-Path $env:USERPROFILE 'Documents'
    'Pictures'   = Join-Path $env:USERPROFILE 'Pictures'
    'Desktop'    = Join-Path $env:USERPROFILE 'Desktop'
    'Music'      = Join-Path $env:USERPROFILE 'Music'
    'Videos'     = Join-Path $env:USERPROFILE 'Videos'
    'Downloads'  = Join-Path $env:USERPROFILE 'Downloads'
  }
  foreach ($k in $map.Keys) {
    $src = Join-Path $InDir ("OneDrive\" + $k)
    if (Test-Path -LiteralPath $src) {
      $dst = $map[$k]
      New-Item -ItemType Directory -Force -Path $dst | Out-Null
      $args = "`"$src`" `"$dst`" /E /COPY:DAT /DCOPY:T /ZB /FFT /R:1 /W:1 /XJ /SL /NFL /NDL /NP /MT:16"
      $rc = Run-External -FilePath "robocopy.exe" -Arguments $args
      if ($rc -ge 8) { Log "robocopy OneDrive ($k): code $rc (erreur) $src -> $dst" } else { Log "✔ OneDrive ($k) copié (rc=$rc)" }
      try { Log "Import OneDrive ($k): $src -> $dst" } catch {}
    }
  }
}
function Get-ExportSourceForPath {
  param([Parameter(Mandatory)][string]$SelectedPath)
  $map = @{
    'Desktop'   = (Join-Path $ProfilePath 'Desktop')
    'Documents' = (Join-Path $ProfilePath 'Documents')
    'Downloads' = (Join-Path $ProfilePath 'Downloads')
    'Pictures'  = (Join-Path $ProfilePath 'Pictures')
    'Music'     = (Join-Path $ProfilePath 'Music')
    'Videos'    = (Join-Path $ProfilePath 'Videos')
    'Favorites' = (Join-Path $ProfilePath 'Favorites')
    'Links'     = (Join-Path $ProfilePath 'Links')
    'Contacts'  = (Join-Path $ProfilePath 'Contacts')
  }
  foreach($k in $map.Keys){
    $std = $map[$k]
    if ($SelectedPath -ieq $std) {
      $real = Get-KnownFolderPath -Name $k
      if ($real -and (Test-Path $real)) { return $real }
    }
  }
  return $SelectedPath
}
# --------- Copie ----------
$Global:ExcludePatterns = @()
$Global:ExcludePatternsFiles = @()
$Global:ExcludePatternsDirs  = @()
$Global:MaxFileSizeMB   = $null
function Copy-Tree {
  param([string]$src,[string]$dst)
  if (-not (Test-Path -LiteralPath $src)) { Log "MISSING: $src"; return }
  if (-not (Test-Path -LiteralPath $dst)) { New-Item -ItemType Directory -Path $dst -Force | Out-Null }
  Log "→ Copie: $src -> $dst"

  # Arguments fixes (liste simple), on encapsule ensuite les chemins entre guillemets
  $baseArgs = @(
    '/E','/R:1','/W:1','/MT:16','/COPY:DAT','/DCOPY:T','/ZB','/FFT',
    '/NP','/NFL','/NDL','/XJ','/SL'
  )

  # Construire l'array final en s'assurant que les chemins sont correctement cités
  $quotedSrc = '"' + $src + '"'
  $quotedDst = '"' + $dst + '"'
  $argsList = @($quotedSrc, $quotedDst) + $baseArgs

  if ($Global:LastLogPath) {
    $rlog = [System.IO.Path]::ChangeExtension($Global:LastLogPath, ".robocopy.log")
    $argsList += '/TEE','/NJH','/NJS',('/LOG:' + '"' + $rlog + '"')
  }

  # Exclusions (XF/XD) : ajouter proprement
  $exFiles = @($Global:ExcludePatternsFiles)
  $exDirs  = @($Global:ExcludePatternsDirs)
  if ($Global:ExcludePatterns) {
    $exFiles = @($exFiles + $Global:ExcludePatterns)
    $exDirs  = @($exDirs  + $Global:ExcludePatterns)
  }
  foreach($pat in ($exFiles | Where-Object { $_ -and $_ -ne '' } | Select-Object -Unique)) {
    $argsList += ('/XF ' + '"' + $pat + '"')
  }
  foreach($pat in ($exDirs | Where-Object { $_ -and $_ -ne '' } | Select-Object -Unique)) {
    $argsList += ('/XD ' + '"' + $pat + '"')
  }

  # /MAX si demandé
  if ($Global:MaxFileSizeMB -and ($src -notmatch '\\Microsoft\\Outlook($|\\)')) {
    $maxBytes = [long]$Global:MaxFileSizeMB * 1048576
    $argsList += ("/MAX:$maxBytes")
  }

  # Exécuter robocopy en joignant avec un espace
  $argsStr = $argsList -join ' '
  $rc = Run-External -FilePath "robocopy.exe" -Arguments $argsStr
  if ($rc -ge 8) { Log "robocopy: code $rc (erreur) pour $src -> $dst" }
  else { Log "✔ Dossier copié: $src -> $dst" }
}
# --------- Verrouillage de l’arbre ----------
$script:TreeBusy = $false
# --------- Helpers tri-état ----------
function Ensure-Children([System.Windows.Controls.TreeViewItem]$item){
  if ($null -eq $item) { return }
  if ( ($item.Items.Count -eq 1) -and ($item.Items[0] -eq "*") ) {
    $item.Items.Clear()
    try {
      $hdrTag = $item.Header.Tag
      $dir = $null
      if ($hdrTag) {
        if (($hdrTag.PSObject.Properties.Name -contains 'Src') -and $hdrTag.Src) { $dir = $hdrTag.Src }
        else { $dir = $hdrTag.Path }
      }
      if ($dir) {
        $showHidden = [bool]$cbShowHidden.IsChecked
        $items = Get-ChildItem -Path $dir -Directory -ErrorAction Stop
        if (-not $showHidden) {
          $items = $items | Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::Hidden) }
        }
        foreach($child in $items){
          $parentTag = $item.Header.Tag
          $node = $null
          if ($parentTag -and ($parentTag.PSObject.Properties.Name -contains 'Src') -and $parentTag.Src) {
            $childSrc  = $child.FullName
            $childDest = Join-Path $parentTag.Path $child.Name
            $node = New-Node -path $childDest -label $child.Name -srcPath $childSrc
          } else {
            $node = New-Node -path $child.FullName -label $child.Name
          }
          $item.Items.Add($node) | Out-Null
        }
      }
    } catch {}
  }
}
function Set-ChildrenState([System.Windows.Controls.TreeViewItem]$item, $state){
  if ($null -eq $item) { return }
  Ensure-Children $item
  foreach($c in $item.Items){
    if ($c -is [System.Windows.Controls.TreeViewItem]) {
      $c.Header.IsChecked = $state
      Set-ChildrenState -item $c -state $state
    }
  }
}
function Update-ParentState([System.Windows.Controls.TreeViewItem]$child){
  $item = $child
  while ($item.Parent -is [System.Windows.Controls.TreeViewItem]) {
    $parent = [System.Windows.Controls.TreeViewItem]$item.Parent
    Ensure-Children $parent
    $states = @()
    foreach($c in $parent.Items){
      if ($c -is [System.Windows.Controls.TreeViewItem]) { $states += $c.Header.IsChecked }
    }
    $allTrue  = ($states -notcontains $false) -and ($states -notcontains $null)
    $allFalse = ($states -notcontains $true)  -and ($states -notcontains $null)
    $new = $null
    if ($allFalse) { $new = $false }
    elseif ($allTrue) { $new = $true }
    else { $new = $null }
    $parent.Header.IsChecked = $new
    $item = $parent
  }
}
function Set-NodeRecursive([System.Windows.Controls.TreeViewItem]$item, $state){
  if ($null -eq $item) { return }
  Ensure-Children $item
  $item.Header.IsChecked = $state
  foreach($c in $item.Items){
    if ($c -is [System.Windows.Controls.TreeViewItem]) { Set-NodeRecursive -item $c -state $state }
  }
}
function Check-AllTreeItems([bool]$state = $true){
  if ($null -eq $treeFolders) { return }
 $disp = [System.Windows.Threading.Dispatcher]::CurrentDispatcher.DisableProcessing()
  try {
    $script:TreeBusy = $true
    foreach($it in $treeFolders.Items){
      if ($it -is [System.Windows.Controls.TreeViewItem]) { Set-NodeRecursive -item $it -state $state }
    }
  } finally {
    $script:TreeBusy = $false
    if ($disp){ $disp.Dispose() }
  }
  Update-NextAndExclusivity
}
# --------- Sélection / Exclusivité / Suivant ----------
$SelectNodes = New-Object System.Collections.Generic.List[System.Windows.Controls.CheckBox]
function Get-SelectedPaths {
  $raw = @()
  foreach($chk in $SelectNodes){
    if ($chk.IsChecked -eq $true) {
      $p = $null
      if ($chk.Tag) {
        if ($chk.Tag.PSObject.Properties.Name -contains 'Path') { $p = $chk.Tag.Path }
        else { $p = [string]$chk.Tag }
      }
      if ($p) { $raw += [string]$p }
    }
  }
  $out = @()
  foreach($x in $raw){
    if ($x) { $t = $x.Trim(); if ($t -ne '') { $out += $t } }
  }
  @($out | Sort-Object -Unique)
}
function Clear-FolderSelection { foreach($chk in $SelectNodes){ if ($chk.IsChecked){ $chk.IsChecked = $false } } }
function Update-NextAndExclusivity {
  try {
    $skip = $false
    if ($cbSkipCopy -and $cbSkipCopy.PSObject.Properties.Name -contains 'IsChecked') {
      $skip = [bool]$cbSkipCopy.IsChecked
    }
    $hasFolders = $false
    try { $hasFolders = (@(Get-SelectedPaths)).Count -gt 0 } catch {}
    if ($skip -and $hasFolders) { Clear-FolderSelection; $hasFolders = $false }
    if ($treeFolders) { $treeFolders.IsEnabled = -not $skip }
    if ($script:CurrentPage -eq 2 -and $btnNext) { $btnNext.IsEnabled = ($skip -or $hasFolders) }
  } catch {
    Log "Update-NextAndExclusivity: $($_.Exception.Message)"
  }
}
function On-CheckChanged($chk){
  if ($script:TreeBusy) { return }
  $meta = $chk.Tag; $item = $meta.Item
  if ($null -eq $item) { return }
  $disp = [System.Windows.Threading.Dispatcher]::CurrentDispatcher.DisableProcessing()
  try {
    $script:TreeBusy = $true
    if ($chk.IsChecked -eq $null) { $chk.IsChecked = $false }
    Set-ChildrenState -item $item -state $chk.IsChecked
    Update-ParentState -child $item
  } finally { $script:TreeBusy = $false; if ($disp){ $disp.Dispose() } }
  Update-NextAndExclusivity
  Update-Summary
}
function Detect-OutlookInstalled {
  try {
    $regPaths = @(
      "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\OUTLOOK.EXE",
      "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\OUTLOOK.EXE"
    )
    foreach($k in $regPaths){
      try {
        $it = Get-Item -Path $k -ErrorAction SilentlyContinue
        if ($it) {
          $p = $it.GetValue('')
          if ($p) {
            $exe = ($p -replace '^\u0022|\u0022$','')
            if (Test-Path -LiteralPath $exe) {
              return [pscustomobject]@{ Installed = $true; Path = (Resolve-Path $exe).Path }
            }
          }
        }
      } catch { Log "Detect-OutlookInstalled: $($_.Exception.Message)" }
    }
  } catch { Log "Detect-OutlookInstalled root: $($_.Exception.Message)" }
  return [pscustomobject]@{ Installed = $false; Path = $null }
}
function Export-AppDataOutlook {
  param([Parameter(Mandatory)][string]$OutRoot)
  $oldExF = $Global:ExcludePatternsFiles
  try {
    $base = Join-Path $OutRoot 'AppDataOutlook'
    New-Item -ItemType Directory -Force -Path $base | Out-Null
    # Exclure fichiers OST (archives Outlook volumineuses) pendant cette opération
    $Global:ExcludePatternsFiles = @($oldExF + '*.ost')
    $loc = Join-Path $env:LOCALAPPDATA 'Microsoft\Outlook'
    $rom1= Join-Path $env:APPDATA      'Microsoft\Outlook'
    $rom2= Join-Path $env:APPDATA      'Microsoft\Signatures'
    if (Test-Path $loc)  { Copy-Tree -src $loc  -dst (Join-Path $base 'Local\Microsoft\Outlook') }
    if (Test-Path $rom1) { Copy-Tree -src $rom1 -dst (Join-Path $base 'Roaming\Microsoft\Outlook') }
    if (Test-Path $rom2) { Copy-Tree -src $rom2 -dst (Join-Path $base 'Roaming\Microsoft\Signatures') }
    Log "AppData Outlook exporté."
  } catch {
    Log "Export AppData Outlook : $($_.Exception.Message)"
} finally {
    $Global:ExcludePatternsFiles = $oldExF
  }
}
function Import-AppDataOutlook {
  param([Parameter(Mandatory)][string]$InRoot)
  try {
    $base = Join-Path $InRoot 'AppDataOutlook'
    if (-not (Test-Path $base)) { Log "AppDataOutlook absent — rien à restaurer."; return }
    $dst1 = Join-Path $env:LOCALAPPDATA 'Microsoft\Outlook'
    $dst2 = Join-Path $env:APPDATA      'Microsoft\Outlook'
    $dst3 = Join-Path $env:APPDATA      'Microsoft\Signatures'
    if (Test-Path (Join-Path $base 'Local\Microsoft\Outlook'))      { New-Item -ItemType Directory -Force -Path $dst1 | Out-Null; Copy-Tree -src (Join-Path $base 'Local\Microsoft\Outlook')    -dst $dst1 }
    if (Test-Path (Join-Path $base 'Roaming\Microsoft\Outlook'))    { New-Item -ItemType Directory -Force -Path $dst2 | Out-Null; Copy-Tree -src (Join-Path $base 'Roaming\Microsoft\Outlook')  -dst $dst2 }
    if (Test-Path (Join-Path $base 'Roaming\Microsoft\Signatures')) { New-Item -ItemType Directory -Force -Path $dst3 | Out-Null; Copy-Tree -src (Join-Path $base 'Roaming\Microsoft\Signatures') -dst $dst3 }
    Log "AppData Outlook importé."
  } catch { Log "Import AppData Outlook : $($_.Exception.Message)" }
}
function Export-ExplorerQuickAccess {
  param([Parameter(Mandatory)][string]$OutRoot)
  try {
    $base = Join-Path $OutRoot 'ExplorerQuickAccess'
    New-Item -ItemType Directory -Force -Path $base | Out-Null
    $src1 = Join-Path $env:APPDATA 'Microsoft\Windows\Recent\AutomaticDestinations'
    $src2 = Join-Path $env:APPDATA 'Microsoft\Windows\Recent\CustomDestinations'
    if (Test-Path $src1) { Copy-Tree -src $src1 -dst (Join-Path $base 'AutomaticDestinations') }
    if (Test-Path $src2) { Copy-Tree -src $src2 -dst (Join-Path $base 'CustomDestinations') }
    Log "Accès rapide exporté."
  } catch {
    Log "Export QuickAccess : $($_.Exception.Message)"
  }
}
function Import-ExplorerQuickAccess {
  param([Parameter(Mandatory)][string]$InRoot)
  try {
    $base = Join-Path $InRoot 'ExplorerQuickAccess'
    if (-not (Test-Path $base)) { Log "QuickAccess absent — rien à restaurer."; return }
    $dst1 = Join-Path $env:APPDATA 'Microsoft\Windows\Recent\AutomaticDestinations'
    $dst2 = Join-Path $env:APPDATA 'Microsoft\Windows\Recent\CustomDestinations'
    if (Test-Path (Join-Path $base 'AutomaticDestinations')) {
      Copy-Tree -src (Join-Path $base 'AutomaticDestinations') -dst $dst1
    }
    if (Test-Path (Join-Path $base 'CustomDestinations')) {
      Copy-Tree -src (Join-Path $base 'CustomDestinations') -dst $dst2
    }
    Log "Accès rapide importé."
  } catch {
    Log "Import QuickAccess : $($_.Exception.Message)"
  }
}
function Export-RDPConnections {
  param([Parameter(Mandatory)][string]$OutRoot)
  try {
    $base = Join-Path $OutRoot 'RDP'
New-Item -ItemType Directory -Force -Path $base | Out-Null
$defRdp = Join-Path $env:USERPROFILE 'Documents\default.rdp'
if (Test-Path $defRdp) {
  Copy-Item $defRdp (Join-Path $base 'default.rdp') -Force
}
$regFile = Join-Path $base 'Servers_HKCU.reg'
try {
  $psKey  = "HKCU:\Software\Microsoft\Terminal Server Client\Servers"
  $rawKey = "HKCU\Software\Microsoft\Terminal Server Client\Servers"
  if (Test-Path $psKey) {
    $props = Get-ItemProperty -Path $psKey -ErrorAction SilentlyContinue
    if ($props -and ($props.PSObject.Properties.Count -gt 0)) {
      & reg.exe export $rawKey "$regFile" /y 2>$null | Out-Null
      Log "RDP Servers exporté → $regFile"
    } else {
      Log "RDP Servers présent mais vide — export ignoré."
    }
  } else {
    Log "RDP Servers absent — export ignoré."
  }
} catch {
  Log "Export RDP Servers : $($_.Exception.Message)"
}
Log "Connexions RDP: export terminé."
  } catch {
    Log "Export RDP : $($_.Exception.Message)"
  }
}
function Import-RDPConnections {
  param([Parameter(Mandatory)][string]$InRoot)
  try {
    $base = Join-Path $InRoot 'RDP'
    if (-not (Test-Path $base)) { Log "RDP absent — rien à restaurer."; return }
    $defRdp = Join-Path $base 'default.rdp'
    if (Test-Path $defRdp) {
      Copy-Item $defRdp (Join-Path $env:USERPROFILE 'Documents\default.rdp') -Force
    }
    $regFile = Join-Path $base 'Servers_HKCU.reg'
    if (Test-Path $regFile) { & reg.exe import "$regFile" 2>$null | Out-Null }
    Log "Connexions RDP importées."
  } catch {
    Log "Import RDP : $($_.Exception.Message)"
  }
}
# --------- TreeView / New-Node ----------
function New-Node {
  param([string]$path,[string]$label,[string]$srcPath)
  $chk = New-Object System.Windows.Controls.CheckBox
  $chk.Content = $label
  $chk.IsThreeState = $true
  if ($srcPath) { $meta = [pscustomobject]@{ Path = $path; Src = $srcPath; Item = $null } }
  else { $meta = [pscustomobject]@{ Path = $path; Item = $null } }
  $chk.Tag = $meta
  $item = New-Object System.Windows.Controls.TreeViewItem
  $item.Header = $chk
  $item.Items.Add("*") | Out-Null
  $meta.Item = $item
  $null = $item.Add_Expanded({ param($s,$e) Ensure-Children ([System.Windows.Controls.TreeViewItem]$s) })
  $null = $chk.Add_Checked({       param($s,$e) On-CheckChanged $s })
  $null = $chk.Add_Unchecked({     param($s,$e) On-CheckChanged $s })
  $null = $chk.Add_Indeterminate({ param($s,$e) On-CheckChanged $s })
  $SelectNodes.Add($chk) | Out-Null
  return $item
}
# --------- XAML ----------
$xamlText = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Assistant de Migration (Portable)" Height="720" Width="1080"
        WindowStartupLocation="CenterScreen" Background="#0b1220">
  <Window.Resources>
    <SolidColorBrush x:Key="PanelDark" Color="#111827"/>
    <SolidColorBrush x:Key="Ink" Color="#e8eefc"/>
    <SolidColorBrush x:Key="Accent" Color="#263147"/>
    <Style TargetType="TextBlock"><Setter Property="Foreground" Value="{StaticResource Ink}"/></Style>
    <Style TargetType="Label"><Setter Property="Foreground" Value="{StaticResource Ink}"/></Style>
    <Style TargetType="CheckBox"><Setter Property="Foreground" Value="{StaticResource Ink}"/><Setter Property="FontWeight" Value="SemiBold"/></Style>
    <Style TargetType="Button"><Setter Property="Margin" Value="6"/></Style>
    <Style TargetType="TextBox"><Setter Property="Margin" Value="6"/><Setter Property="Background" Value="{StaticResource PanelDark}"/><Setter Property="Foreground" Value="{StaticResource Ink}"/><Setter Property="BorderBrush" Value="{StaticResource Accent}"/></Style>
    <Style TargetType="TreeView"><Setter Property="Background" Value="{StaticResource PanelDark}"/><Setter Property="Foreground" Value="{StaticResource Ink}"/><Setter Property="BorderBrush" Value="{StaticResource Accent}"/><Setter Property="BorderThickness" Value="1"/><Setter Property="FontSize" Value="14"/></Style>
    <Style TargetType="TreeViewItem"><Setter Property="Foreground" Value="{StaticResource Ink}"/></Style>
    <Style TargetType="GroupBox"><Setter Property="Foreground" Value="{StaticResource Ink}"/><Setter Property="BorderBrush" Value="{StaticResource Accent}"/></Style>
  </Window.Resources>
  <Grid Margin="16">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <DockPanel Grid.Row="0" Margin="0 0 0 8" LastChildFill="False">
      <Image Name="imgLogo"
             DockPanel.Dock="Right"
             Width="501" Height="167"
             Stretch="Uniform"
             Margin="0,0,8,0"
             HorizontalAlignment="Right"
             VerticalAlignment="Center"
             RenderOptions.BitmapScalingMode="HighQuality"
             SnapsToDevicePixels="True"/>
      <TextBlock Text="Assistant de Migration" FontSize="22" FontWeight="Bold"/>
      <TextBlock Text=" — By JMT" Foreground="#a8b2d1" Margin="8,8,0,0"/>
    </DockPanel>
    <Grid Grid.Row="1" Name="pageHost">
      <Grid Name="page1">
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
        <StackPanel Orientation="Vertical">
          <TextBlock Text="Que souhaites-tu faire ?" FontSize="18" Margin="0 0 0 12"/>
          <StackPanel Orientation="Horizontal">
            <RadioButton Name="rbExport" Content="Exporter depuis cet ordinateur" IsChecked="True" Foreground="{StaticResource Ink}" Margin="6"/>
            <RadioButton Name="rbImport" Content="Importer vers cet ordinateur" Foreground="{StaticResource Ink}" Margin="6"/>
          </StackPanel>
        </StackPanel>
        <Border Grid.Row="1" Margin="0,12,0,0" Padding="12" BorderBrush="{StaticResource Accent}" BorderThickness="1" CornerRadius="8" Background="{StaticResource PanelDark}">
          <TextBlock>
            <Run Text="Utilisateur interactif : "/><Run Text="" Name="txtUser"/>
            <LineBreak/><Run Text="Profil : "/><Run Text="" Name="txtProfile"/>
            <LineBreak/><Run Text="Conseil : Exécuter en Administrateur pour Wi-Fi, Imprimantes, Taskbar."/>
          </TextBlock>
        </Border>
      </Grid>
      <Grid Name="page2" Visibility="Collapsed">
        <Grid.ColumnDefinitions><ColumnDefinition Width="2*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
        <Grid Grid.Column="0" Margin="0,0,8,0">
          <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <GroupBox Header="Dossiers à inclure" Grid.Row="0">
            <Grid Background="{StaticResource PanelDark}">
              <TreeView Name="treeFolders"
          ScrollViewer.VerticalScrollBarVisibility="Auto"
          ScrollViewer.CanContentScroll="True"
          VirtualizingStackPanel.IsVirtualizing="True"
          VirtualizingStackPanel.VirtualizationMode="Recycling"/>
            </Grid>
          </GroupBox>
          <GroupBox Grid.Row="1" Margin="0,8,0,0" Padding="8" BorderThickness="1">
            <GroupBox.Background>
              <SolidColorBrush Color="White"/>
            </GroupBox.Background>
            <StackPanel Orientation="Vertical">
              <CheckBox Name="cbSkipCopy"
                        Content="Ne pas copier de fichiers (sauter la phase dossiers)"
                        IsChecked="False"
                        Foreground="Black"/>
            </StackPanel>
          </GroupBox>
        </Grid>
        <StackPanel Grid.Column="1">
          <GroupBox Header="Options" Margin="0,0,0,8">
            <StackPanel Background="{StaticResource PanelDark}" Margin="6">
              <CheckBox Name="cbWifi"            Content="Wi-Fi (profils XML)"         IsChecked="True"/>
<CheckBox Name="cbPrinters"        Content="Imprimantes (queues)"        IsChecked="True"/>
<CheckBox Name="cbPrinterDrivers"  Content="Pilotes d’imprimantes"       IsChecked="True"/>
<CheckBox Name="cbTaskbar"         Content="Barre des tâches"            IsChecked="True"/>
<CheckBox Name="cbStartMenu"       Content="Menu Démarrer"               IsChecked="True"/>
<CheckBox Name="cbWallpaper"       Content="Fond d’écran"                IsChecked="True"/>
<CheckBox Name="cbDesktopPos"      Content="Positions d’icônes"          IsChecked="True"/>
<CheckBox Name="cbNetDrives"       Content="Lecteurs réseau mappés"      IsChecked="True"/>
<CheckBox Name="cbQuickAccess"    Content="Accès rapide de l’Explorateur" IsChecked="True"/>
<CheckBox Name="cbRDP"            Content="Connexions RDP (default.rdp + Reg HKCU)" IsChecked="True"/>
            </StackPanel>
          </GroupBox>
          <GroupBox Header="Mode">
            <StackPanel Background="{StaticResource PanelDark}" Margin="6">
              <CheckBox Name="cbShowHidden" Content="Afficher dossiers cachés" IsChecked="True"/>
              <CheckBox Name="cbFilterBig" Content="Exclure fichiers volumineux (ISO/VM…)" IsChecked="False"/>
            </StackPanel>
          </GroupBox>
  <GroupBox Header="AppData navigateurs &amp; Outlook" Margin="0,8,0,0">
  <StackPanel Background="{StaticResource PanelDark}" Margin="6">
    <CheckBox Name="cbAppChrome"   Content="AppData Chrome"    IsChecked="False"/>
    <CheckBox Name="cbAppEdge"     Content="AppData Edge"      IsChecked="False"/>
    <CheckBox Name="cbAppFirefox"  Content="AppData Firefox"   IsChecked="False"/>
    <CheckBox Name="cbAppOutlook"  Content="AppData Outlook"   IsChecked="False"/>
  </StackPanel>
</GroupBox>
        </StackPanel>
      </Grid>
      <Grid Name="pagePasswords" Visibility="Collapsed">
        <StackPanel>
          <TextBlock Name="lblPwTitle" Text="Merci d’exporter les mots de passe des navigateurs ci-dessous, puis cliquez sur Suivant."
                     FontSize="18" Margin="0,0,0,12" TextWrapping="Wrap"/>
          <UniformGrid Name="gridPwTiles" Columns="3" Rows="1" Margin="0,6,0,0"/>
        </StackPanel>
      </Grid>
      <Grid Name="page3" Visibility="Collapsed">
        <StackPanel>
          <StackPanel Name="panelExport" Visibility="Collapsed" Background="{StaticResource PanelDark}" Margin="6">
            <TextBlock Text="Nom du client (sera le nom du dossier d’export) :"/>
            <TextBox Name="tbClientName" />
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
              <TextBlock Text="Dossier destination :"/>
              <TextBox Name="tbExportDest" Width="520" IsReadOnly="True"/>
              <Button Name="btnPickExport" Content="Parcourir..."/>
            </StackPanel>
          </StackPanel>
          <StackPanel Name="panelImport" Visibility="Collapsed" Background="{StaticResource PanelDark}" Margin="6">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
              <TextBlock Text="Dossier client (export) :"/>
              <TextBox Name="tbImportSrc" Width="520" IsReadOnly="True"/>
              <Button Name="btnPickImport" Content="Parcourir..."/>
            </StackPanel>
            <StackPanel Orientation="Horizontal" Margin="0,6,0,0">
              <TextBlock Text="Nom du client :" VerticalAlignment="Center"/>
              <TextBox Name="tbImportClient" Width="260" Margin="6,0,0,0" IsReadOnly="True"/>
            </StackPanel>
            <TextBlock Text="Le contenu sera intégré depuis ce dossier." Foreground="#a8b2d1"/>
          </StackPanel>
<GroupBox Header="Résumé avant exécution" Background="{StaticResource PanelDark}" Margin="6">
  <Grid Margin="6">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <!-- Zone de résumé avec barre de défilement -->
<TextBox Name="txtSummary"
         Grid.Row="0"
         IsReadOnly="True"
         TextWrapping="Wrap"
         VerticalScrollBarVisibility="Auto"
         HorizontalScrollBarVisibility="Disabled"
         Background="{StaticResource PanelDark}"
         Foreground="{StaticResource Ink}"
         BorderBrush="{StaticResource Accent}"
         Height="240"
         Margin="0,0,0,8"/>
    <!-- Confirmation toujours accessible -->
    <StackPanel Grid.Row="1" Orientation="Horizontal" VerticalAlignment="Center">
      <CheckBox Name="cbConfirm" Content="Je confirme ce plan d’exécution" IsChecked="False"/>
    </StackPanel>
  </Grid>
</GroupBox>
        </StackPanel>
      </Grid>
      <Grid Name="page4" Visibility="Collapsed">
        <StackPanel>
          <TextBlock Text="Exécution en cours…" FontSize="18" Margin="0,0,0,8"/>
          <ProgressBar Name="progressBar" Height="18" Minimum="0" Maximum="100"/>
          <Label Name="lblProgress" Content=""/>
          <RichTextBox Name="txtLog" Height="400" IsReadOnly="True" VerticalScrollBarVisibility="Auto"
                       Background="{StaticResource PanelDark}" Foreground="{StaticResource Ink}" BorderBrush="{StaticResource Accent}"/>
        </StackPanel>
      </Grid>
      <Grid Name="page5" Visibility="Collapsed">
        <StackPanel>
          <TextBlock Text="Terminé ✅" FontSize="18" Margin="0,0,0,8"/>
          <TextBlock Text="Un log détaillé est disponible."/>
          <TextBlock>
            <Run Text="Log : "/>
            <Hyperlink Name="hlLog"><Run Text="ouvrir le log"/></Hyperlink>
          </TextBlock>
          <TextBlock Name="lblLogPath" Foreground="#a8b2d1" TextWrapping="Wrap"/>
        </StackPanel>
      </Grid>
    </Grid>
    <DockPanel Grid.Row="2" Margin="0,8,0,0">
      <StackPanel Orientation="Horizontal" DockPanel.Dock="Right">
        <Button Name="btnPrev" Content="↵ Précédent" IsEnabled="False"/>
        <Button Name="btnNext" Content="Suivant ↦"/>
        <Button Name="btnRun" Content="Lancer" Visibility="Collapsed"/>
        <Button Name="btnClose" Content="Fermer" Visibility="Collapsed"/>
      </StackPanel>
    </DockPanel>
  </Grid>
</Window>
"@
# --------- Construction de l’interface WPF ----------
try {
  $window = [Windows.Markup.XamlReader]::Parse($xamlText)
} catch {
  [System.Windows.MessageBox]::Show("Erreur XAML : $($_.Exception.Message)","Erreur",
    [System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Error) | Out-Null
  return
}
function F($n){ $window.FindName($n) }
# --------- Association des contrôles ----------
$rbExport = F 'rbExport'; $rbImport = F 'rbImport'
$page1=F 'page1'; $page2=F 'page2'; $page3=F 'page3'; $page4=F 'page4'; $page5=F 'page5'
$pagePasswords = F 'pagePasswords'; $lblPwTitle = F 'lblPwTitle'; $gridPwTiles = F 'gridPwTiles'
$txtUser = F 'txtUser'; $txtProfile = F 'txtProfile'
$treeFolders = F 'treeFolders'
$cbWifi=F 'cbWifi'
$cbPrinters=F 'cbPrinters'; $cbPrinterDrivers=F 'cbPrinterDrivers'
$cbTaskbar=F 'cbTaskbar';   $cbStartMenu=F 'cbStartMenu'
$cbWallpaper=F 'cbWallpaper'; $cbDesktopPos=F 'cbDesktopPos'
$cbNetDrives=F 'cbNetDrives'
$cbShowHidden=F 'cbShowHidden'; $cbFilterBig=F 'cbFilterBig'; $cbSkipCopy=F 'cbSkipCopy'
$cbAppChrome   = F 'cbAppChrome'
$cbAppEdge     = F 'cbAppEdge'
$cbAppFirefox  = F 'cbAppFirefox'
$cbAppOutlook  = F 'cbAppOutlook'
$panelExport=F 'panelExport'; $panelImport=F 'panelImport'
$tbClientName=F 'tbClientName'; $tbExportDest=F 'tbExportDest'; $btnPickExport=F 'btnPickExport'
$tbImportSrc=F 'tbImportSrc'; $btnPickImport=F 'btnPickImport'
$tbImportClient = F 'tbImportClient'
$btnPrev=F 'btnPrev'; $btnNext=F 'btnNext'; $btnRun=F 'btnRun'; $btnClose=F 'btnClose'
# Garde-fou pour éviter double attachement
if (-not $script:HandlersWired) { $script:HandlersWired = $false }

if (-not $script:HandlersWired) {
  $btnRun.Add_Click({
    try {
      if (-not [bool]$cbConfirm.IsChecked) {
        [System.Windows.MessageBox]::Show("Merci de confirmer le plan d’exécution avant de lancer.","Info",
          [System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Information) | Out-Null
        return
      }
      if ($script:IsExport) { Run-Export-Safe } else { Run-Import-Safe }
    } catch { Log "btnRun Safe : $($_.Exception.Message)" }
  })

  $script:HandlersWired = $true
}
# --- Alias rétro-compatibilité (anciens noms utilisés ailleurs)
$BtnPrecedent = $btnPrev
$BtnSuivant   = $btnNext
$BtnTerminer  = $btnRun
$BtnFermer    = $btnClose
# --- État de navigation ---
$script:CurrentPage = 1      # ← évite un null au premier "Suivant"
$script:IsExport    = $true  # ← par défaut (rbExport coché)
$progressBar=F 'progressBar'; $lblProgress=F 'lblProgress'; $txtLog=F 'txtLog'
$hlLog = F 'hlLog'; $lblLogPath = F 'lblLogPath'
$hlLog.NavigateUri = [Uri]"about:blank"
$txtSummary = F 'txtSummary'; $cbConfirm = F 'cbConfirm'
$script:txtLog=$txtLog; $script:progressBar=$progressBar; $script:lblProgress=$lblProgress
# --------- Utilitaire : ImageSource à partir d’un tableau d’octets ----------
function New-ImageSourceFromBytes {
  param([byte[]]$Bytes)
  $ms = New-Object System.IO.MemoryStream(,$Bytes)
  $bi = New-Object System.Windows.Media.Imaging.BitmapImage
  $bi.BeginInit()
  $bi.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
  $bi.StreamSource = $ms
  $bi.EndInit()
  $bi.Freeze()
  $ms.Dispose()
  return $bi
}
# --------- Logo optionnel (Base64) ----------
$LogoBase64 = @'
iVBORw0KGgoAAAANSUhEUgAAAXwAAABVCAMAAAB97a+yAAADJWlUWHRYTUw6Y29tLmFkb2JlLnhtcAAAAAAAPD94cGFja2V0IGJlZ2luPSLvu78iIGlkPSJXNU0wTXBDZWhpSHpyZVN6TlRjemtjOWQiPz4gPHg6eG1wbWV0YSB4bWxuczp4PSJhZG9iZTpuczptZXRhLyIgeDp4bXB0az0iQWRvYmUgWE1QIENvcmUgNS42LWMxNDggNzkuMTY0MDM2LCAyMDE5LzA4LzEzLTAxOjA2OjU3ICAgICAgICAiPiA8cmRmOlJERiB4bWxuczpyZGY9Imh0dHA6Ly93d3cudzMub3JnLzE5OTkvMDIvMjItcmRmLXN5bnRheC1ucyMiPiA8cmRmOkRlc2NyaXB0aW9uIHJkZjphYm91dD0iIiB4bWxuczp4bXBNTT0iaHR0cDovL25zLmFkb2JlLmNvbS94YXAvMS4wL21tLyIgeG1sbnM6c3RSZWY9Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC9zVHlwZS9SZXNvdXJjZVJlZiMiIHhtbG5zOnhtcD0iaHR0cDovL25zLmFkb2JlLmNvbS94YXAvMS4wLyIgeG1wTU06RG9jdW1lbnRJRD0ieG1wLmRpZDpDMzJERTc4MjE4NDUxMUVBODZFMkU3MkVDMkUzRDMwOCIgeG1wTU06SW5zdGFuY2VJRD0ieG1wLmlpZDpDMzJERTc4MTE4NDUxMUVBODZFMkU3MkVDMkUzRDMwOCIgeG1wOkNyZWF0b3JUb29sPSJBZG9iZSBQaG90b3Nob3AgMjEuMCAoTWFjaW50b3NoKSI+IDx4bXBNTTpEZXJpdmVkRnJvbSBzdFJlZjppbnN0YW5jZUlEPSJ4bXAuaWlkOkZGRkM3N0ZEMTdBNTExRUFCMzdDODQwQTYyMUI3ODFDIiBzdFJlZjpkb2N1bWVudElEPSJ4bXAuZGlkOkZGRkM3N0ZFMTdBNTExRUFCMzdDODQwQTYyMUI3ODFDIi8+IDwvcmRmOkRlc2NyaXB0aW9uPiA8L3JkZjpSREY+IDwveDp4bXBtZXRhPiA8P3hwYWNrZXQgZW5kPSJyIj8+YXRd1QAAABl0RVh0U29mdHdhcmUAQWRvYmUgSW1hZ2VSZWFkeXHJZTwAAAMAUExURUdwTFdWVldWVldWVldWVldWVldWVldWVldWVldWVldWVldWVmFVUldWVldWVldWVldWVldWVldWVqceJldWVldWVldWVk5VXFdWVgBOgldWVldWVldWVldWVldWVldWVldWVlNVWFdWVldWVldWVldWVldWVldWVldWVldWVldWVldWVldWVldWVldWVldWVldWVldWVldWVldWVldWVldWVldWVldWVldWVldWVldWVldWVldWVldWVldWVldWVuWlIFdWVldWVldWVldWVldWVldWVldWVldWVldWVldWVldWVldWVldWVldWVldWVldWVldWVldWVldWVldWVldWVldWVldWVldWVqceJldWVldWVldWVldWVldWVldWVldWVldWVldWVldWVldWVldWVldWVldWVldWVqceJqceJldWVldWVldWVldWVldWVldWVldWVqceJrI4JQBOgldWVldWVldWVqceJgBOggBOgldWVqceJqceJgBOgqceJqceJqceJldWVldWVldWVldWVldWVldWVldWVldWVqceJgBOgqceJgBOgqceJqceJqceJqceJgBOggBOggBOggBOguWlIABOggBOgldWVldWVldWVgBOggBOgqceJqceJqceJqceJqceJqceJgBOgqceJgBOgqceJqceJuWlIKceJqceJqceJqceJuWlIOWlIOWlIOWlIABOggBOggBOggBOguWlIFdWVuWlIABOgqceJqceJuWlIABOggBOgqceJqceJgBOgqceJgBOguWlIKceJgBOggBOgqceJuWlIABOgqceJqceJqceJqceJgBOggBOggBOgqceJuWlIOWlIOWlIOWlIOWlIABOguWlIABOguWlIOWlIOWlIOWlIOWlIABOgqceJgBOggBOguWlIABOggBOgqceJqceJuWlIOWlIKceJuWlIABOguWlIABOguWlIKceJuWlIKceJqceJuWlIOWlILiMMeWlIKAgKlY1UyVDbVdWVqceJgBOguWlIHLv4A4AAAD8dFJOUwCQQBDAoLBg8DAg4AH+0FAO+vKAcAnJBAzw9wM3PkweBgKAuPzplhXvLRlGG314xvWZJGOfhhIhSSaTWsPPO1dQvUOD2lWcXY1o57Gj7CrUazIHcxM1bq3dBainYdfjC+WMu4lls6rSOQ+F33pTWzErirED/KZO0dH3FEFY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
'@
$imgLogo = F 'imgLogo'
if ($imgLogo) {
  try {
    $bytes = [Convert]::FromBase64String(($LogoBase64 -replace '\s',''))
    $imgLogo.Source = New-ImageSourceFromBytes $bytes
  } catch { }
}
# --------- Lien « ouvrir le log » ----------
$null = $hlLog.Add_RequestNavigate({
  param($s,$e)
  try {
    $path = $Global:LastLogPath
    if ($path -and (Test-Path $path)) {
      if ((Get-Item -LiteralPath $path).PSIsContainer) {
        Start-Process -FilePath explorer.exe -ArgumentList "`"$path`""
      } else {
        Start-Process -FilePath $path
      }
    } else {
      [System.Windows.MessageBox]::Show("Log introuvable.","Info",
        [System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Information) | Out-Null
    }
  } catch {}
  $e.Handled = $true
})
$txtUser.Text = $Account
$txtProfile.Text = $ProfilePath
function Sanitize-ClientName {
  param([Parameter(Mandatory)][string]$Name)
  # Autorise lettres/chiffres/underscore/-,.,(),[], espaces ; remplace le reste par "_"
  $safe = $Name -replace '[^\w\-\.\(\)

\[\]

\s]','_'
  $safe = $safe.Trim()
  # Évite les noms de type "C:\" ou "D:\" (non valides comme dossiers)
  if ($safe -match '^[A-Za-z]:\\?$') { $safe = 'Client_' + (Get-Date -Format 'yyyyMMdd_HHmmss') }
  if ([string]::IsNullOrWhiteSpace($safe)) { $safe = 'Client_' + (Get-Date -Format 'yyyyMMdd_HHmmss') }
  # Longueur maximale
  if ($safe.Length -gt 64) { $safe = $safe.Substring(0,64) }
  return $safe
}
# --------- Dossier par défaut (destination/import) ----------
function Get-DefaultDest {
  if ($PSCommandPath){ return (Split-Path -Parent $PSCommandPath) }
  elseif ($PSScriptRoot){ return $PSScriptRoot }
  elseif ($MyInvocation.MyCommand.Path){ return (Split-Path -Parent $MyInvocation.MyCommand.Path) }
  else { return (Get-Location).Path }
}
$DefaultDest = Get-DefaultDest
(F 'tbExportDest').Text = $DefaultDest
(F 'tbImportSrc').Text  = $DefaultDest
# --------- Manifestes : sauvegarde/chargement ----------
function Save-Manifests($folder,[hashtable]$data){
  $json = ($data | ConvertTo-Json -Depth 8)
  $json | Set-Content (Join-Path $folder 'manifest.json') -Encoding UTF8
  $xml = New-Object System.Xml.XmlDocument
  $root = $xml.CreateElement("MigrationManifest"); $xml.AppendChild($root) | Out-Null
  $meta = $xml.CreateElement("Meta"); $meta.SetAttribute("Machine",$env:COMPUTERNAME); $meta.SetAttribute("User",$Account); $meta.SetAttribute("Time",(Get-Date).ToString('s')); $root.AppendChild($meta) | Out-Null
  $cdata = $xml.CreateCDataSection($json); $blob = $xml.CreateElement("JsonBlob"); $blob.AppendChild($cdata) | Out-Null; $root.AppendChild($blob) | Out-Null
  $xml.Save( (Join-Path $folder 'manifest.xml') )
}
function Load-Manifest($folder){
  $jsonPath = Join-Path $folder 'manifest.json'
  if (Test-Path $jsonPath) { try { return Get-Content $jsonPath -Raw | ConvertFrom-Json } catch {} }
  $xmlPath = Join-Path $folder 'manifest.xml'
  if (Test-Path $xmlPath) { try { [xml]$x = Get-Content $xmlPath -Raw; return ($x.MigrationManifest.JsonBlob.'#cdata-section' | ConvertFrom-Json) } catch {} }
  return $null
}
function Merge-Manifests {
  param(
    [Parameter(Mandatory)] [string]$folder,
    [Parameter(Mandatory)] $new
  )
  $old = Load-Manifest $folder
  if (-not $old) { Save-Manifests -folder $folder -data $new; return }
  if (-not $old.History) { $old | Add-Member -NotePropertyName History -NotePropertyValue @() }
  $old.History += [pscustomobject]@{ When=$old.When; Mode=$old.Mode; Options=$old.Options }
  $old.Mode   = $new.Mode
  $old.When   = $new.When
  $old.User   = $new.User
  $old.Source = $new.Source
  $pathsOld = @(); if ($old.Paths) { $pathsOld = @($old.Paths) }
  $pathsNew = @(); if ($new.Paths) { $pathsNew = @($new.Paths) }
  $old.Paths = @($pathsOld + $pathsNew | Where-Object { $_ -and ($_ -ne '') } | Sort-Object -Unique)
  if (-not $old.Options) { $old.Options = @{} }
  $old.Options.LastRun = $new.Options
foreach ($k in @('Wifi','Printers','PrinterDrivers','Taskbar','StartMenu','Wallpaper','DesktopPos','NetDrives',
                 'AppDataChrome','AppDataEdge','AppDataFirefox','AppDataOutlook')) {
  $old.Options."Ever_$k" = [bool]($old.Options."Ever_$k") -or [bool]$new.Options.$k
}
$old.Sections = @{
  Wifi         = Test-Path (Join-Path $folder 'WiFi')
  Printers     = Test-Path (Join-Path $folder 'Printers')
  PrinterDrv   = Test-Path (Join-Path (Join-Path $folder 'Printers') 'Drivers')
  TaskbarUI    = Test-Path (Join-Path $folder 'UI') # indicatif
  StartLayout  = Test-Path (Join-Path (Join-Path $folder 'UI') 'StartLayout.xml')
  Wallpaper    = Test-Path (Join-Path $folder 'Wallpaper')
  DesktopPos   = (
                   (Test-Path (Join-Path (Join-Path $folder 'Registry') 'desktopbag.reg')) -or
                   (Test-Path (Join-Path (Join-Path $folder 'Registry') 'streamsdesk.reg')) -or
                   (Test-Path (Join-Path (Join-Path $folder 'Registry') 'UserDesktop_HKCU.reg'))
                 )
  NetDrives    = Test-Path (Join-Path (Join-Path $folder 'NetworkDrives') 'drives.csv')
  AppDataChrome  = Test-Path (Join-Path (Join-Path $folder 'AppDataBrowsers') 'Chrome')
  AppDataEdge    = Test-Path (Join-Path (Join-Path $folder 'AppDataBrowsers') 'Edge')
  AppDataFirefox = Test-Path (Join-Path (Join-Path $folder 'AppDataBrowsers') 'Firefox')
  AppDataOutlook = Test-Path (Join-Path $folder 'AppDataOutlook')
}
  Save-Manifests -folder $folder -data $old
}
# --------- Sélecteurs de dossier (fallback WinForms) ----------
function Select-FolderClassic {
  param([string]$Title = "Sélectionner un dossier",[string]$InitialPath = "")
  try {
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($dlg.PSObject.Properties.Name -contains 'AutoUpgradeEnabled') { $dlg.AutoUpgradeEnabled = $true }
    if ($dlg.PSObject.Properties.Name -contains 'UseDescriptionForTitle') { $dlg.UseDescriptionForTitle = $true }
    $dlg.Description = if ([string]::IsNullOrWhiteSpace($Title)) { "Sélectionner un dossier" } else { $Title }
    $dlg.ShowNewFolderButton = $true
    $dlg.RootFolder = [System.Environment+SpecialFolder]::MyComputer
    if ($InitialPath -and (Test-Path $InitialPath)) { $dlg.SelectedPath = (Resolve-Path $InitialPath).Path }
    $res = $dlg.ShowDialog()
    if ($res -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.SelectedPath }
  } catch {}
  return $null
}
function Select-Folder {
  param([string]$Title = "Sélectionner un dossier",[string]$InitialPath = "")
  return Select-FolderClassic -Title $Title -InitialPath $InitialPath
}
# --------- Détection du contenu d’un dossier d’import ----------
function Detect-ImportContents {
  param([Parameter(Mandatory)] [string]$Folder)
  $info = [ordered]@{
    Paths           = @()
    WifiXml         = 0
    PrintBrm        = $false
    DriversInf      = 0
    HasUIStart      = $false
    HasTaskband     = $false
    HasTaskbarPins  = $false
    RegDesktop      = $false
    WallpaperFiles  = 0
    NetDrivesCsv    = $false
AppDataChrome  = $false
AppDataEdge    = $false
AppDataFirefox = $false
AppDataOutlook = $false
  }
  $manifest = Load-Manifest $Folder
  if ($manifest) {
    $paths = @()
    try {
      foreach($p in $manifest.Paths){
        if ($p) {
          $s = [string]$p
          if ($s) { if ($s.Trim() -ne '') { $paths += $s } }
        }
      }
    } catch {}
    if ($paths.Count -gt 0) { $info.Paths = @($paths | Sort-Object -Unique) }
  }
  $wifi = Join-Path $Folder 'WiFi'
  if (Test-Path $wifi) {
    try { $info.WifiXml = @(Get-ChildItem $wifi -Filter *.xml -ErrorAction SilentlyContinue).Count } catch {}
  }
  $prn = Join-Path $Folder 'Printers'
if (Test-Path (Join-Path $prn 'Printers_Backup.printerExport')) { $info.PrintBrm = $true }
$info.PrintSnapshot = (Test-Path (Join-Path $prn 'Printers_List.json')) -or (Test-Path (Join-Path $prn 'Ports.json'))
$drv = Join-Path $prn 'Drivers'
  if (Test-Path $drv) {
    try { $info.DriversInf = @(Get-ChildItem $drv -Recurse -Filter *.inf -ErrorAction SilentlyContinue).Count } catch {}
  }
  $ui = Join-Path $Folder 'UI'
  if (Test-Path (Join-Path $ui 'StartLayout.xml')) { $info.HasUIStart = $true }
  if (Test-Path (Join-Path $ui 'Taskband.reg'))    { $info.HasTaskband = $true }
  if (Test-Path (Join-Path $ui 'Taskbar_Pinned'))  { $info.HasTaskbarPins = $true }
  $reg = Join-Path $Folder 'Registry'
if (
    (Test-Path (Join-Path $reg 'UserDesktop_HKCU.reg')) -or
    (Test-Path (Join-Path $reg 'desktopbag.reg'))       -or
    (Test-Path (Join-Path $reg 'streamsdesk.reg'))
) {
  $info.RegDesktop = $true
}
  $wdir = Join-Path $Folder 'Wallpaper'
  if (Test-Path $wdir) {
    try { $info.WallpaperFiles = @(Get-ChildItem $wdir -File -ErrorAction SilentlyContinue).Count } catch {}
  }
  $nd = Join-Path $Folder 'NetworkDrives\drives.csv'
  if (Test-Path $nd) { $info.NetDrivesCsv = $true }
$adb = Join-Path $Folder 'AppDataBrowsers'
if (Test-Path (Join-Path $adb 'Chrome'))  { $info.AppDataChrome  = $true }
if (Test-Path (Join-Path $adb 'Edge'))    { $info.AppDataEdge    = $true }
if (Test-Path (Join-Path $adb 'Firefox')) { $info.AppDataFirefox = $true }
$ao = Join-Path $Folder 'AppDataOutlook'
if (Test-Path (Join-Path $ao 'Local\Microsoft\Outlook'))        { $info.AppDataOutlook = $true }
if (Test-Path (Join-Path $ao 'Roaming\Microsoft\Outlook'))      { $info.AppDataOutlook = $true }
if (Test-Path (Join-Path $ao 'Roaming\Microsoft\Signatures'))   { $info.AppDataOutlook = $true }
  return [pscustomobject]$info
} # end function Detect-ImportContents
# --------- Fond d’écran (export/import sûrs) ----------
function Export-WallpaperSimple {
  param([Parameter(Mandatory)][string]$OutRoot)
  try {
    $wp = (Get-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name WallPaper -ErrorAction SilentlyContinue).WallPaper
    if (-not $wp -or -not (Test-Path $wp)) {
      Log "Fond d’écran : chemin introuvable — export ignoré."
      return
    }
    $wdir = Join-Path $OutRoot 'Wallpaper'
    New-Item -ItemType Directory -Force -Path $wdir | Out-Null
    $dst = Join-Path $wdir (Split-Path $wp -Leaf)
    Copy-Item -LiteralPath $wp -Destination $dst -Force
    "$([IO.Path]::GetFileName($dst))" | Set-Content -Path (Join-Path $wdir 'wallpaper.txt') -Encoding UTF8
    Log "Fond d’écran copié -> $dst"
  } catch {
    Log "Export fond d’écran : $($_.Exception.Message)"
  }
}
function Set-WallpaperSafe {
  param([Parameter(Mandatory)][string]$ImagePath)
  try {
    if (-not (Test-Path -LiteralPath $ImagePath)) { throw "Image introuvable: $ImagePath" }
    # 1) Copie sous C:\Logicia\Wallpaper
    $root = 'C:\Logicia\Wallpaper'
    try { New-Item -ItemType Directory -Force -Path $root | Out-Null } catch {}
    $dst = Join-Path $root (Split-Path $ImagePath -Leaf)
    Copy-Item -LiteralPath $ImagePath -Destination $dst -Force
    $ImagePath = $dst
    Log "Fond d’écran : image copiée → $ImagePath"
    # 2) Tentative API DesktopWallpaper (Win8+)
    $ok = $false
    try {
      $dw = New-Object -ComObject DesktopWallpaper
      if ($dw) {
        $dw.SetWallpaper('', $ImagePath) | Out-Null
        $ok = $true
        Log "Fond d’écran appliqué via DesktopWallpaper."
      }
    } catch {
      Log "DesktopWallpaper KO : $($_.Exception.Message)"
    }
    # 3) Fallback : SPI + refresh Explorer
    if (-not $ok) {
      try {
$sig = @'
using System;
using System.Runtime.InteropServices;
public class WP {
  [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern bool SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
'@
        if (-not ([type]::GetType('WP'))) { Add-Type $sig -ErrorAction SilentlyContinue }
        [void][WP]::SystemParametersInfo(20, 0, $ImagePath, 1 -bor 2)   # SPI_SETDESKWALLPAPER
        Log "Fond d’écran appliqué via SystemParametersInfo."
        $ok = $true
      } catch {
        Log "SPI KO : $($_.Exception.Message)"
      }
    }
    # 4) Fallback verbe shell (optionnel, certains systèmes ne l’exposent pas)
    if (-not $ok) {
      try {
        $shell = New-Object -ComObject Shell.Application
        $shell.ShellExecute($ImagePath, $null, $null, 'setdesktopwallpaper', 1) | Out-Null
        Log "Fond d’écran appliqué via verbe shell."
        $ok = $true
      } catch { }
    }
    if (-not $ok) { throw "Impossible d’appliquer le fond d’écran (toutes méthodes ont échoué)." }
  } catch {
    Log "Set-WallpaperSafe : $($_.Exception.Message)"
  }
}
# --------- Impression : PrintBRM + repli (édition Home) ----------
function Ensure-Spooler {
  $s = Get-Service Spooler -ErrorAction SilentlyContinue
  if (-not $s) { Log "Impression : service Spooler introuvable."; return $false }
  if ($s.Status -ne 'Running') {
    try { Start-Service Spooler -ErrorAction Stop; Log "Impression : Spooler démarré" }
    catch { Log "Impression : impossible de démarrer Spooler : $($_.Exception.Message)" }
  }
  return $true
}
function Export-PrinterDriversTargeted {
  param([Parameter(Mandatory)] [string]$OutDir)
  try { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null } catch {}
  if (-not (Get-Command Get-PrinterDriver -ErrorAction SilentlyContinue)) {
    Log "Get-PrinterDriver indisponible — export ciblé des pilotes impossible."
    return
  }
  try {
    $drivers = @(Get-PrinterDriver | Sort-Object Name -Unique)
    if ($drivers.Count -eq 0) { Log "Aucun pilote d'imprimante détecté."; return }
    $done = @{}
    foreach($d in $drivers) {
      $inf = $d.InfPath
      if (-not $inf -or -not (Test-Path $inf)) { Log ("Pilote {0}: InfPath introuvable" -f $d.Name); continue }
      $srcDir = Split-Path -Path $inf -Parent
      if ($done.ContainsKey($srcDir)) { continue }
      $safe  = ($d.Name -replace '[^\w\.-]+','_'); if ([string]::IsNullOrWhiteSpace($safe)) { $safe = "Driver_$([Guid]::NewGuid().ToString('N'))" }
      $dstDir = Join-Path $OutDir $safe
      try {
        Copy-Item -LiteralPath $srcDir -Destination $dstDir -Recurse -Force -ErrorAction Stop
        $done[$srcDir] = $true
        Log ("Pilote exporté: {0} -> {1}" -f $d.Name, $dstDir)
      } catch { Log ("Export pilote KO ({0}) : {1}" -f $d.Name, $_.Exception.Message) }
    }
  } catch { Log ("Export-PrinterDriversTargeted : {0}" -f $_.Exception.Message) }
}
function Export-PrinterSnapshot([string]$outDir){
  try {
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    if (Get-Command Get-Printer -ErrorAction SilentlyContinue) {
      $plist = Get-Printer | Select-Object Name,DriverName,PortName,Shared,ShareName,Published,Type,Location,Comment, @{n='IsDefault';e={$_.Default}}
      $plist | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $outDir 'Printers_List.json') -Encoding UTF8
      $def = ($plist | Where-Object { $_.IsDefault -eq $true } | Select-Object -First 1).Name
      if ($def) { $def | Set-Content (Join-Path $outDir 'DefaultPrinter.txt') -Encoding UTF8 }
      Log "Liste imprimantes exportée -> Printers_List.json"
      if ($def) { Log "Imprimante par défaut : $def" }
    }
    if (Get-Command Get-PrinterPort -ErrorAction SilentlyContinue) {
      $ports = Get-PrinterPort | Select-Object Name, Description, PortMonitor, PrinterHostAddress, PortNumber, SNMP, SNMPCommunity, SNMPDevIndex
      $ports | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $outDir 'Ports.json') -Encoding UTF8
      Log "Ports TCP/IP exportés -> Ports.json"
    } else {
      Log "Get-PrinterPort indisponible — ports non exportés."
    }
  } catch { Log "Export snapshot imprimantes/ports : $($_.Exception.Message)" }
}
function Export-PrintersViaPrintBrm([string]$outDir){
  New-Item -ItemType Directory -Path $outDir -Force | Out-Null
  if (-not (Ensure-Spooler)) { return $false }
  $printbrm = "$env:SystemRoot\System32\spool\tools\printbrm.exe"
  $hasPrintBrm = Test-Path $printbrm
  if (-not $hasPrintBrm) { Log "PrintBRM introuvable (édition Windows ? Home/N)" }
  $ok = $false
  if ($hasPrintBrm) {
    $bak = Join-Path $outDir "Printers_Backup.printerExport"
    try {
      $code = Run-External -FilePath $printbrm -Arguments "-B -F `"$bak`" -S localhost -O force"
      if ($code -eq 0 -and (Test-Path $bak)) {
        try { $size = (Get-Item $bak).Length; Log ("PrintBRM : fichier généré ({0} octets) -> {1}" -f $size, $bak) }
        catch { Log "PrintBRM : fichier généré -> $bak" }
        $ok = $true
      } else {
        Log "PrintBRM code=$code (fichier présent: $([bool](Test-Path $bak)))"
      }
    } catch { Log "PrintBRM export : $($_.Exception.Message)" }
  }
  try { Export-PrinterSnapshot -outDir $outDir } catch {}
  return $ok
}
function Import-PrintersViaPrintBrm([string]$inDir){
  if (-not (Ensure-Spooler)) { return $false }
  $printbrm = "$env:SystemRoot\System32\spool\tools\printbrm.exe"
  $bak = Get-ChildItem $inDir -Filter *.printerExport -ErrorAction SilentlyContinue | Select-Object -First 1
  if ((Test-Path $printbrm) -and $bak) {
    try {
      try { $size = (Get-Item $bak.FullName).Length; Log ("PrintBRM import : fichier détecté ({0} octets) -> {1}" -f $size, $($bak.FullName)) } catch {}
      $code = Run-External -FilePath $printbrm -Arguments "-R -F `"$($bak.FullName)`" -O force"
      if ($code -eq 0) { Log "Imprimantes restaurées via PrintBRM"; return $true }
      Log "PrintBRM import code=$code"
    } catch { Log "PrintBRM import : $($_.Exception.Message)" }
  } else {
    Log "Aucune sauvegarde PrintBRM utilisable (Home ou fichier absent)."
  }
  return $false
}
function Import-PrintersFromSnapshot([string]$inDir){
  try {
    $driversDir = Join-Path $inDir 'Drivers'
    if (Test-Path $driversDir) {
      Get-ChildItem $driversDir -Recurse -Filter *.inf -ErrorAction SilentlyContinue | ForEach-Object {
        try { pnputil /add-driver "`"$($_.FullName)`"" /install /subdirs 2>&1 | Out-Null; Log "Pilote installé: $($_.Name)" }
        catch { Log "Pilote : $($_.Exception.Message)" }
      }
    }
    $portsJson = Join-Path $inDir 'Ports.json'
    $knownPorts = @{}
    if (Test-Path $portsJson) {
      $ports = Get-Content $portsJson -Raw | ConvertFrom-Json
      foreach($p in $ports){
        $knownPorts[$p.Name] = $true
        if (-not (Get-PrinterPort -Name $p.Name -ErrorAction SilentlyContinue)) {
          if ($p.PortMonitor -eq 'Standard TCP/IP Port' -and $p.PrinterHostAddress) {
            try {
              $params = @{ Name = $p.Name; PrinterHostAddress = $p.PrinterHostAddress }
              if ($p.PortNumber) { $params['PortNumber'] = [int]$p.PortNumber }
              Add-PrinterPort @params
              if ($p.SNMP -and ($p.SNMP -ne $false)) {
                try {
                  Set-PrinterPort -Name $p.Name -SNMP $true -SNMPCommunity $p.SNMPCommunity -SNMPDevIndex ([int]$p.SNMPDevIndex) -ErrorAction SilentlyContinue
                } catch {}
              }
              Log "Port créé: $($p.Name) -> $($p.PrinterHostAddress):$($p.PortNumber)"
            } catch { Log "Création port KO ($($p.Name)) : $($_.Exception.Message)" }
          } else {
            Log "Port $($p.Name) non créé (monitor=$($p.PortMonitor), host=$($p.PrinterHostAddress))"
          }
        }
      }
    } else {
      Log "Ports.json absent — création de ports limitée."
    }
    $plistJson = Join-Path $inDir 'Printers_List.json'
    if (Test-Path $plistJson) {
      $plist = Get-Content $plistJson -Raw | ConvertFrom-Json
      foreach($pr in $plist){
        if ($pr.DriverName -match 'Microsoft|OneNote|XPS|PDF') { continue }
        $port = $pr.PortName
        $drv  = $pr.DriverName
        $name = $pr.Name
        if (-not (Get-PrinterPort -Name $port -ErrorAction SilentlyContinue)) {
          Log "Imprimante '$name' ignorée: port '$port' introuvable (WSD/USB ou partagé). Connecte l'imprimante une fois et relance si besoin."
          continue
        }
        if (-not (Get-Printer -Name $name -ErrorAction SilentlyContinue)) {
          try {
            Add-Printer -Name $name -DriverName $drv -PortName $port -ErrorAction Stop | Out-Null
            if ($pr.Location) { try { Set-Printer -Name $name -Location $pr.Location -ErrorAction SilentlyContinue } catch {} }
            if ($pr.Comment)  { try { Set-Printer -Name $name -Comment  $pr.Comment  -ErrorAction SilentlyContinue } catch {} }
            Log "Imprimante recréée: $name (driver='$drv', port='$port')"
          } catch { Log "Création imprimante KO ($name) : $($_.Exception.Message)" }
        }
      }
      $defPath = Join-Path $inDir 'DefaultPrinter.txt'
      if (Test-Path $defPath) {
        $def = (Get-Content $defPath -Raw).Trim()
        if ($def -and (Get-Printer -Name $def -ErrorAction SilentlyContinue)) {
          try { Set-Printer -Name $def -IsDefault $true -ErrorAction Stop; Log "Imprimante par défaut définie : $def" }
          catch { Log "Définir défaut KO ($def) : $($_.Exception.Message)" }
        }
      }
    } else {
      Log "Printers_List.json absent — rien à recréer."
    }
  } catch { Log "Import imprimantes (snapshot) : $($_.Exception.Message)" }
}

# --------- Lecteurs réseau mappés ----------
function Export-NetworkDrives {
  param([Parameter(Mandatory)][string]$OutRoot)
  try {
    $out = Join-Path $OutRoot 'NetworkDrives'
    New-Item -ItemType Directory -Force -Path $out | Out-Null
    $drives = Get-PSDrive | Where-Object { $_.Provider -and $_.Provider.Name -eq 'FileSystem' -and $_.DisplayRoot }
    $rows = @()
    foreach($d in $drives){
      $rows += [pscustomobject]@{
        Name   = $d.Name
        Root   = $d.DisplayRoot
        Used   = [math]::Round($d.Used/1MB,2)
        Free   = [math]::Round($d.Free/1MB,2)
        Scope  = $d.Scope
      }
    }
    if ($rows.Count -gt 0) {
      $csv = Join-Path $out 'drives.csv'
      $rows | Export-Csv -NoTypeInformation -Encoding UTF8 -UseCulture -Path $csv
      Log "Lecteurs réseau exportés -> $csv"
    } else {
      Log "Aucun lecteur réseau mappé."
    }
  } catch { Log "Export NetworkDrives : $($_.Exception.Message)" }
}
function Import-NetworkDrives {
  param([Parameter(Mandatory)][string]$InRoot)
  try {
    $csv = Join-Path (Join-Path $InRoot 'NetworkDrives') 'drives.csv'
    if (-not (Test-Path $csv)) { Log "NetworkDrives absent — rien à restaurer."; return }
    $rows = Import-Csv -Path $csv
    foreach($r in $rows){
      $name = $r.Name; $root = $r.Root
      if (-not $name -or -not $root) { continue }
      try {
        if (Get-PSDrive -Name $name -ErrorAction SilentlyContinue) {
          Log "Lecteur $name existe déjà — saut."
        } else {
          New-PSDrive -Name $name -PSProvider FileSystem -Root $root -Persist -ErrorAction Stop | Out-Null
          Log "Lecteur réseau mappé : $name -> $root"
        }
      } catch { Log "Map lecteur $name -> $root : $($_.Exception.Message)" }
    }
  } catch { Log "Import NetworkDrives : $($_.Exception.Message)" }
}

# --------- Wi-Fi ----------
function Export-WifiProfiles {
  param([Parameter(Mandatory)][string]$OutRoot)
  try {
    $dir = Join-Path $OutRoot 'WiFi'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $profiles = netsh wlan show profiles
    $names = @()
    foreach($line in $profiles){
      if ($line -match 'Profil Tous les utilisateurs|All User Profile') {
        $n = $line -replace '.*:\s*',''
        if ($n) { $names += $n.Trim() }
      }
    }
    foreach($n in $names){
      try {
        $xml = Join-Path $dir ("WiFi_" + ($n -replace '[^\w\.-]+','_') + ".xml")
        netsh wlan export profile name="$n" folder="$dir" key=clear | Out-Null
        if (Test-Path $xml) { Log "Wi-Fi exporté: $n" } else { Log "Wi-Fi exporté: $n (fichier par défaut créé par netsh)" }
      } catch { Log "Wi-Fi ($n) : $($_.Exception.Message)" }
    }
    Log "Wi-Fi : export terminé."
  } catch { Log "Export Wi-Fi : $($_.Exception.Message)" }
}
function Import-WifiProfiles {
  param([Parameter(Mandatory)][string]$InRoot)
  try {
    $dir = Join-Path $InRoot 'WiFi'
    if (-not (Test-Path $dir)) { Log "Wi-Fi absent — rien à restaurer."; return }
    $xmls = Get-ChildItem $dir -Filter *.xml -ErrorAction SilentlyContinue
    foreach($f in $xmls){
      try {
        netsh wlan add profile filename="$($f.FullName)" user=current | Out-Null
        Log "Wi-Fi importé : $($f.Name)"
      } catch { Log "Wi-Fi import : $($_.Exception.Message)" }
    }
    Log "Wi-Fi : import terminé."
  } catch { Log "Import Wi-Fi : $($_.Exception.Message)" }
}

# --------- Barre des tâches et Menu Démarrer (export/import non destructifs) ----------
function Export-TaskbarAndStart {
  param([Parameter(Mandatory)][string]$OutRoot)
  try {
    $ui = Join-Path $OutRoot 'UI'
    New-Item -ItemType Directory -Force -Path $ui | Out-Null
    # Export Taskband (épinglements barre des tâches)
    try {
      $reg = Join-Path $ui 'Taskband.reg'
$taskbandKeyPs = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband"
$taskbandKeyRaw= "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband"
try {
  if (Test-Path $taskbandKeyPs) {
    $props = Get-ItemProperty -Path $taskbandKeyPs -ErrorAction SilentlyContinue
    if ($props -and ($props.PSObject.Properties.Count -gt 0)) {
      & reg.exe export $taskbandKeyRaw "$reg" /y 2>$null | Out-Null
      Log "Taskband exporté → $reg"
    } else {
      Log "Taskband présent mais vide — export ignoré."
    }
  } else {
    Log "Taskband absent — export ignoré."
  }
} catch {
  Log "Taskband export : $($_.Exception.Message)"
}
    } catch { Log "Taskband export : $($_.Exception.Message)" }
    # Export StartLayout (Windows 11) – best-effort
    try {
      $layout = Join-Path $ui 'StartLayout.xml'
      $cmd = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
      $args = "-NoProfile -ExecutionPolicy Bypass -Command `"Export-StartLayout -UseDesktopApplicationID -Path `"$layout`"`""
      $rc = Run-External -FilePath $cmd -Arguments $args
      if ((Test-Path $layout) -and ($rc -eq 0)) { Log "StartLayout exporté -> $layout" }
      else { Log "StartLayout export: rc=$rc (peut être indisponible selon édition)" }
    } catch { Log "StartLayout export : $($_.Exception.Message)" }
    # Épingles directes (exploration dossier)
    try {
      $pinsDir = Join-Path $ui 'Taskbar_Pinned'
      New-Item -ItemType Directory -Force -Path $pinsDir | Out-Null
      $taskbarPins = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
      if (Test-Path $taskbarPins) {
        Copy-Tree -src $taskbarPins -dst $pinsDir
        Log "Taskbar pinned exporté."
      }
    } catch { Log "Taskbar pinned export : $($_.Exception.Message)" }
  } catch { Log "Export Taskbar/Start : $($_.Exception.Message)" }
}
function Import-TaskbarAndStart {
  param([Parameter(Mandatory)][string]$InRoot)
  try {
    $ui = Join-Path $InRoot 'UI'
    if (-not (Test-Path $ui)) { Log "UI absent — rien à restaurer."; return }
    # Import Taskband
    try {
      $reg = Join-Path $ui 'Taskband.reg'
      if (Test-Path $reg) {
        & reg.exe import "$reg" 2>$null | Out-Null
        Log "Taskband importé."
      }
    } catch { Log "Taskband import : $($_.Exception.Message)" }
    # Import StartLayout (best-effort)
    try {
      $layout = Join-Path $ui 'StartLayout.xml'
      if (Test-Path $layout) {
        $cmd = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
        $args = "-NoProfile -ExecutionPolicy Bypass -Command `"Import-StartLayout -LayoutPath `"$layout`" -MountPath `"$env:SystemDrive\`"`""
        $rc = Run-External -FilePath $cmd -Arguments $args
        Log "StartLayout import: rc=$rc (selon édition)"
      }
    } catch { Log "StartLayout import : $($_.Exception.Message)" }
    # Épingles directes
    try {
      $pinsDir = Join-Path $ui 'Taskbar_Pinned'
      $taskbarPins = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
      if (Test-Path $pinsDir) {
        New-Item -ItemType Directory -Force -Path $taskbarPins | Out-Null
        Copy-Tree -src $pinsDir -dst $taskbarPins
        Log "Taskbar pinned importé."
      }
    } catch { Log "Taskbar pinned import : $($_.Exception.Message)" }
  } catch { Log "Import Taskbar/Start : $($_.Exception.Message)" }
}

# --------- BuildRoots / Build-ImportTree / PopulateTreeFromPaths ----------
function ComputeLabelForDest {
  param([Parameter(Mandatory)][string]$Dest,[Parameter(Mandatory)][string]$ProfileRoot)
  if ($Dest -like ($ProfileRoot + '*')) {
    $rel = $Dest.Substring($ProfileRoot.Length).TrimStart('\')
    if ($rel -and ($rel.Trim() -ne '')) { return $rel }
    return (Split-Path $Dest -Leaf)
  } elseif ($Dest -eq 'C:\Users\Public\Desktop') {
    return 'Public\Desktop'
  } else { return (Split-Path $Dest -Leaf) }
}
function AddOrUpdateMap {
  param([Parameter(Mandatory)][hashtable]$Map,[Parameter(Mandatory)][string]$Dest,[Parameter(Mandatory)][string]$Src)
  if (-not $Map.ContainsKey($Dest)) { $Map[$Dest] = $Src }
}
function AddOrUpdateTreeNodeUnique {
  param([Parameter(Mandatory)][System.Windows.Controls.TreeView]$Tree,[Parameter(Mandatory)][string]$DestForNode,[Parameter(Mandatory)][string]$Label,[string]$Src)
  foreach ($it in $Tree.Items) {
    if ($it -is [System.Windows.Controls.TreeViewItem]) {
      if ($it.Header -and $it.Header.Tag -and ($it.Header.Tag.PSObject.Properties.Name -contains 'Path')) {
        if ([string]::Equals($it.Header.Tag.Path, $DestForNode, [StringComparison]::OrdinalIgnoreCase)) { return $false }
      }
    }
  }
  $node = if ($Src -and (Test-Path $Src)) { New-Node -path $DestForNode -label $Label -srcPath $Src } else { New-Node -path $DestForNode -label $Label }
  $Tree.Items.Add($node) | Out-Null
  try { $node.Header.IsChecked = $true } catch {}
  return $true
}
function BuildRoots {
  $SelectNodes.Clear()
  $treeFolders.Items.Clear()
  $roots = @('Desktop','Documents','Downloads','Pictures','Music','Videos','Favorites','Links','Contacts') |
    ForEach-Object { @{ Label = $_; Path = (Join-Path $ProfilePath $_) } }
  $roots += @(
    @{ Label = 'AppData\Local';   Path = Join-Path $ProfilePath 'AppData\Local' },
    @{ Label = 'AppData\Roaming'; Path = Join-Path $ProfilePath 'AppData\Roaming' }
  )
  foreach ($r in $roots) { if (Test-Path $r.Path) { $treeFolders.Items.Add( (New-Node -path $r.Path -label $r.Label) ) | Out-Null } }
  # Bureau public uniquement ici
  $pubDesk = 'C:\Users\Public\Desktop'
  if (Test-Path $pubDesk) { $treeFolders.Items.Add( (New-Node -path $pubDesk -label 'Public\Desktop') ) | Out-Null }
  Update-NextAndExclusivity
}
function Build-ImportTree {
  param([Parameter(Mandatory)] [string]$srcRoot,[pscustomobject]$Info)
  $script:ImportRoot = $srcRoot
  $SelectNodes.Clear()
  $treeFolders.Items.Clear()
  $profileSrc    = Join-Path $srcRoot 'Profile'
  $publicDeskSrc = Join-Path $srcRoot 'Public\Desktop'
  $map = @{}
  $known = @('Desktop','Documents','Downloads','Pictures','Music','Videos','Favorites','Links','Contacts','AppData\Local','AppData\Roaming')
  foreach($k in $known){
    $src = Join-Path $profileSrc $k
    if (Test-Path $src) {
      $dest = Join-Path $ProfilePath $k
      AddOrUpdateMap -Map $map -Dest $dest -Src $src
    }
  }
  if (Test-Path $publicDeskSrc) {
    $destPub = 'C:\Users\Public\Desktop'
    $node = New-Node -path $destPub -label 'Public\Desktop' -srcPath $publicDeskSrc
    $treeFolders.Items.Add($node) | Out-Null
    try { $node.Header.IsChecked = $true } catch {}
  }
  if ($Info -and $Info.Paths -and ($Info.Paths.Count -gt 0)) {
    foreach ($p in $Info.Paths) {
      if (-not $p) { continue }
      $pp = [string]$p
      if ([string]::IsNullOrWhiteSpace($pp)) { continue }
      if ($pp -eq 'C:\Users\Public\Desktop') { continue }
      $srcCandidate = $null
      $rel = ($pp -replace [regex]::Escape($ProfilePath),'').TrimStart('\')
      if ($rel -and ($rel.Trim() -ne '')) { $srcCandidate = Join-Path $profileSrc $rel } else { $srcCandidate = Join-Path $profileSrc (Split-Path $pp -Leaf) }
      if (Test-Path $srcCandidate) { AddOrUpdateMap -Map $map -Dest $pp -Src $srcCandidate }
    }
  } else {
    if (Test-Path $profileSrc) {
      Get-ChildItem $profileSrc -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $dest = Join-Path $ProfilePath $_.Name
        AddOrUpdateMap -Map $map -Dest $dest -Src $_.FullName
      }
    }
  }
  foreach ($kv in $map.GetEnumerator() | Sort-Object Key) {
    $dest = $kv.Key; $src = $kv.Value
    $label = ComputeLabelForDest -Dest $dest -ProfileRoot $ProfilePath
    $node = New-Node -path $dest -label $label -srcPath $src
    $treeFolders.Items.Add($node) | Out-Null
  }
  try { Check-AllTreeItems -state $true } catch {}
  Update-NextAndExclusivity
}
function PopulateTreeFromPaths {
  param([Parameter(Mandatory)][string[]]$Paths)
  $SelectNodes.Clear(); $treeFolders.Items.Clear()
  $isImport    = -not [string]::IsNullOrWhiteSpace($script:ImportRoot)
  $profileSrc  = $null
  if ($isImport) { $profileSrc = Join-Path $script:ImportRoot 'Profile' }
  foreach($p in $Paths){
    if (-not $p) { continue }
    $pp = [string]$p
    if ([string]::IsNullOrWhiteSpace($pp)) { continue }
    if ($pp -eq 'C:\Users\Public\Desktop') { continue }
    $label = ComputeLabelForDest -Dest $pp -ProfileRoot $ProfilePath
    $srcCandidate = $null
    if ($isImport -and $profileSrc) {
      $rel2 = ($pp -replace [regex]::Escape($ProfilePath),'').TrimStart('\')
      if ($rel2 -and ($rel2.Trim() -ne '')) { $srcCandidate = Join-Path $profileSrc $rel2 } else { $srcCandidate = Join-Path $profileSrc (Split-Path $pp -Leaf) }
    }
    AddOrUpdateTreeNodeUnique -Tree $treeFolders -DestForNode $pp -Label $label -Src $srcCandidate | Out-Null
  }
  Update-NextAndExclusivity
}

# --------- Navigateurs (tuiles d’accès) ----------
function Find-AppExe {
  param([Parameter(Mandatory)][string]$AppId)
  $candidates = @()
  foreach ($root in @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths",
                      "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths")) {
    try {
      $it = Get-Item "$root\$AppId.exe" -ErrorAction SilentlyContinue
      if ($it) {
        $val = $it.GetValue('')
        if ($val) { $candidates += ($val -replace '^"|"$','') }
      }
    } catch {}
  }
  $candidates += @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe",
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles(x86)\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Mozilla Firefox\firefox.exe",
    "$env:ProgramFiles(x86)\Mozilla Firefox\firefox.exe"
  )
  foreach($p in $candidates){
    if ($p -and (Test-Path $p)) { return (Resolve-Path $p).Path }
  }
  return $null
}
function Get-IconImageSource {
  param([Parameter(Mandatory)][string]$ExePath)
  try {
    $ico = [System.Drawing.Icon]::ExtractAssociatedIcon($ExePath)
    if (-not $ico) { return $null }
    $ms = New-Object System.IO.MemoryStream
    ($ico.ToBitmap()).Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $bytes = $ms.ToArray()
    $ms.Dispose()
    return (New-ImageSourceFromBytes $bytes)
  } catch { return $null }
}
function New-NavTile {
  param([Parameter(Mandatory)][string]$Title,[Parameter(Mandatory)][string]$ExeName,[Parameter(Mandatory)][string]$ExePath)
  $btn = New-Object System.Windows.Controls.Button
  $btn.Tag = [pscustomobject]@{ Title=$Title; Exe=$ExePath }
  $btn.Padding = '10'; $btn.Margin = '6'; $btn.ToolTip = "Ouvrir $Title"; $btn.BorderThickness = '1'
  $btn.Content = (New-Object System.Windows.Controls.StackPanel); $btn.Content.Orientation = 'Vertical'
  $img = New-Object System.Windows.Controls.Image; $img.Width = 64; $img.Height = 64; $img.Source = Get-IconImageSource -ExePath $ExePath
  $lbl = New-Object System.Windows.Controls.TextBlock; $lbl.Text = $Title; $lbl.HorizontalAlignment = 'Center'; $lbl.Margin = '6,8,6,0'
  $btn.Content.Children.Add($img) | Out-Null
  $btn.Content.Children.Add($lbl) | Out-Null
  $null = $btn.Add_Click({ param($s,$e) try { Start-Process -FilePath $s.Tag.Exe -ErrorAction Stop } catch { [System.Windows.MessageBox]::Show("Impossible d’ouvrir $($s.Tag.Title) : $($_.Exception.Message)","Navigateur",[System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Error) | Out-Null } })
  return $btn
}
function Build-PasswordTiles {
  param([Parameter(Mandatory)][System.Windows.Controls.Panel]$GridPwTiles)
  $GridPwTiles.Children.Clear()
  $list = @(
    @{ Name='Google Chrome'; ExeName='chrome';  Path=(Find-AppExe 'chrome') },
    @{ Name='Microsoft Edge'; ExeName='msedge'; Path=(Find-AppExe 'msedge') },
    @{ Name='Mozilla Firefox'; ExeName='firefox'; Path=(Find-AppExe 'firefox') }
  )
  $found = $false
  foreach($b in $list){
    if ($b.Path) {
      $GridPwTiles.Children.Add( (New-NavTile -Title $b.Name -ExeName $b.ExeName -ExePath $b.Path) ) | Out-Null
      $found = $true
    }
  }
  if (-not $found) { $lbl = New-Object System.Windows.Controls.TextBlock; $lbl.Text = "Aucun navigateur détecté."; $GridPwTiles.Children.Add($lbl) | Out-Null }
}

# --------- Résumé avant exécution ----------
function Get-YesNo([bool]$b){ if($b){'Oui'}else{'Non'} }
function Update-Summary {
  try {
    $isExport = [bool]$rbExport.IsChecked
    $srcRoot  = $tbImportSrc.Text
    $destRoot = $tbExportDest.Text
    $client   = $tbClientName.Text.Trim()
    $pathsSel = @(Get-SelectedPaths)
    $opts = Get-Options
    $lines = New-Object System.Collections.Generic.List[string]
    $mode = if ($isExport) { "EXPORT" } else { "IMPORT" }
    $lines.Add("Mode : $mode")
    if ($isExport) {
      $clientDisplay = if (-not [string]::IsNullOrWhiteSpace($client)) { $client } else { "(non renseigné)" }
      $lines.Add("Client : " + $clientDisplay)
      $lines.Add("Destination export : " + $destRoot)
    } else {
      $lines.Add("Source import : " + $srcRoot)
    }
    if (-not $opts.SkipCopy) {
      if ($pathsSel.Count -gt 0) {
        $lines.Add("Dossiers sélectionnés :")
        foreach($p in $pathsSel){ $lines.Add("  - " + $p) }
      } else { $lines.Add("Dossiers sélectionnés : (aucun)") }
    } else { $lines.Add("Dossiers : saut de copie (SkipCopy = Oui)") }
    $lines.Add("Options :")
    $lines.Add("  - Wi-Fi : "                 + (Get-YesNo $opts.Wifi))
    $lines.Add("  - Imprimantes : "           + (Get-YesNo $opts.Printers))
    $lines.Add("  - Pilotes d’imprimantes : " + (Get-YesNo $opts.PrinterDrivers))
    $lines.Add("  - Barre des tâches : "      + (Get-YesNo $opts.Taskbar))
    $lines.Add("  - Menu Démarrer : "         + (Get-YesNo $opts.StartMenu))
    $lines.Add("  - Fond d’écran : "          + (Get-YesNo $opts.Wallpaper))
    $lines.Add("  - Positions d’icônes : "    + (Get-YesNo $opts.DesktopPos))
    $lines.Add("  - RDP : "                 + (Get-YesNo $opts.RDP))
    $lines.Add("  - Lecteurs réseau : "       + (Get-YesNo $opts.NetDrives))
    $lines.Add("  - Accès rapide : "        + (Get-YesNo $opts.QuickAccess))
    $lines.Add("  - Exclure gros fichiers : " + (Get-YesNo $opts.FilterBig))
    $lines.Add("  - AppData Chrome : "        + (Get-YesNo $opts.AppDataChrome))
    $lines.Add("  - AppData Edge : "          + (Get-YesNo $opts.AppDataEdge))
    $lines.Add("  - AppData Firefox : "       + (Get-YesNo $opts.AppDataFirefox))
    $lines.Add("  - AppData Outlook : "       + (Get-YesNo $opts.AppDataOutlook))
    $txtSummary.Text = ($lines -join [Environment]::NewLine)
  } catch {
    $txtSummary.Text = "Impossible de générer le résumé : $($_.Exception.Message)"
  }
}

# --------- Navigation (pages) ----------
function Show-Page([int]$n){
  foreach($pg in @($page1,$page2,$page3,$page4,$page5,$pagePasswords)){ if ($pg) { $pg.Visibility = 'Collapsed' } }
  switch ($n) {
    1 { $page1.Visibility = 'Visible' }
    2 { $page2.Visibility = 'Visible' }
    20 { $pagePasswords.Visibility = 'Visible' }
    3 { $page3.Visibility = 'Visible' }
    4 { $page4.Visibility = 'Visible' }
    5 { $page5.Visibility = 'Visible' }
    default { $page1.Visibility = 'Visible' }
  }
  $script:CurrentPage = $n
  # État boutons
  if ($btnPrev) { $btnPrev.IsEnabled = ($n -gt 1) }
  if ($btnNext) { $btnNext.Visibility = 'Visible'; $btnRun.Visibility = 'Collapsed' }
  if ($n -eq 3) {
    if ($btnNext) { $btnNext.Visibility = 'Collapsed' }
    if ($btnRun)  { $btnRun.Visibility = 'Visible' ; $btnRun.IsEnabled = [bool]$cbConfirm.IsChecked }
  }
}
# Initialiser BuildRoots (export par défaut)
try { BuildRoots } catch {}
Update-Summary

# Détection Outlook et masquage/désactivation de la case si non installé
try {
  $od = Detect-OutlookInstalled
  if (-not $od.Installed -and $cbAppOutlook) {
    $cbAppOutlook.IsEnabled = $false
    $cbAppOutlook.ToolTip   = "Outlook non détecté sur ce poste"
  }
} catch { Log "Init Outlook detect: $($_.Exception.Message)" }

# Radio Export/Import
$null = $rbExport.Add_Checked({
  $script:IsExport = $true
  Show-Page 2
  try { BuildRoots } catch {}
  Update-NextAndExclusivity
  Update-Summary
})
$null = $rbImport.Add_Checked({
  $script:IsExport = $false
  Show-Page 2
  Update-NextAndExclusivity
  Update-Summary
})

# Affichage cachés
$cbShowHidden.Add_Checked({ if ($script:IsExport -and (-not $script:ImportRoot)) { try { BuildRoots } catch {} } Update-Summary })
$cbShowHidden.Add_Unchecked({ if ($script:IsExport -and (-not $script:ImportRoot)) { try { BuildRoots } catch {} } Update-Summary })

# Boutons Next/Prev
$btnPrev.Add_Click({
  switch ($script:CurrentPage) {
    2 { Show-Page 1 }
    20 { Show-Page 2 }
    3 { Show-Page 2 }
    4 { Show-Page 3 }
    5 { Show-Page 4 }
    default { Show-Page 1 }
  }
})
$cbConfirm.Add_Checked({ if ($btnRun) { $btnRun.IsEnabled = $true } })
$cbConfirm.Add_Unchecked({ if ($btnRun) { $btnRun.IsEnabled = $false } })

# Pick dossiers Export/Import
$btnPickExport.Add_Click({
  $sel = Select-Folder -Title "Choisir le dossier destination (racine des exports)" -InitialPath ""
  if ($sel) { $tbExportDest.Text = $sel }
  Update-Summary
})
$btnPickImport.Add_Click({
  $sel = Select-Folder -Title "Choisir le dossier client (export)" -InitialPath ""
  if (-not $sel -or -not (Test-Path $sel)) { return }
  $tbImportSrc.Text = $sel
  $script:ImportRoot = $sel
  try {
    $leaf = Split-Path $sel -Leaf
    if ($tbImportClient) { $tbImportClient.Text = $leaf }
  } catch {}
  try { $script:ImportInfo = Detect-ImportContents -Folder $sel } catch {
    [System.Windows.MessageBox]::Show("Échec de la détection du contenu d'export : $($_.Exception.Message)","Import",
      [System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Error) | Out-Null
    return
  }
  try { ApplyImportPreset -Info $script:ImportInfo } catch {
    [System.Windows.MessageBox]::Show("Échec lors de l’application du preset d’import : $($_.Exception.Message)","Import",
      [System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Error) | Out-Null
  }
  Update-Summary
})

# --------- Preset d’import ----------
function ApplyImportPreset {
  param([Parameter(Mandatory)][pscustomobject]$Info)
  $script:ImportPresetApplied = $true
  # Arbre depuis manifest Paths + contenus réels
  $paths = @()
  if ($Info.Paths) { $paths += @($Info.Paths) }
  # Ajouter standards si présents
  foreach($k in @('Desktop','Documents','Downloads','Pictures','Music','Videos','Favorites','Links','Contacts','AppData\Local','AppData\Roaming')){
    $p = Join-Path $ProfilePath $k
    if ($Info.Paths -notcontains $p) { $paths += $p }
  }
  PopulateTreeFromPaths -Paths $paths
  # Options en fonction de la détection
  $cbWifi.IsChecked           = [bool]($Info.WifiXml -gt 0)
  $cbPrinters.IsChecked       = [bool]$Info.PrintSnapshot -or [bool]$Info.PrintBrm
  $cbPrinterDrivers.IsChecked = [bool]($Info.DriversInf -gt 0)
  $cbWallpaper.IsChecked      = [bool]($Info.WallpaperFiles -gt 0)
  $cbDesktopPos.IsChecked     = [bool]$Info.RegDesktop
  $cbNetDrives.IsChecked      = [bool]$Info.NetDrivesCsv
  $cbTaskbar.IsChecked        = [bool]($Info.HasTaskband -or $Info.HasTaskbarPins)
  $cbStartMenu.IsChecked      = [bool]$Info.HasUIStart
  $cbAppChrome.IsChecked      = [bool]$Info.AppDataChrome
  $cbAppEdge.IsChecked        = [bool]$Info.AppDataEdge
  $cbAppFirefox.IsChecked     = [bool]$Info.AppDataFirefox
  $cbAppOutlook.IsChecked     = [bool]$Info.AppDataOutlook
  Update-NextAndExclusivity
  Update-Summary
}

# --------- Phase Export ---------
function Do-Export {
  try {
    # 1) Préparer la destination et le nom client
    $root = $tbExportDest.Text
    if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path -LiteralPath $root)) {
      [System.Windows.MessageBox]::Show("Destination d’export invalide ou inaccessible.","Export",
        [System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Error) | Out-Null
      return
    }

    $clientRaw = $tbClientName.Text
    if ([string]::IsNullOrWhiteSpace($clientRaw)) {
      try { $tbClientName.Focus() } catch {}
      [System.Windows.MessageBox]::Show("Nom du client manquant.", "Export",
        [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
      return
    }
    $client = Sanitize-ClientName -Name $clientRaw.Trim()

    $outDir = Join-Path $root $client
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null

    # 2) Construire le plan et le manifeste
    $paths = @(Get-SelectedPaths)
    $opts = Get-Options
    $manifest = [ordered]@{
      Mode   = 'Export'
      When   = (Get-Date).ToString('s')
      User   = $Account
      Source = $env:COMPUTERNAME
      Paths  = $paths
      Options= $opts
    }
    Save-Manifests -folder $outDir -data $manifest

    # 3) Exécuter
    Show-Page 4
    Set-Progress 1 "Préparation…"

    # 3.1) Copie de dossiers
    if (-not $opts.SkipCopy) {
      $copyRoot = Join-Path $outDir 'Profile'
      New-Item -ItemType Directory -Force -Path $copyRoot | Out-Null
      $i = 0
      foreach($p in $paths){
        $i++
        try {
          $src = Get-ExportSourceForPath -SelectedPath $p
          $label = ComputeLabelForDest -Dest $p -ProfileRoot $ProfilePath
          $dst  = Join-Path $copyRoot $label
          Set-Progress ([math]::Min(90,(10 + ($i * (60.0/[math]::Max(1,$paths.Count)))))) "Copie : $label"
          Copy-Tree -src $src -dst $dst
        } catch { Log "Copie dossier '$p' : $($_.Exception.Message)" }
      }
      # Bureau public fusionné à part
      $pubDesk = 'C:\Users\Public\Desktop'
      try {
        $dstPub = Join-Path $outDir 'Public\Desktop'
        if (Test-Path $pubDesk) { Copy-Tree -src $pubDesk -dst $dstPub }
      } catch { Log "Copie Public Desktop : $($_.Exception.Message)" }
    }

    # 3.2) Sections optionnelles
    if ($opts.Wifi)           { Set-Progress 75 "Wi-Fi…";           Export-WifiProfiles -OutRoot $outDir }
    if ($opts.NetDrives)      { Set-Progress 76 "Lecteurs réseau…";      Export-NetworkDrives -OutRoot $outDir }
    if ($opts.QuickAccess)    { Set-Progress 76.5 "Accès rapide…";       Export-ExplorerQuickAccess -OutRoot $outDir }
    if ($opts.Printers) {
      Set-Progress 77 "Imprimantes…"
      $prnDir = Join-Path $outDir 'Printers'
      New-Item -ItemType Directory -Force -Path $prnDir | Out-Null
      $okBrm = $false
      try { $okBrm = Export-PrintersViaPrintBrm -outDir $prnDir } catch {}
      if ($opts.PrinterDrivers) { try { Export-PrinterDriversTargeted -OutDir (Join-Path $prnDir 'Drivers') } catch {} }
      try { Export-PrinterSnapshot -outDir $prnDir } catch {}
    }
    if ($opts.Taskbar -or $opts.StartMenu) { Set-Progress 78 "Barre des tâches / Menu Démarrer…"; Export-TaskbarAndStart -OutRoot $outDir }
    if ($opts.Wallpaper)       { Set-Progress 79 "Fond d’écran…";            Export-WallpaperSimple -OutRoot $outDir }
    if ($opts.DesktopPos)      { Set-Progress 80 "Positions d’icônes…";      Save-DesktopLayout -OutDir $outDir }
    if ($opts.RDP)           { Set-Progress 76.8 "Connexions RDP…";      Export-RDPConnections -OutRoot $outDir }
    if ($opts.AppDataOutlook)  { Set-Progress 81 "Outlook…";                 Export-AppDataOutlook -OutRoot $outDir }

    # 3.3) Navigateurs: tuile mots de passe déjà fournie (pas d’export automatique)
    Build-PasswordTiles -GridPwTiles $gridPwTiles

    Set-Progress 100 "Export terminé."
    Log "Export terminé."
    Update-LogLink -Path $Global:LastLogPath


    # Page Terminé + réactivation claire des actions
    Show-Page 5
    Invoke-UI {
      if ($btnRun)   { $btnRun.Visibility  = 'Collapsed' }
      if ($btnNext)  { $btnNext.Visibility = 'Visible';   $btnNext.IsEnabled = $true }
      if ($btnClose) { $btnClose.Visibility= 'Visible';   $btnClose.IsEnabled= $true }
    }
  } catch {
    Log "Do-Export : $($_.Exception.Message)"
    [System.Windows.MessageBox]::Show("Erreur pendant l’export : $($_.Exception.Message)","Export",
      [System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Error) | Out-Null
    Show-Page 5
    Invoke-UI {
      if ($btnRun)   { $btnRun.Visibility  = 'Collapsed' }
      if ($btnNext)  { $btnNext.Visibility = 'Visible';   $btnNext.IsEnabled = $true }
      if ($btnClose) { $btnClose.Visibility= 'Visible';   $btnClose.IsEnabled= $true }
    }
  }
}
# --------- Phase Import ---------
function Do-Import {
  try {
    # 1) Source d’import
    $in = $tbImportSrc.Text
    if ([string]::IsNullOrWhiteSpace($in) -or -not (Test-Path $in)) {
      [System.Windows.MessageBox]::Show("Dossier d’import invalide.","Import",
        [System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Error) | Out-Null
      return
    }
    # 2) Manifest
    $manifest = Load-Manifest $in
    $paths = @(Get-SelectedPaths)
    $opts = Get-Options
    $newManifest = [ordered]@{
      Mode   = 'Import'
      When   = (Get-Date).ToString('s')
      User   = $Account
      Source = $env:COMPUTERNAME
      Paths  = $paths
      Options= $opts
    }
    Merge-Manifests -folder $in -new $newManifest

    # 3) Exécuter
    Show-Page 4
    Set-Progress 1 "Préparation…"

    # 3.1) Copie de dossiers
    if (-not $opts.SkipCopy) {
      $profileSrc = Join-Path $in 'Profile'
      $i = 0
      foreach($dest in $paths){
        $i++
        try {
          $label = ComputeLabelForDest -Dest $dest -ProfileRoot $ProfilePath
          $src   = Join-Path $profileSrc $label
          if (-not (Test-Path $src)) {
            # fallback leaf
            $src = Join-Path $profileSrc (Split-Path $dest -Leaf)
          }
          if (Test-Path $src) {
            Set-Progress ([math]::Min(90,(10 + ($i * (60.0/[math]::Max(1,$paths.Count)))))) "Copie : $label"
            New-Item -ItemType Directory -Force -Path $dest | Out-Null
            Copy-Tree -src $src -dst $dest
          } else {
            Log "Import: source absente pour $label ($src)"
          }
        } catch { Log "Import dossier '$dest' : $($_.Exception.Message)" }
      }
      # Bureau public
      try {
        $srcPub = Join-Path $in 'Public\Desktop'
        $dstPub = 'C:\Users\Public\Desktop'
        if (Test-Path $srcPub) { Copy-Tree -src $srcPub -dst $dstPub }
      } catch { Log "Import Public Desktop : $($_.Exception.Message)" }
    }
    # Correction ACL basique (optionnelle)
    if ($script:EnableAclFix) {
      try { Ensure-OwnershipAndAcl -Path $env:USERPROFILE } catch {}
      try { Ensure-OwnershipAndAcl -Path 'C:\Users\Public\Desktop' } catch {}
    }
    # 3.2) Sections optionnelles
    if ($opts.Wifi)           { Set-Progress 75 "Wi-Fi…";         Import-WifiProfiles -InRoot $in }
    if ($opts.NetDrives)      { Set-Progress 76 "Lecteurs réseau…";    Import-NetworkDrives -InRoot $in }
    if ($opts.QuickAccess)    { Set-Progress 76.5 "Accès rapide…";     Import-ExplorerQuickAccess -InRoot $in }
    if ($opts.Printers) {
      Set-Progress 77 "Imprimantes…"
      $prnDir = Join-Path $in 'Printers'
      $ok = $false
      try { $ok = Import-PrintersViaPrintBrm -inDir $prnDir } catch {}
      if (-not $ok) { try { Import-PrintersFromSnapshot -inDir $prnDir } catch {} }
      if ($opts.PrinterDrivers) {
        try {
          $drvDir = Join-Path $prnDir 'Drivers'
          if (Test-Path $drvDir) {
            Get-ChildItem $drvDir -Recurse -Filter *.inf -ErrorAction SilentlyContinue | ForEach-Object {
              try { pnputil /add-driver "`"$($_.FullName)`"" /install /subdirs 2>&1 | Out-Null; Log "Pilote installé: $($_.Name)" }
              catch { Log "Pilote : $($_.Exception.Message)" }
            }
          }
        } catch {}
      }
    }
    if ($opts.Taskbar -or $opts.StartMenu) { Set-Progress 78 "Barre des tâches / Menu Démarrer…"; Import-TaskbarAndStart -InRoot $in }
    if ($opts.Wallpaper) {
      Set-Progress 79 "Fond d’écran…"
      try {
        $wpDir = Join-Path $in 'Wallpaper'
        $txt = Join-Path $wpDir 'wallpaper.txt'
        $fileName = $null
        if (Test-Path $txt) { $fileName = (Get-Content $txt -Raw).Trim() }
        $img = $null
        if ($fileName) { $img = Join-Path $wpDir $fileName } else {
          $cand = Get-ChildItem $wpDir -File -ErrorAction SilentlyContinue | Select-Object -First 1
          if ($cand) { $img = $cand.FullName }
        }
        if ($img) { Set-WallpaperSafe -ImagePath $img } else { Log "Fond d’écran : aucune image trouvée." }
      } catch { Log "Fond d’écran import : $($_.Exception.Message)" }
    }
    if ($opts.DesktopPos) {
      Set-Progress 80 "Positions d’icônes…"
      try { Restore-DesktopLayout -InDir $in } catch { Log "Restore-DesktopLayout : $($_.Exception.Message)" }
    }
    if ($opts.RDP)           { Set-Progress 76.8 "Connexions RDP…";      Import-RDPConnections -InRoot $in }
    if ($opts.AppDataOutlook) { Set-Progress 81 "Outlook…"; Import-AppDataOutlook -InRoot $in }

    # 3.3) Étape MDP navigateurs après import
    Build-PasswordTiles -GridPwTiles $gridPwTiles
    $lblPwTitle.Text = "Si nécessaire, réimportez les mots de passe des navigateurs (selon les outils natifs)."
    Show-Page 20

    Set-Progress 100 "Import terminé."
    Log "Import terminé."
    Update-LogLink -Path $Global:LastLogPath

  } catch {
    Log "Do-Import : $($_.Exception.Message)"
    [System.Windows.MessageBox]::Show("Erreur pendant l’import : $($_.Exception.Message)","Import",
      [System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Error) | Out-Null
    Show-Page 5
  }
}

# --------- Exclusions et filtres avancés ----------
function Set-DefaultExclusions {
  # Remise à zéro
  $Global:ExcludePatterns       = @()
  $Global:ExcludePatternsFiles  = @()
  $Global:ExcludePatternsDirs   = @()

  # Dossiers typiquement inutiles pour une migration de données utilisateur
  $Global:ExcludePatternsDirs = @(
  'AppData\Local\Temp',
  'AppData\Local\Packages',
  'AppData\Local\Microsoft\Windows\INetCache',
  'AppData\Local\Microsoft\Windows\Explorer',
  'AppData\Local\CrashDumps',
  'AppData\Local\Adobe\Temp',
  'AppData\Local\Google\Chrome\User Data\Default\Code Cache',
  'AppData\Local\Google\Chrome\User Data\Default\GPUCache',
  'AppData\Local\Microsoft\Edge\User Data\Default\Code Cache',
  'AppData\Local\Microsoft\Edge\User Data\Default\GPUCache',
  'AppData\Local\Microsoft\Edge\User Data\Default\Service Worker\CacheStorage',
  'AppData\Local\Mozilla\Firefox\Profiles\*\cache2',
  'AppData\Roaming\Microsoft\Windows\Recent'
)


  # Fichiers lourds et archives fréquentes si FilterBig actif (complément via option)
  $Global:ExcludePatternsFiles += @(
    '*.iso','*.vhd','*.vhdx','*.img',
    '*.bak','*.tmp','*.temp',
    '*.zip','*.7z','*.rar',
    '*.log'
  )

  # Fichiers Outlook volumineux (déjà exclus dans Export-AppDataOutlook)
  # Ajout facultatif ici si besoin global
  # $Global:ExcludePatternsFiles += @('*.ost','*.pst')

  # Exclusions mixtes (s’appliquent comme XF/XD dans Copy-Tree)
  $Global:ExcludePatterns += @(
    'Thumbs.db',
    'desktop.ini',
    '$RECYCLE.BIN',
    'System Volume Information'
  )
}
Set-DefaultExclusions

# --------- Estimation d’espace disque ----------
function Estimate-BytesToCopy {
  param([Parameter(Mandatory)][string[]]$Paths)
  [long]$sum = 0
  foreach($p in $Paths){
    if (-not $p -or -not (Test-Path $p)) { continue }
    try {
      Get-ChildItem -LiteralPath $p -Recurse -Force -File -ErrorAction SilentlyContinue |
        ForEach-Object { $sum += [long]($_.Length) }
    } catch {}
  }
  return $sum
}
function Estimate-BytesFromExportProfile {
  param([Parameter(Mandatory)][string]$ExportRoot)
  $profile = Join-Path $ExportRoot 'Profile'
  if (-not (Test-Path $profile)) { return 0 }
  [long]$sum = 0
  try {
    Get-ChildItem -LiteralPath $profile -Recurse -Force -File -ErrorAction SilentlyContinue |
      ForEach-Object { $sum += [long]($_.Length) }
  } catch {}
  return $sum
}

# --------- Sécurité : validation de nom client et de chemins ----------
function Ensure-Directory {
  param([Parameter(Mandatory)][string]$Path)
  try {
    if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Force -Path $Path | Out-Null }
    return $true
  } catch { Log "Ensure-Directory: $($_.Exception.Message)"; return $false }
}

# --------- Export AppData navigateurs ----------
function Export-AppDataBrowsers {
  param([Parameter(Mandatory)][string]$OutRoot,
        [bool]$Chrome = $false,
        [bool]$Edge   = $false,
        [bool]$Firefox= $false)
  try {
    $base = Join-Path $OutRoot 'AppDataBrowsers'
    Ensure-Directory -Path $base | Out-Null

    if ($Chrome) {
      try {
        $srcC = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
        if (Test-Path $srcC) {
          $dstC = Join-Path $base 'Chrome'
          Ensure-Directory -Path $dstC | Out-Null
          Copy-Tree -src $srcC -dst $dstC
          Log "AppData Chrome exporté."
        } else { Log "Chrome: dossier introuvable." }
      } catch { Log "Chrome export : $($_.Exception.Message)" }
    }

    if ($Edge) {
      try {
        $srcE = Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data'
        if (Test-Path $srcE) {
          $dstE = Join-Path $base 'Edge'
          Ensure-Directory -Path $dstE | Out-Null
          Copy-Tree -src $srcE -dst $dstE
          Log "AppData Edge exporté."
        } else { Log "Edge: dossier introuvable." }
      } catch { Log "Edge export : $($_.Exception.Message)" }
    }

    if ($Firefox) {
      try {
        $srcF = Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles'
        if (Test-Path $srcF) {
          $dstF = Join-Path $base 'Firefox'
          Ensure-Directory -Path $dstF | Out-Null
          Copy-Tree -src $srcF -dst $dstF
          Log "AppData Firefox exporté."
        } else { Log "Firefox: dossier introuvable." }
      } catch { Log "Firefox export : $($_.Exception.Message)" }
    }
  } catch { Log "Export AppDataBrowsers : $($_.Exception.Message)" }
}
function Import-AppDataBrowsers {
  param([Parameter(Mandatory)][string]$InRoot,
        [bool]$Chrome = $false,
        [bool]$Edge   = $false,
        [bool]$Firefox= $false)
  try {
    $base = Join-Path $InRoot 'AppDataBrowsers'
    if (-not (Test-Path $base)) { Log "AppDataBrowsers absent — rien à restaurer."; return }

    if ($Chrome) {
      try {
        $srcC = Join-Path $base 'Chrome'
        $dstC = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
        if (Test-Path $srcC) { Ensure-Directory -Path $dstC | Out-Null; Copy-Tree -src $srcC -dst $dstC; Log "AppData Chrome importé." }
      } catch { Log "Chrome import : $($_.Exception.Message)" }
    }

    if ($Edge) {
      try {
        $srcE = Join-Path $base 'Edge'
        $dstE = Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data'
        if (Test-Path $srcE) { Ensure-Directory -Path $dstE | Out-Null; Copy-Tree -src $srcE -dst $dstE; Log "AppData Edge importé." }
      } catch { Log "Edge import : $($_.Exception.Message)" }
    }

    if ($Firefox) {
      try {
        $srcF = Join-Path $base 'Firefox'
        $dstF = Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles'
        if (Test-Path $srcF) { Ensure-Directory -Path $dstF | Out-Null; Copy-Tree -src $srcF -dst $dstF; Log "AppData Firefox importé." }
      } catch { Log "Firefox import : $($_.Exception.Message)" }
    }
  } catch { Log "Import AppDataBrowsers : $($_.Exception.Message)" }
}

# --------- Amélioration des logs: export HTML ----------
function Write-LogHtml {
  param([Parameter(Mandatory)][string]$TextLogPath)
  try {
    if (-not (Test-Path $TextLogPath)) { return $null }
    $htmlPath = [System.IO.Path]::ChangeExtension($TextLogPath,'.html')
    $lines = Get-Content $TextLogPath

    $builder = New-Object System.Text.StringBuilder

    # En-tête HTML (here-string simple pour éviter problèmes d'apostrophes / encodage)
    $head = @'
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Migration Log</title>
<style>
  body { font-family: Consolas, monospace; background:#0b1220; color:#e8eefc; }
  .ts { color:#a8b2d1 }
  .ok { color:#98c379 }
  .err { color:#e06c75 }
  pre { white-space: pre-wrap; word-break: break-word; }
</style>
</head>
<body>
<h2>Journal d'exécution</h2>
<pre>
'@

    [void]$builder.AppendLine($head)

    foreach ($l in $lines) {
      if (-not $l) {
        [void]$builder.AppendLine("<span class='ts'></span> - <span class='ok'></span>")
        continue
      }
      # Séparer série temporelle et message sur " - " si présent
      $parts = $l -split ' - ', 2
      $ts = if ($parts.Count -ge 1) { [System.Web.HttpUtility]::HtmlEncode($parts[0]) } else { "" }
      $msg = if ($parts.Count -ge 2) { [System.Web.HttpUtility]::HtmlEncode($parts[1]) } else { [System.Web.HttpUtility]::HtmlEncode($parts[0]) }

      $cls = 'ok'
      if ($msg -match '(?i)erreur|KO|fail|échec') { $cls = 'err' }

      [void]$builder.AppendLine("<span class='ts'>$ts</span> - <span class='$cls'>$msg</span>")
    }

    $foot = @'
</pre>
</body>
</html>
'@

    [void]$builder.AppendLine($foot)

    [System.IO.File]::WriteAllText($htmlPath, $builder.ToString(), [System.Text.Encoding]::UTF8)
    return $htmlPath
  } catch {
    Log "Write-LogHtml : $($_.Exception.Message)"
    return $null
  }
}

# --------- Intégration OneDrive/KFM pendant export/import ----------
function Export-OneDriveIfNeeded {
  param([Parameter(Mandatory)][string]$OutRoot,[Parameter(Mandatory)][string[]]$SelectedPaths)
  try {
    # Si certains chemins sont sous OneDrive, offrir une exportation parallèle dans OneDrive\*
    $underOD = $SelectedPaths | Where-Object { Is-UnderOneDrive $_ }
    if ($underOD.Count -gt 0) {
      Log "Détection OneDrive: export complémentaire OneDrive (KFM)."
      Export-OneDriveTrees -OutDir $OutRoot
    }
  } catch { Log "Export-OneDriveIfNeeded : $($_.Exception.Message)" }
}
function Import-OneDriveIfAvailable {
  param([Parameter(Mandatory)][string]$InRoot)
  try {
    $odDir = Join-Path $InRoot 'OneDrive'
    if (Test-Path $odDir) {
      Log "Import OneDrive présent: hydratation/copie."
      Import-OneDriveTrees -InDir $InRoot
    }
  } catch { Log "Import-OneDriveIfAvailable : $($_.Exception.Message)" }
}

# --------- Nettoyage des flux et correction ACL basiques ----------
function Ensure-OwnershipAndAcl {
  param([Parameter(Mandatory)][string]$Path)
  try {
    # Best-effort: éviter les ACL bloquantes sur fichiers importés
    $items = Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    foreach($i in $items){
      try { icacls "`"$($i.FullName)`"" /inheritance:e /grant:r "$env:USERNAME:(OI)(CI)F" /T 2>&1 | Out-Null } catch {}
    }
  } catch { Log "Ensure-OwnershipAndAcl : $($_.Exception.Message)" }
}

# --------- Amélioration: vérification d’espace avant copie ----------
function Preflight-SpaceCheck-Export {
  param([Parameter(Mandatory)][string]$DestRoot,[Parameter(Mandatory)][string[]]$Paths,[bool]$SkipCopy = $false)
  if ($SkipCopy) { return $true }
  try {
    [long]$need = Estimate-BytesToCopy -Paths $Paths
    if ($need -le 0) { return $true }
    $ok = Ensure-FreeSpace -TargetPath $DestRoot -NeededBytes $need
    if (-not $ok) {
      [System.Windows.MessageBox]::Show("Espace disque insuffisant pour l’export. Estimation: $([math]::Round($need/1GB,2)) GB","Export",
        [System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Warning) | Out-Null
    }
    return $ok
  } catch { Log "Preflight-SpaceCheck-Export : $($_.Exception.Message)"; return $true }
}
function Preflight-SpaceCheck-Import {
  param([Parameter(Mandatory)][string]$DestRoot,[Parameter(Mandatory)][string]$ExportRoot,[bool]$SkipCopy = $false)
  if ($SkipCopy) { return $true }
  try {
    [long]$need = Estimate-BytesFromExportProfile -ExportRoot $ExportRoot
    if ($need -le 0) { return $true }
    $ok = Ensure-FreeSpace -TargetPath $DestRoot -NeededBytes $need
    if (-not $ok) {
      [System.Windows.MessageBox]::Show("Espace disque insuffisant pour l’import. Estimation: $([math]::Round($need/1GB,2)) GB","Import",
        [System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Warning) | Out-Null
    }
    return $ok
  } catch { Log "Preflight-SpaceCheck-Import : $($_.Exception.Message)"; return $true }
}

# --------- Correction: appliquer FilterBig proprement sur Copy-Tree ----------
function Apply-FilterBigIfNeeded {
  param([bool]$FilterBig)

  # Toujours repartir des exclusions par défaut
  Set-DefaultExclusions

  if ($FilterBig) {
    $extra = @('*.iso','*.vhd','*.vhdx','*.img','*.ova','*.ovf','*.zip','*.7z','*.rar','*.bak','*.tmp','*.temp','*.log')
    $Global:ExcludePatternsFiles = @($Global:ExcludePatternsFiles + $extra) | Select-Object -Unique

    # Size cap prêt, désactivé par défaut
    $Global:MaxFileSizeMB = $null  # Pour activer: par ex. 2500 (~2.5GB)
  } else {
    $Global:MaxFileSizeMB = $null
  }
}

# --------- Intégration à Do-Export / Do-Import (compléments) ----------
function Do-Export-Extras {
  param([Parameter(Mandatory)][string]$OutDir,[Parameter(Mandatory)][hashtable]$Options,[Parameter(Mandatory)][string[]]$Paths)
  try {
    # Estimation et espace
    $okSpace = Preflight-SpaceCheck-Export -DestRoot $OutDir -Paths $Paths -SkipCopy $Options.SkipCopy
    if (-not $okSpace) { Log "Export annulé: espace insuffisant."; return $false }

    # FilterBig
    Apply-FilterBigIfNeeded -FilterBig $Options.FilterBig

    # OneDrive complémentaire
    Export-OneDriveIfNeeded -OutRoot $OutDir -SelectedPaths $Paths

    # AppData Navigateurs
    if ($Options.AppDataChrome -or $Options.AppDataEdge -or $Options.AppDataFirefox) {
      Export-AppDataBrowsers -OutRoot $OutDir -Chrome:$Options.AppDataChrome -Edge:$Options.AppDataEdge -Firefox:$Options.AppDataFirefox
    }
    return $true
  } catch { Log "Do-Export-Extras : $($_.Exception.Message)"; return $false }
}
function Do-Import-Extras {
  param([Parameter(Mandatory)][string]$InDir,[Parameter(Mandatory)][hashtable]$Options)
  try {
    # Espace
    $okSpace = Preflight-SpaceCheck-Import -DestRoot $env:SystemDrive -ExportRoot $InDir -SkipCopy $Options.SkipCopy
    if (-not $okSpace) { Log "Import: espace insuffisant."; return $false }

    # FilterBig
    Apply-FilterBigIfNeeded -FilterBig $Options.FilterBig

    # OneDrive
    Import-OneDriveIfAvailable -InRoot $InDir

    # AppData Navigateurs
    if ($Options.AppDataChrome -or $Options.AppDataEdge -or $Options.AppDataFirefox) {
      Import-AppDataBrowsers -InRoot $InDir -Chrome:$Options.AppDataChrome -Edge:$Options.AppDataEdge -Firefox:$Options.AppDataFirefox
    }
    return $true
  } catch { Log "Do-Import-Extras : $($_.Exception.Message)"; return $false }
}

# --------- Surcouche: exécutions sécurisées (wrap) ----------

function Run-Import-Safe {
  try {
    $in = $tbImportSrc.Text
    if ([string]::IsNullOrWhiteSpace($in) -or -not (Test-Path $in)) {
      [System.Windows.MessageBox]::Show("Dossier d’import invalide.","Import",
        [System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Error) | Out-Null
      return
    }
    $paths = @(Get-SelectedPaths)
    $opts = Get-Options
    # Log
    $logPath = Write-LogToDisk -PrimaryPath (Join-Path $in "import.log") -FallbackKey "import"
    $lblLogPath.Text = $logPath
    Update-LogLink -Path $logPath

    # Extras
    if (-not (Do-Import-Extras -InDir $in -Options $opts)) { return }

    # Exécution
    Show-Page 4
    Set-Progress 1 "Préparation…"
    Do-Import

    # Log HTML
    $html = Write-LogHtml -TextLogPath $logPath
    if ($html) { Log "Log HTML : $html" }
  } catch {
    Log "Run-Import-Safe : $($_.Exception.Message)"
    [System.Windows.MessageBox]::Show("Erreur import (safe) : $($_.Exception.Message)","Import",
      [System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Error) | Out-Null
    Show-Page 5
  }
}
# --------- Amélioration UI : état log et lien ----------

function Run-Export-Safe {
  try {
    $paths = @(Get-SelectedPaths)
    $opts = Get-Options
    $clientRaw  = $tbClientName.Text.Trim()
    $client     = Sanitize-ClientName -Name $clientRaw
    $rootDest   = $tbExportDest.Text
    Log "DEBUG: entrée Run-Export-Safe avec clientRaw='$clientRaw' client='$client' rootDest='$rootDest'"

    if ([string]::IsNullOrWhiteSpace($clientRaw)) {
      [System.Windows.MessageBox]::Show("Nom du client manquant.","Export",
        [System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Error) | Out-Null
      try { $tbClientName.Focus() } catch {}
      return
    }

    if ($client -ne $clientRaw) {
      try { $tbClientName.Text = $client } catch {}
    }

    if (-not (Test-Path $rootDest)) {
      try {
        New-Item -ItemType Directory -Force -Path $rootDest | Out-Null
        Log "Destination créée automatiquement : $rootDest"
      } catch {
        [System.Windows.MessageBox]::Show("Impossible de créer le dossier destination.","Export",
          [System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Error) | Out-Null
        return
      }
    }

    $outDir = Join-Path $rootDest $client
    if (-not (Ensure-Directory -Path $outDir)) {
      [System.Windows.MessageBox]::Show("Impossible de préparer le dossier client.","Export",
        [System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Error) | Out-Null
      return
    }

    $manifest = [ordered]@{
      Mode   = 'Export'
      When   = (Get-Date).ToString('s')
      User   = $Account
      Source = $env:COMPUTERNAME
      Paths  = $paths
      Options= $opts
    }
    # Écriture manifeste déplacée dans Do-Export pour éviter doublon

    $logPath = Write-LogToDisk -PrimaryPath (Join-Path $outDir "export.log") -FallbackKey "export"
    $lblLogPath.Text = $logPath
    Update-LogLink -Path $logPath

    if (-not (Do-Export-Extras -OutDir $outDir -Options $opts -Paths $paths)) { return }

    Show-Page 4
    Set-Progress 1 "Préparation…"
    Do-Export

    $html = Write-LogHtml -TextLogPath $logPath
    if ($html) { Log "Log HTML : $html" }

    Show-Page 5
  } catch {
    Log "Run-Export-Safe : $($_.Exception.Message)"
    [System.Windows.MessageBox]::Show("Erreur export (safe) : $($_.Exception.Message)","Export",
      [System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Error) | Out-Null
    Show-Page 5
  }
}
# --------- Connexion boutons au mode Safe (gardé) ----------
# Remplace le handler direct par la surcouche robuste (retrait du handler précédent si possible)
# Garde-fou pour éviter double attachement
if ($null -eq $script:HandlersWired) { $script:HandlersWired = $false }

if (-not $script:HandlersWired) {
  $btnRun.Add_Click({
    try {
      if (-not [bool]$cbConfirm.IsChecked) {
        [System.Windows.MessageBox]::Show("Merci de confirmer le plan d’exécution avant de lancer.","Info",
          [System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Information) | Out-Null
        return
      }
      if ($script:IsExport) { Run-Export-Safe } else { Run-Import-Safe }
    } catch { Log "btnRun Safe : $($_.Exception.Message)" }
  })
  $script:HandlersWired = $true
}
# --------- Raccourcis clavier ----------
$window.Add_KeyDown({
  param($s,$e)
  try {
    if ($e.Key -eq 'Escape') { $window.Close(); $e.Handled = $true }
    elseif ($e.Key -eq 'F5') { Update-Summary; $e.Handled = $true }
    elseif ($e.Key -eq 'F9') { Check-AllTreeItems -state $true; $e.Handled = $true }
    elseif ($e.Key -eq 'F8') { Check-AllTreeItems -state $false; $e.Handled = $true }
  } catch {}
})

# --------- Hooks finaux pour la navigation ----------
# Garde-fou pour éviter double attachement du Next
if ($null -eq $script:NextHookWired) { $script:NextHookWired = $false }

if (-not $script:NextHookWired) {
  $btnNext.Add_Click({
    switch ($script:CurrentPage) {
      1 { Show-Page 2 }
      2 {
        if ($script:IsExport) {
          Build-PasswordTiles -GridPwTiles $gridPwTiles
          $lblPwTitle.Text = "Merci d’exporter les mots de passe des navigateurs ci-dessous, puis cliquez sur Suivant."
          Show-Page 20
        } else {
          Show-Page 3
        }
      }
      20 {
        try {
          if ($panelExport) { $panelExport.Visibility = 'Visible' }
          if ($panelImport) { $panelImport.Visibility = 'Collapsed' }
        } catch { Log "Patch navigation -> page Export : $($_.Exception.Message)" }
        Show-Page 3
      }
      3 {
        if (-not [bool]$cbConfirm.IsChecked) {
          [System.Windows.MessageBox]::Show("Merci de cocher la confirmation avant de continuer.","Info",
            [System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Information) | Out-Null
          return
        }
        if ($script:IsExport) { Run-Export-Safe } else { Run-Import-Safe }
      }
      default { Show-Page 2 }
    }
  })
  $script:NextHookWired = $true
}
# --------- Robustesse : empêcher fermeture pendant exécution ----------
$script:IsRunning = $false
function Set-Running([bool]$b){
  $script:IsRunning = $b
  try {
    if ($btnPrev)  { $btnPrev.IsEnabled  = -not $b }
    if ($btnNext)  { $btnNext.IsEnabled  = -not $b }
    if ($btnRun)   { $btnRun.IsEnabled   = -not $b }
    if ($btnClose) { $btnClose.IsEnabled = -not $b }
  } catch {}
}

# Encapsuler set running autour des opérations principales
$originalDoExport = ${function:Do-Export}
Set-Item -Path function:Do-Export -Value {
  Set-Running $true
  try { & $originalDoExport } finally { Set-Running $false }
}
$originalDoImport = ${function:Do-Import}
Set-Item -Path function:Do-Import -Value {
  Set-Running $true
  try { & $originalDoImport } finally { Set-Running $false }
}

# --------- Affichages initiaux et finalisation ----------
try {
  # Détection initiale simple (export par défaut)
  BuildRoots
  Update-Summary
  Show-Page 1
} catch { Log "Init UI : $($_.Exception.Message)" }

# --------- Conseils ----------
Log "Conseil: Exécuter en Administrateur pour Wi-Fi, imprimantes et modifications système."
Log "Export: privilégier un disque local ou un partage fiable. Éviter les clés USB très lentes."

# --------- Close safe (remplacé : Hide au lieu de Close) ----------
$btnClose.Add_Click({
  try {
    if ($script:IsRunning) {
      [System.Windows.MessageBox]::Show("Une opération est en cours. Merci d'attendre sa fin.","Info",
        [System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Information) | Out-Null
      return
    }
    # On cache la fenêtre pour pouvoir la réutiliser plus tard
    try { $window.Hide() } catch {}
  } catch {}
})

# --------- Afficher la fenêtre (si pas déjà affichée) ----------
try {
  if (-not $window.IsVisible) {
    $window.Topmost = $false
    $window.ShowDialog() | Out-Null
  }
} catch {
  [System.Windows.MessageBox]::Show("Erreur d’affichage fenêtre : $($_.Exception.Message)","UI",
    [System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Error) | Out-Null
}
