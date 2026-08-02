<#
.SYNOPSIS
Read-only NinjaOne diagnostic for Reparo runtime deployment.

.DESCRIPTION
Run as SYSTEM with no arguments. Reports the actual ProgramData runtime, logs,
PATH entries, process context, and Ninja custom-field setter availability. It makes
no changes and returns nonzero only when the expected runtime is missing.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Write-DiagnosticValue {
    param(
        [string]$Name,
        [object]$Value
    )

    $text = if ($null -eq $Value) { '<null>' } else { [string]$Value }
    Write-Host ("{0}: {1}" -f $Name, $text)
}

$installRoot = Join-Path $env:ProgramData 'Reparo'
$runtimePath = Join-Path $installRoot 'Reparo.ps1'
$logRoot = Join-Path $installRoot 'Logs'
$shimPath = Join-Path $installRoot 'bin\reparo.cmd'

Write-Host '=== Ninja Reparo Runtime Diagnostic ==='
Write-DiagnosticValue -Name 'Computer' -Value $env:COMPUTERNAME
Write-DiagnosticValue -Name 'Identity' -Value ([Security.Principal.WindowsIdentity]::GetCurrent().Name)
Write-DiagnosticValue -Name 'Working directory' -Value (Get-Location).Path
Write-DiagnosticValue -Name 'ProgramData' -Value $env:ProgramData
Write-DiagnosticValue -Name 'Install root' -Value $installRoot
Write-DiagnosticValue -Name 'Install root exists' -Value (Test-Path -LiteralPath $installRoot -PathType Container)
Write-DiagnosticValue -Name 'Runtime exists' -Value (Test-Path -LiteralPath $runtimePath -PathType Leaf)
Write-DiagnosticValue -Name 'Shim exists' -Value (Test-Path -LiteralPath $shimPath -PathType Leaf)
Write-DiagnosticValue -Name 'Log directory exists' -Value (Test-Path -LiteralPath $logRoot -PathType Container)

if (Test-Path -LiteralPath $runtimePath -PathType Leaf) {
    $versionMatch = Select-String -LiteralPath $runtimePath -Pattern "ReparoVersion\s*=\s*'([^']+)'" | Select-Object -First 1
    $version = if ($versionMatch) { $versionMatch.Matches[0].Groups[1].Value } else { 'Installed (version unreadable)' }
    Write-DiagnosticValue -Name 'Runtime version' -Value $version
    Write-DiagnosticValue -Name 'Runtime SHA-256' -Value ((Get-FileHash -LiteralPath $runtimePath -Algorithm SHA256).Hash)
    $signature = Get-AuthenticodeSignature -FilePath $runtimePath
    Write-DiagnosticValue -Name 'Runtime signature status' -Value $signature.Status
    Write-DiagnosticValue -Name 'Runtime signer thumbprint' -Value $(if ($signature.SignerCertificate) { $signature.SignerCertificate.Thumbprint } else { '<none>' })
}

if (Test-Path -LiteralPath $logRoot -PathType Container) {
    $logs = @(Get-ChildItem -LiteralPath $logRoot -File -Filter 'reparo_*.log' -ErrorAction Stop | Sort-Object LastWriteTime -Descending)
    Write-DiagnosticValue -Name 'Reparo log count' -Value $logs.Count
    foreach ($log in @($logs | Select-Object -First 5)) {
        Write-Host ("Recent log: {0} ({1:u})" -f $log.FullName, $log.LastWriteTime)
    }
}

foreach ($scope in @('Machine', 'User', 'Process')) {
    $path = if ($scope -eq 'Process') { $env:Path } else { [Environment]::GetEnvironmentVariable('Path', $scope) }
    $hasReparoBin = [bool](@($path -split ';' | Where-Object { $_ -ieq (Join-Path $installRoot 'bin') }))
    Write-DiagnosticValue -Name "$scope PATH contains Reparo bin" -Value $hasReparoBin
}

$propertySetter = Get-Command -Name Ninja-Property-Set -ErrorAction SilentlyContinue
Write-DiagnosticValue -Name 'Ninja-Property-Set available' -Value ([bool]$propertySetter)
if ($propertySetter) {
    Write-DiagnosticValue -Name 'Ninja-Property-Set command type' -Value $propertySetter.CommandType
    Write-DiagnosticValue -Name 'Ninja-Property-Set source' -Value $propertySetter.Source
}

if (-not (Test-Path -LiteralPath $runtimePath -PathType Leaf)) {
    Write-Error "Reparo runtime is missing: $runtimePath"
    exit 1
}

Write-Host 'Diagnostic complete: Reparo runtime is present.'
exit 0

# SIG # Begin signature block
# MIIfFwYJKoZIhvcNAQcCoIIfCDCCHwQCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU5GhEQ8h5KPDsliH9y1Ye4hsr
# gfigghh2MIIFODCCAyCgAwIBAgIQRAnY3+h+m7ZGhdt+bpKDhTANBgkqhkiG9w0B
# AQsFADAsMSowKAYDVQQDDCFUaGUgVGVjaG5vbG9naXN0IEludGVybmFsIFJvb3Qg
# Q0EwHhcNMjYwODAyMDYzNTIyWhcNMzYwODAxMDY0NTIwWjAbMRkwFwYDVQQDDBBU
# aGUgVGVjaG5vbG9naXN0MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA
# lNNhdFAcHc7pXrTpI9GZ4wGRATk5nCBjKBB/M9WKokYnDIr073y59dRUaXETnzl/
# kKdorprHwvmSX8k6StiVCl8zAEi94w7CLYB5rqMXFmKm3VFX6s6X615gnoEL2sZX
# Ff9Nof+zIH+2TqVof7kYnSjUcpcDabadRxg4tpEfONLWKtRmgGMFI/AgfJKZrQgG
# oGoSZK8ba+Oo+HsrrsPAmgJCbSNInBn9cuOCqbyGenaFA+MYzUQ41GsFdlrWKP/k
# UIye+0OqsABabOq2y18k9zTfivgF1Vq5/raUDwjMDQPT/FwX7+vESWPdiDBCjlxw
# udll03kF1dfz9cF9zOV6UAWce8nxWl/jtaix4dIX+SyEPjKtOPMm7SYBERVWeTYG
# oGFOzyWNnxKm9YQ+2k7eYHEmlOdWI8KvcIXZwTG/o/XKOuh1CaV2Hbhfw4QFg4FU
# 32JjNYMid7hJBhAtLf5yCMGO0VSdcVyJrC+xQKR7UGobwFqGTRImIp3V9QffGxXh
# we+HU5qNzkhzA9mrg7XKgCxXbyz1HmwOH1+4v+cHB1AD/d91vnBnydg4Az2IDmC9
# AlmJwMaEMdkhpHzutSmQ0wbktu/I/3d6Ww2M7KKWHdQeqiMEFR/tZ6W5yt8oYipo
# LcTGbl87MdBYykI2iF8yeyCIBlAoozk0/FnBQqVsEZUCAwEAAaNnMGUwDgYDVR0P
# AQH/BAQDAgeAMBMGA1UdJQQMMAoGCCsGAQUFBwMDMB8GA1UdIwQYMBaAFC2/rogq
# j3D9/NSFjj81LqMTzs4rMB0GA1UdDgQWBBRXUJHYAZIY2TOUNjqBVrsf0xlVjjAN
# BgkqhkiG9w0BAQsFAAOCAgEABDrlrZlG0CHzdeCegE53n1s1U5xebwC77FdXTM9I
# 4vKRrtROYog0HssZ4JFTXXgAuoIv7SwpyNQUf7HtxSzp99qLnMJ7/uusclQOEGb0
# 8hWGCSp+KT8Jw5ltKUyygYdjAs5epHxAT6EA4XNbJ5DCox+ZyFhHo7XjoFGEbZGo
# XWcUhpVYl/XP4+7iUa+fVRaETHg/uJYtdoCMi5bdy5lcubIFwb9d1VI3JwbuhYMa
# xh8+yWMeRz2IRcVt/Xw4DxlC12HOqico8kDY86l8GGH8VSPvwW1SLwepf3/iVr8/
# bA5QiTb38eMOkYcFrXcw3FNV2MYuVXB1CYRCHog60cJ52u9iZBVKnZjiHtc4wnWW
# QcaLjKjD/4ZuyK0yw3TjXdGwO9+rEpWLFjsUSkVBltH7/Ont1/9Tvjer0poauyxq
# zOu4dZmaK6DU9jAygU9UhTiT2PP0ji8sec9XGDkC/P8YcihrDkERKrqQAt4r3Q9k
# eEAq92NccsmuC9/zwt2/jpJCt566Tg9U1Yohy/qdwVbzNIgHyuIOtfPEtYlhleur
# GR4/fkb1Oqqwome7AlEy6L/1IHKXn/A/cScN0BnswLkg8yVhsoZK++0KXAHZHFjW
# pv9PV0pPFkyS0Zh1XPoRroJT0ENsS+SvHQube2rJc+WPjmPV2CSMNqjFJ3dIlz8X
# tvMwggWNMIIEdaADAgECAhAOmxiO+dAt5+/bUOIIQBhaMA0GCSqGSIb3DQEBDAUA
# MGUxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsT
# EHd3dy5kaWdpY2VydC5jb20xJDAiBgNVBAMTG0RpZ2lDZXJ0IEFzc3VyZWQgSUQg
# Um9vdCBDQTAeFw0yMjA4MDEwMDAwMDBaFw0zMTExMDkyMzU5NTlaMGIxCzAJBgNV
# BAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdp
# Y2VydC5jb20xITAfBgNVBAMTGERpZ2lDZXJ0IFRydXN0ZWQgUm9vdCBHNDCCAiIw
# DQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAL/mkHNo3rvkXUo8MCIwaTPswqcl
# LskhPfKK2FnC4SmnPVirdprNrnsbhA3EMB/zG6Q4FutWxpdtHauyefLKEdLkX9YF
# PFIPUh/GnhWlfr6fqVcWWVVyr2iTcMKyunWZanMylNEQRBAu34LzB4TmdDttceIt
# DBvuINXJIB1jKS3O7F5OyJP4IWGbNOsFxl7sWxq868nPzaw0QF+xembud8hIqGZX
# V59UWI4MK7dPpzDZVu7Ke13jrclPXuU15zHL2pNe3I6PgNq2kZhAkHnDeMe2scS1
# ahg4AxCN2NQ3pC4FfYj1gj4QkXCrVYJBMtfbBHMqbpEBfCFM1LyuGwN1XXhm2Tox
# RJozQL8I11pJpMLmqaBn3aQnvKFPObURWBf3JFxGj2T3wWmIdph2PVldQnaHiZdp
# ekjw4KISG2aadMreSx7nDmOu5tTvkpI6nj3cAORFJYm2mkQZK37AlLTSYW3rM9nF
# 30sEAMx9HJXDj/chsrIRt7t/8tWMcCxBYKqxYxhElRp2Yn72gLD76GSmM9GJB+G9
# t+ZDpBi4pncB4Q+UDCEdslQpJYls5Q5SUUd0viastkF13nqsX40/ybzTQRESW+UQ
# UOsxxcpyFiIJ33xMdT9j7CFfxCBRa2+xq4aLT8LWRV+dIPyhHsXAj6KxfgommfXk
# aS+YHS312amyHeUbAgMBAAGjggE6MIIBNjAPBgNVHRMBAf8EBTADAQH/MB0GA1Ud
# DgQWBBTs1+OC0nFdZEzfLmc/57qYrhwPTzAfBgNVHSMEGDAWgBRF66Kv9JLLgjEt
# UYunpyGd823IDzAOBgNVHQ8BAf8EBAMCAYYweQYIKwYBBQUHAQEEbTBrMCQGCCsG
# AQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wQwYIKwYBBQUHMAKGN2h0
# dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RD
# QS5jcnQwRQYDVR0fBD4wPDA6oDigNoY0aHR0cDovL2NybDMuZGlnaWNlcnQuY29t
# L0RpZ2lDZXJ0QXNzdXJlZElEUm9vdENBLmNybDARBgNVHSAECjAIMAYGBFUdIAAw
# DQYJKoZIhvcNAQEMBQADggEBAHCgv0NcVec4X6CjdBs9thbX979XB72arKGHLOyF
# XqkauyL4hxppVCLtpIh3bb0aFPQTSnovLbc47/T/gLn4offyct4kvFIDyE7QKt76
# LVbP+fT3rDB6mouyXtTP0UNEm0Mh65ZyoUi0mcudT6cGAxN3J0TU53/oWajwvy8L
# punyNDzs9wPHh6jSTEAZNUZqaVSwuKFWjuyk1T3osdz9HNj0d1pcVIxv76FQPfx2
# CWiEn2/K2yCNNWAcAgPLILCsWKAOQGPFmCLBsln1VWvPJ6tsds5vIy30fnFqI2si
# /xK4VC0nftg62fC2h5b9W9FcrBjDTZ9ztwGpn1eqXijiuZQwgga0MIIEnKADAgEC
# AhANx6xXBf8hmS5AQyIMOkmGMA0GCSqGSIb3DQEBCwUAMGIxCzAJBgNVBAYTAlVT
# MRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5j
# b20xITAfBgNVBAMTGERpZ2lDZXJ0IFRydXN0ZWQgUm9vdCBHNDAeFw0yNTA1MDcw
# MDAwMDBaFw0zODAxMTQyMzU5NTlaMGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5E
# aWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBUaW1l
# U3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTEwggIiMA0GCSqGSIb3DQEB
# AQUAA4ICDwAwggIKAoICAQC0eDHTCphBcr48RsAcrHXbo0ZodLRRF51NrY0NlLWZ
# loMsVO1DahGPNRcybEKq+RuwOnPhof6pvF4uGjwjqNjfEvUi6wuim5bap+0lgloM
# 2zX4kftn5B1IpYzTqpyFQ/4Bt0mAxAHeHYNnQxqXmRinvuNgxVBdJkf77S2uPoCj
# 7GH8BLuxBG5AvftBdsOECS1UkxBvMgEdgkFiDNYiOTx4OtiFcMSkqTtF2hfQz3zQ
# Sku2Ws3IfDReb6e3mmdglTcaarps0wjUjsZvkgFkriK9tUKJm/s80FiocSk1VYLZ
# lDwFt+cVFBURJg6zMUjZa/zbCclF83bRVFLeGkuAhHiGPMvSGmhgaTzVyhYn4p0+
# 8y9oHRaQT/aofEnS5xLrfxnGpTXiUOeSLsJygoLPp66bkDX1ZlAeSpQl92QOMeRx
# ykvq6gbylsXQskBBBnGy3tW/AMOMCZIVNSaz7BX8VtYGqLt9MmeOreGPRdtBx3yG
# OP+rx3rKWDEJlIqLXvJWnY0v5ydPpOjL6s36czwzsucuoKs7Yk/ehb//Wx+5kMqI
# MRvUBDx6z1ev+7psNOdgJMoiwOrUG2ZdSoQbU2rMkpLiQ6bGRinZbI4OLu9BMIFm
# 1UUl9VnePs6BaaeEWvjJSjNm2qA+sdFUeEY0qVjPKOWug/G6X5uAiynM7Bu2ayBj
# UwIDAQABo4IBXTCCAVkwEgYDVR0TAQH/BAgwBgEB/wIBADAdBgNVHQ4EFgQU729T
# SunkBnx6yuKQVvYv1Ensy04wHwYDVR0jBBgwFoAU7NfjgtJxXWRM3y5nP+e6mK4c
# D08wDgYDVR0PAQH/BAQDAgGGMBMGA1UdJQQMMAoGCCsGAQUFBwMIMHcGCCsGAQUF
# BwEBBGswaTAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tMEEG
# CCsGAQUFBzAChjVodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRU
# cnVzdGVkUm9vdEc0LmNydDBDBgNVHR8EPDA6MDigNqA0hjJodHRwOi8vY3JsMy5k
# aWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkUm9vdEc0LmNybDAgBgNVHSAEGTAX
# MAgGBmeBDAEEAjALBglghkgBhv1sBwEwDQYJKoZIhvcNAQELBQADggIBABfO+xaA
# HP4HPRF2cTC9vgvItTSmf83Qh8WIGjB/T8ObXAZz8OjuhUxjaaFdleMM0lBryPTQ
# M2qEJPe36zwbSI/mS83afsl3YTj+IQhQE7jU/kXjjytJgnn0hvrV6hqWGd3rLAUt
# 6vJy9lMDPjTLxLgXf9r5nWMQwr8Myb9rEVKChHyfpzee5kH0F8HABBgr0UdqirZ7
# bowe9Vj2AIMD8liyrukZ2iA/wdG2th9y1IsA0QF8dTXqvcnTmpfeQh35k5zOCPmS
# Nq1UH410ANVko43+Cdmu4y81hjajV/gxdEkMx1NKU4uHQcKfZxAvBAKqMVuqte69
# M9J6A47OvgRaPs+2ykgcGV00TYr2Lr3ty9qIijanrUR3anzEwlvzZiiyfTPjLbnF
# RsjsYg39OlV8cipDoq7+qNNjqFzeGxcytL5TTLL4ZaoBdqbhOhZ3ZRDUphPvSRmM
# Thi0vw9vODRzW6AxnJll38F0cuJG7uEBYTptMSbhdhGQDpOXgpIUsWTjd6xpR6oa
# Qf/DJbg3s6KCLPAlZ66RzIg9sC+NJpud/v4+7RWsWCiKi9EOLLHfMR2ZyJ/+xhCx
# 9yHbxtl5TPau1j/1MIDpMPx0LckTetiSuEtQvLsNz3Qbp7wGWqbIiOWCnb5WqxL3
# /BAPvIXKUjPSxyZsq8WhbaM2tszWkPZPubdcMIIG7TCCBNWgAwIBAgIQCoDvGEuN
# 8QWC0cR2p5V0aDANBgkqhkiG9w0BAQsFADBpMQswCQYDVQQGEwJVUzEXMBUGA1UE
# ChMORGlnaUNlcnQsIEluYy4xQTA/BgNVBAMTOERpZ2lDZXJ0IFRydXN0ZWQgRzQg
# VGltZVN0YW1waW5nIFJTQTQwOTYgU0hBMjU2IDIwMjUgQ0ExMB4XDTI1MDYwNDAw
# MDAwMFoXDTM2MDkwMzIzNTk1OVowYzELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRp
# Z2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBTSEEyNTYgUlNBNDA5NiBU
# aW1lc3RhbXAgUmVzcG9uZGVyIDIwMjUgMTCCAiIwDQYJKoZIhvcNAQEBBQADggIP
# ADCCAgoCggIBANBGrC0Sxp7Q6q5gVrMrV7pvUf+GcAoB38o3zBlCMGMyqJnfFNZx
# +wvA69HFTBdwbHwBSOeLpvPnZ8ZN+vo8dE2/pPvOx/Vj8TchTySA2R4QKpVD7dvN
# Zh6wW2R6kSu9RJt/4QhguSssp3qome7MrxVyfQO9sMx6ZAWjFDYOzDi8SOhPUWlL
# nh00Cll8pjrUcCV3K3E0zz09ldQ//nBZZREr4h/GI6Dxb2UoyrN0ijtUDVHRXdmn
# cOOMA3CoB/iUSROUINDT98oksouTMYFOnHoRh6+86Ltc5zjPKHW5KqCvpSduSwhw
# UmotuQhcg9tw2YD3w6ySSSu+3qU8DD+nigNJFmt6LAHvH3KSuNLoZLc1Hf2JNMVL
# 4Q1OpbybpMe46YceNA0LfNsnqcnpJeItK/DhKbPxTTuGoX7wJNdoRORVbPR1VVnD
# uSeHVZlc4seAO+6d2sC26/PQPdP51ho1zBp+xUIZkpSFA8vWdoUoHLWnqWU3dCCy
# FG1roSrgHjSHlq8xymLnjCbSLZ49kPmk8iyyizNDIXj//cOgrY7rlRyTlaCCfw7a
# SUROwnu7zER6EaJ+AliL7ojTdS5PWPsWeupWs7NpChUk555K096V1hE0yZIXe+gi
# AwW00aHzrDchIc2bQhpp0IoKRR7YufAkprxMiXAJQ1XCmnCfgPf8+3mnAgMBAAGj
# ggGVMIIBkTAMBgNVHRMBAf8EAjAAMB0GA1UdDgQWBBTkO/zyMe39/dfzkXFjGVBD
# z2GM6DAfBgNVHSMEGDAWgBTvb1NK6eQGfHrK4pBW9i/USezLTjAOBgNVHQ8BAf8E
# BAMCB4AwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwgZUGCCsGAQUFBwEBBIGIMIGF
# MCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wXQYIKwYBBQUH
# MAKGUWh0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRH
# NFRpbWVTdGFtcGluZ1JTQTQwOTZTSEEyNTYyMDI1Q0ExLmNydDBfBgNVHR8EWDBW
# MFSgUqBQhk5odHRwOi8vY3JsMy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVk
# RzRUaW1lU3RhbXBpbmdSU0E0MDk2U0hBMjU2MjAyNUNBMS5jcmwwIAYDVR0gBBkw
# FzAIBgZngQwBBAIwCwYJYIZIAYb9bAcBMA0GCSqGSIb3DQEBCwUAA4ICAQBlKq3x
# HCcEua5gQezRCESeY0ByIfjk9iJP2zWLpQq1b4URGnwWBdEZD9gBq9fNaNmFj6Eh
# 8/YmRDfxT7C0k8FUFqNh+tshgb4O6Lgjg8K8elC4+oWCqnU/ML9lFfim8/9yJmZS
# e2F8AQ/UdKFOtj7YMTmqPO9mzskgiC3QYIUP2S3HQvHG1FDu+WUqW4daIqToXFE/
# JQ/EABgfZXLWU0ziTN6R3ygQBHMUBaB5bdrPbF6MRYs03h4obEMnxYOX8VBRKe1u
# NnzQVTeLni2nHkX/QqvXnNb+YkDFkxUGtMTaiLR9wjxUxu2hECZpqyU1d0IbX6Wq
# 8/gVutDojBIFeRlqAcuEVT0cKsb+zJNEsuEB7O7/cuvTQasnM9AWcIQfVjnzrvwi
# CZ85EE8LUkqRhoS3Y50OHgaY7T/lwd6UArb+BOVAkg2oOvol/DJgddJ35XTxfUlQ
# +8Hggt8l2Yv7roancJIFcbojBcxlRcGG0LIhp6GvReQGgMgYxQbV1S3CrWqZzBt1
# R9xJgKf47CdxVRd/ndUlQ05oxYy2zRWVFjF7mcr4C34Mj3ocCVccAvlKV9jEnstr
# niLvUxxVZE/rptb7IRE2lskKPIJgbaP5t2nGj/ULLi49xTcBZU8atufk+EMF/cWu
# iC7POGT75qaL6vdCvHlshtjdNXOCIUjsarfNZzGCBgswggYHAgEBMEAwLDEqMCgG
# A1UEAwwhVGhlIFRlY2hub2xvZ2lzdCBJbnRlcm5hbCBSb290IENBAhBECdjf6H6b
# tkaF235ukoOFMAkGBSsOAwIaBQCgeDAYBgorBgEEAYI3AgEMMQowCKACgAChAoAA
# MBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgor
# BgEEAYI3AgEVMCMGCSqGSIb3DQEJBDEWBBQhRvGc2qEk87U4FG9HIBYQm4CIKTAN
# BgkqhkiG9w0BAQEFAASCAgAlf6eBxni5OKYsoFWRzEMjWdWtlGVEhdaEuCF6pP6d
# NFN8ses18O/uiP1FSYVrnCoNBzyMDPwg0wf6TAoHALskieQpdvn0w5npfUjq9Crm
# 24E0HEMsc6aJzlefU0FWg3eXutxKspEjR5qJuZRXzdyvi2Kc5Z+eN3qEdwaqOzmp
# nwKeoj600LmwrUiG9RS6gQs1vcDI6oHIPsvMV3Hp7pV4lL7FXpxVPWJm+ilhKPP7
# 8yGnNFlhRSikfQ7Va3B3ta5JGMt/E5+0x/adCOWbxVqZ7OYOqrUvztC6BXkmRkpV
# R7UFg+xJkW6YweqVCKpIztFPboZCJuSeyQ3OUpMIKPQRSWfs6lZUyeXQGOK8Cexi
# clwMjhvKnU1WbFHfuwus5QWAn6PO9O3XhZZy1u8TfLT/4FdheBYcTRTNJTlh99XR
# uYHzBlELtdEXUZiQwXylfiYZVh1D452g1lSJY3eMvko3B1KyQMFwj1wJz8p3ie6R
# T7uJOblQ1tMQ/wYwrK7LkJ3VMqGdCC2Y48p1IWntRdJ4KMOWylSXsLGznauvwg3Z
# n/wi45FSoq1zlrTXbgly9IxfZ3isX3v8Rf+C+mJ4IaEQs74Vdo75syLk2dBFHvw5
# 8gi9kcXdD+/8Y+Glavxb11RwSBnsq7vUwW4/fAR3lz8eEWqgZGJopEdKQsFK+J4J
# 5KGCAyYwggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVT
# MRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1
# c3RlZCBHNCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAqA
# 7xhLjfEFgtHEdqeVdGgwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJ
# KoZIhvcNAQcBMBwGCSqGSIb3DQEJBTEPFw0yNjA4MDIwNzIwMzhaMC8GCSqGSIb3
# DQEJBDEiBCDMEBb1e+KJPVAiniZCHbilYIDOWd/EGhjE3SIWrHARBjANBgkqhkiG
# 9w0BAQEFAASCAgAWookHfBiImbwhlrKcUyGDnkvCXP5gDmDEoonnXhgSiDgZXgYA
# FoaS9KbjgtwHCVB1M3kx7Lii4vWkPVDMiMdgd++Co1OY63er2RK+C2H1Ecu/jHTk
# j0l1GTr3XfG414D2XE4OvkRZYjdQMzNMcIOIP4J4xro9RcJznzdIA6oqX4oY61jf
# rsXjaIPSzSGf7HvWZCkA/2p6CQX5h5Kc4+bWjwqIMYavhvBUyRsN/c+qouVkksz4
# fPq/AIVLyVdYjknKj1jjmf/GEJ+vEG5rY9thL63cn4wgEZMnhya8flDhidraTveO
# TH+MVr5+xnMwWxD51euBa5B+Jo5buZtgGQjvtgrtkDy/D5bZ8Yk9GhmYi4IqsIdV
# LMXAyLsv9X2L9cArs3scmFvX5ycJ/DlKSJSTUmNFZ7IRBL99y4BBdBebktQEDPOH
# Lxpukr6+JzA34nxMPLJT+69bYlevgyybpJNCfAPsaUHyo/u1vuTTvgMjqcJ3fFuW
# Xf7wCEqZjfkM7leDeFtJJx9AcbD2dz9a3apiMsF9V0bfs/No19R5UfcMm0RhZsvI
# 1Wtv0Ow0cEI8bXHhTJodLOhkt4dteBacG6jah4UwGpIqHERFF6eQ1Jwo7InKZvlp
# HMEiD1UKgVGyZpJUEiry1iY8EJp7gehEbsFhhWY2W3erq7HNq2H0l5KK+Q==
# SIG # End signature block
