$ErrorActionPreference = "Stop"
$req = [guid]::NewGuid().ToString()
$uri = ${env:URL}
if ([string]::IsNullOrWhiteSpace($uri)) { $uri = "http://localhost:3000/up" }
$resp = Invoke-WebRequest -Headers @{ "X-Request-ID" = $req } -Uri $uri -UseBasicParsing
if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 300 -and $resp.Content -match "ok") {
  Write-Host "smoke ok ($req)"
  exit 0
} else {
  Write-Host "smoke failed ($req)"
  exit 1
}
$ErrorActionPreference = "SilentlyContinue"
bin\rails db:drop db:create db:migrate
docker compose down -v
