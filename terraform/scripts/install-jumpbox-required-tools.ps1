param(
  [string]$PythonVersion = "3.12.10"
)

$ErrorActionPreference = "Stop"

$logRoot = "C:\WindowsAzure\Logs\gpt-rag-required-tools"
$downloadRoot = Join-Path $logRoot "downloads"
New-Item -ItemType Directory -Force -Path $downloadRoot | Out-Null

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Add-MachinePath {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [switch]$Prepend
  )

  if (-not (Test-Path $Path)) {
    return
  }

  $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
  $parts = $machinePath -split ";" | Where-Object { $_ }
  if ($parts -notcontains $Path) {
    if ($Prepend) {
      [Environment]::SetEnvironmentVariable("Path", "$Path;$machinePath", "Machine")
    }
    else {
      [Environment]::SetEnvironmentVariable("Path", "$machinePath;$Path", "Machine")
    }
  }

  $sessionParts = $env:Path -split ";" | Where-Object { $_ }
  if ($sessionParts -notcontains $Path) {
    if ($Prepend) {
      $env:Path = "$Path;$env:Path"
    }
    else {
      $env:Path = "$env:Path;$Path"
    }
  }
}

function Invoke-Download {
  param(
    [Parameter(Mandatory = $true)][string]$Uri,
    [Parameter(Mandatory = $true)][string]$OutFile
  )

  Write-Host "Downloading $Uri"
  Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing
}

function Install-Executable {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Uri,
    [Parameter(Mandatory = $true)][string]$OutFile,
    [Parameter(Mandatory = $true)][string[]]$ArgumentList
  )

  Invoke-Download -Uri $Uri -OutFile $OutFile
  Write-Host "Installing $Name"
  $process = Start-Process -FilePath $OutFile -ArgumentList $ArgumentList -Wait -PassThru
  if ($process.ExitCode -notin @(0, 3010, 1641)) {
    throw "$Name installer failed with exit code $($process.ExitCode)"
  }
}

function Install-Msi {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Uri,
    [Parameter(Mandatory = $true)][string]$OutFile,
    [string[]]$ExtraArguments = @()
  )

  Invoke-Download -Uri $Uri -OutFile $OutFile
  Write-Host "Installing $Name"
  $arguments = @("/i", "`"$OutFile`"", "/qn", "/norestart") + $ExtraArguments
  $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $arguments -Wait -PassThru
  if ($process.ExitCode -notin @(0, 3010, 1641)) {
    throw "$Name MSI failed with exit code $($process.ExitCode)"
  }
}

Write-Host "Installing required GPT-RAG jumpbox tools..."

$pwshExe = "C:\Program Files\PowerShell\7\pwsh.exe"
if (-not (Test-Path $pwshExe)) {
  Write-Host "Installing PowerShell 7"
  Invoke-Expression "& { $(Invoke-RestMethod https://aka.ms/install-powershell.ps1) } -UseMSI -Quiet"
}
Add-MachinePath "C:\Program Files\PowerShell\7"
if (-not (Test-Path $pwshExe)) {
  throw "PowerShell 7 was not found at $pwshExe after install."
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
  Install-Msi `
    -Name "Azure CLI" `
    -Uri "https://aka.ms/installazurecliwindows" `
    -OutFile (Join-Path $downloadRoot "AzureCLI.msi")
}
Add-MachinePath "C:\Program Files (x86)\Microsoft SDKs\Azure\CLI2\wbin"
Add-MachinePath "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin"
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
  throw "Azure CLI command 'az' was not found after install."
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  Install-Executable `
    -Name "Git for Windows" `
    -Uri "https://github.com/git-for-windows/git/releases/latest/download/Git-64-bit.exe" `
    -OutFile (Join-Path $downloadRoot "Git-64-bit.exe") `
    -ArgumentList @("/VERYSILENT", "/NORESTART", "/NOCANCEL", "/SP-", "/CLOSEAPPLICATIONS", "/RESTARTAPPLICATIONS")
}
Add-MachinePath "C:\Program Files\Git\cmd"
Add-MachinePath "C:\Program Files\Git\bin"
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  throw "Git command 'git' was not found after install."
}

$pythonRoot = "C:\Python312"
$pythonExe = Join-Path $pythonRoot "python.exe"
if (-not (Test-Path $pythonExe)) {
  Install-Executable `
    -Name "Python $PythonVersion" `
    -Uri "https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-amd64.exe" `
    -OutFile (Join-Path $downloadRoot "python-$PythonVersion-amd64.exe") `
    -ArgumentList @("/quiet", "InstallAllUsers=1", "TargetDir=$pythonRoot", "PrependPath=0", "Include_launcher=1", "Include_pip=1", "Include_test=0")
}
Add-MachinePath $pythonRoot -Prepend
Add-MachinePath (Join-Path $pythonRoot "Scripts") -Prepend
if (-not (Test-Path $pythonExe)) {
  throw "Python executable was not found at $pythonExe after install."
}
$pythonVersionOutput = & $pythonExe --version
if ($pythonVersionOutput -notmatch "^Python 3\.12\.") {
  throw "Expected Python 3.12, but $pythonExe returned '$pythonVersionOutput'."
}

$azdRoot = "C:\AzureDevCLI"
$azdExe = Join-Path $azdRoot "azd.exe"
if (-not (Test-Path $azdExe)) {
  Write-Host "Installing Azure Developer CLI"
  New-Item -ItemType Directory -Force -Path $azdRoot | Out-Null
  $azdZip = Join-Path $downloadRoot "azd-windows-amd64.zip"
  Invoke-Download -Uri "https://azuresdkartifacts.z5.web.core.windows.net/azd/standalone/release/stable/azd-windows-amd64.zip" -OutFile $azdZip
  Expand-Archive -Path $azdZip -DestinationPath $azdRoot -Force
  $azdExtractedExe = Join-Path $azdRoot "azd-windows-amd64.exe"
  if ((Test-Path $azdExtractedExe) -and -not (Test-Path $azdExe)) {
    Move-Item -LiteralPath $azdExtractedExe -Destination $azdExe -Force
  }
}
Add-MachinePath $azdRoot -Prepend
if (-not (Test-Path $azdExe)) {
  throw "Azure Developer CLI executable was not found at $azdExe after install."
}

Write-Host ""
Write-Host "Installed tool versions:"

& $pwshExe -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
az version --query '"azure-cli"' -o tsv
& $azdExe version
git --version
& $pythonExe --version
