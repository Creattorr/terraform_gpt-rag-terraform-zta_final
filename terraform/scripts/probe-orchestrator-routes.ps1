param(
  [Parameter(Mandatory = $true)]
  [string]$Fqdn
)

$ErrorActionPreference = "Continue"

$paths = @("/", "/orchestrator", "/orchestrator/", "/docs", "/openapi.json", "/health", "/healthz")

foreach ($path in $paths) {
  try {
    $response = Invoke-WebRequest -Uri "https://$Fqdn$path" -UseBasicParsing -TimeoutSec 30
    $content = ""
    if ($response.Content) {
      $content = $response.Content.Substring(0, [Math]::Min(160, $response.Content.Length))
    }
    Write-Host "$path -> HTTP $($response.StatusCode) $content"
  }
  catch {
    $statusCode = ""
    if ($_.Exception.Response) {
      $statusCode = [int]$_.Exception.Response.StatusCode
    }
    Write-Host "$path -> ERROR $statusCode $($_.Exception.Message)"
  }
}
