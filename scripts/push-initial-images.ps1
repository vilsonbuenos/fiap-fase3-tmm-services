param(
  [Parameter(Mandatory = $true)]
  [string]$AccountId,

  [string]$Region = "us-east-2",
  [string]$Tag = "v0.0.0-init"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$registry = "$AccountId.dkr.ecr.$Region.amazonaws.com"
$services = @("auth-service", "flag-service", "targeting-service", "evaluation-service", "analytics-service")

aws ecr get-login-password --region $Region | docker login --username AWS --password-stdin $registry

foreach ($svc in $services) {
  Write-Host "=== Build $svc ==="
  docker build -t "togglemaster/${svc}:${Tag}" (Join-Path $root $svc)
  docker tag "togglemaster/${svc}:${Tag}" "$registry/togglemaster/${svc}:${Tag}"
  docker push "$registry/togglemaster/${svc}:${Tag}"
}

Write-Host "Imagens iniciais publicadas com a tag $Tag"
