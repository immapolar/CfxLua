$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$cmd = Join-Path $scriptDir 'cfxlua.cmd'
& $cmd @args
exit $LASTEXITCODE
