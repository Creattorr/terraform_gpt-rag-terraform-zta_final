param(
  [Parameter(Mandatory = $true)]
  [string[]]$Names
)

$ErrorActionPreference = "Continue"

foreach ($name in $Names) {
  Write-Host ""
  Write-Host "=== $name ==="

  Resolve-DnsName $name |
    Where-Object { $_.IPAddress -or $_.NameHost } |
    Format-Table Name, Type, IPAddress, NameHost -AutoSize

  Test-NetConnection $name -Port 443 |
    Select-Object ComputerName, RemoteAddress, RemotePort, TcpTestSucceeded |
    Format-List
}
