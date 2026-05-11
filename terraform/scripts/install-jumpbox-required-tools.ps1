param(
  [string]$PythonVersion = "3.12.10"
)

$ErrorActionPreference = "Stop"

$logRoot = "C:\WindowsAzure\Logs\gpt-rag-required-tools"
$downloadRoot = Join-Path $logRoot "downloads"
New-Item -ItemType Directory -Force -Path $downloadRoot | Out-Null

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Add-MachinePath {
  param([Parameter(Mandatory = $true)][string]$Path)

  if (-not (Test-Path $Path)) {
    return
  }

  $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
  $parts = $machinePath -split ";" | Where-Object { $_ }
  if ($parts -notcontains $Path) {
    [Environment]::SetEnvironmentVariable("Path", "$machinePath;$Path", "Machine")
  }

  $sessionParts = $env:Path -split ";" | Where-Object { $_ }
  if ($sessionParts -notcontains $Path) {
    $env:Path = "$env:Path;$Path"
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

if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
  Write-Host "Installing PowerShell 7"
  Invoke-Expression "& { $(Invoke-RestMethod https://aka.ms/install-powershell.ps1) } -UseMSI -Quiet"
}
Add-MachinePath "C:\Program Files\PowerShell\7"

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
  Install-Msi `
    -Name "Azure CLI" `
    -Uri "https://aka.ms/installazurecliwindows" `
    -OutFile (Join-Path $downloadRoot "AzureCLI.msi")
}
Add-MachinePath "C:\Program Files (x86)\Microsoft SDKs\Azure\CLI2\wbin"
Add-MachinePath "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin"

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  Install-Executable `
    -Name "Git for Windows" `
    -Uri "https://github.com/git-for-windows/git/releases/latest/download/Git-64-bit.exe" `
    -OutFile (Join-Path $downloadRoot "Git-64-bit.exe") `
    -ArgumentList @("/VERYSILENT", "/NORESTART", "/NOCANCEL", "/SP-", "/CLOSEAPPLICATIONS", "/RESTARTAPPLICATIONS")
}
Add-MachinePath "C:\Program Files\Git\cmd"
Add-MachinePath "C:\Program Files\Git\bin"

$pythonRoot = "C:\Program Files\Python312"
$pythonExe = Join-Path $pythonRoot "python.exe"
if (-not (Test-Path $pythonExe)) {
  Install-Executable `
    -Name "Python $PythonVersion" `
    -Uri "https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-amd64.exe" `
    -OutFile (Join-Path $downloadRoot "python-$PythonVersion-amd64.exe") `
    -ArgumentList @("/quiet", "InstallAllUsers=1", "TargetDir=$pythonRoot", "PrependPath=1", "Include_launcher=1", "Include_pip=1", "Include_test=0")
}
Add-MachinePath $pythonRoot
Add-MachinePath (Join-Path $pythonRoot "Scripts")

if (-not (Get-Command azd -ErrorAction SilentlyContinue)) {
  Write-Host "Installing Azure Developer CLI"
  Invoke-Expression "& { $(Invoke-RestMethod https://aka.ms/install-azd.ps1) }"
}
Add-MachinePath "$env:ProgramFiles\Azure Developer CLI"
Add-MachinePath "$env:LOCALAPPDATA\Programs\Azure Dev CLI"

Write-Host ""
Write-Host "Installed tool versions:"

& "C:\Program Files\PowerShell\7\pwsh.exe" -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'

if (Get-Command az -ErrorAction SilentlyContinue) {
  az version --query '"azure-cli"' -o tsv
}
else {
  Write-Warning "Azure CLI command 'az' was not found after install."
}

if (Get-Command azd -ErrorAction SilentlyContinue) {
  azd version
}
else {
  Write-Warning "Azure Developer CLI command 'azd' was not found after install."
}

if (Get-Command git -ErrorAction SilentlyContinue) {
  git --version
}
else {
  Write-Warning "Git command 'git' was not found after install."
}

if (Test-Path $pythonExe) {
  & $pythonExe --version
}
else {
  Write-Warning "Python executable was not found at $pythonExe after install."
}
