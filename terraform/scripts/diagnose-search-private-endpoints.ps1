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

  try {
    $response = Invoke-WebRequest `
      -Uri "https://$name" `
      -UseBasicParsing `
      -TimeoutSec 20

    Write-Host "HTTPS status: $($response.StatusCode)"
  }
  catch {
    Write-Host "HTTPS error: $($_.Exception.Message)"
    if ($_.Exception.Response) {
      Write-Host "HTTPS status: $([int]$_.Exception.Response.StatusCode)"
    }
  }
}
