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
# MIIdnQYJKoZIhvcNAQcCoIIdjjCCHYoCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUeHnK+IOn+Nk9YMvH+kBc5BCq
# uraggheGMIIESDCCArCgAwIBAgIQLVS+Lgx5x4dK1qeO0Fy3mDANBgkqhkiG9w0B
# AQsFADAiMSAwHgYDVQQDDBdSZXBhcm8gSW50ZXJuYWwgUm9vdCBDQTAeFw0yNjA3
# MjgyMDExMTBaFw0yOTA3MjgyMDIxMTBaMCcxJTAjBgNVBAMMHFJlcGFybyBJbnRl
# cm5hbCBDb2RlIFNpZ25pbmcwggGiMA0GCSqGSIb3DQEBAQUAA4IBjwAwggGKAoIB
# gQDDefiKuvFGkLlODev1GfWDfAxuEbPvNqXeNlMfjo8Z07gDQZSnvPP/G2P8ighP
# d+yL7BbEaVhVk86jZfxfSLcwvfybjEF0PljYBCAWOb8k7Kin9qxfNvv76jfsC0dx
# 5C9U7fSa4Ghp9BrkUsK1iC1/LWiyA0RB/O8mljdiTPk2jXJqycQ9m/E90klKtrhr
# 1sSnBKt6qYjOyfhRF249uhtlXYq4wCPmmN3ljHMWRvF71Fm9ieqlhI+rz/Iiq0zt
# 2R9vFBxrlvwsbXOzwzT6QIHPtRU8ecHYlT48KF8BQeWsFmUTI68DDodQW1g8xWcC
# x9S1F/zSptgJdl+O8gOwfHVzRME4Y4j6iKqla4w15Gw0tgLpCDf6z6/LgWQv0wSc
# +ZUT/SZy8mu/sJBMWzSsoayV1lqeK8VD020YJI17FOgVfNNniv6jmlLgTvhXXc+1
# GxE+8JXtuJMqq2mAVwBoM9ab43Cemka5hrIL2/Y+ncIZtY0efPh46a4xFsxqXiz1
# gc0CAwEAAaN1MHMwDgYDVR0PAQH/BAQDAgeAMAwGA1UdEwEB/wQCMAAwEwYDVR0l
# BAwwCgYIKwYBBQUHAwMwHwYDVR0jBBgwFoAUte3wiJmwACggzC2luxXB2qrt3Q4w
# HQYDVR0OBBYEFGp8NVPXw0srUF6nNOdyth14axsmMA0GCSqGSIb3DQEBCwUAA4IB
# gQCm/9nG7ANlqpgGGDJZFI1jpoMGVOooAxJt/1oDnGi/LLnKujuQrDQuR/7E6y4t
# l2SZEX4QTsNhtT0mtZDOt+eZM7ndR/Ble1nqM8ubaxMdmOQVekq7dWQWRdooeys+
# gplzIPzijrgkIxgA4532r3a/hokcSx4E+CQV27a1+nkfNchekYjuOh2NTKfiffXo
# YAOHPMwLOZZjDcAQpXHGpH10L/ZifvKoM+svU1nrfOXiW2Hp6WEKHxJSZW5EhJyH
# aNr7iA2OjbCvFxhbCrW+R+3LwEfZV10UW03hQ08ky74v2UVR9u23EoNnGpMHXgMw
# EkbwRGcs6Fl1/4l+eqiip+Vm2zT1rdBAoED7bl1NtTwoNX8K1ZASIu2rogoglYCf
# eP12qW6fcvCCihTNYILAOujdDcRic3+Rlu4B7TWzszvgglB+Jih7jU2qhRB+IZfU
# zgYeIJ8MCuS8EjVKZx7MHgGYbfcvzn9MkIY4XBUv0yCK8nFtR8nPShfaP8Zurj0y
# WJ0wggWNMIIEdaADAgECAhAOmxiO+dAt5+/bUOIIQBhaMA0GCSqGSIb3DQEBDAUA
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
# iC7POGT75qaL6vdCvHlshtjdNXOCIUjsarfNZzGCBYEwggV9AgEBMDYwIjEgMB4G
# A1UEAwwXUmVwYXJvIEludGVybmFsIFJvb3QgQ0ECEC1Uvi4MeceHStanjtBct5gw
# CQYFKw4DAhoFAKB4MBgGCisGAQQBgjcCAQwxCjAIoAKAAKECgAAwGQYJKoZIhvcN
# AQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUw
# IwYJKoZIhvcNAQkEMRYEFFkSPQqSR/gzD6+DYRdg8h9m06ikMA0GCSqGSIb3DQEB
# AQUABIIBgLqFyo61Y37SwxMp+xX3fMiqsohdTQwjCrb9izfkR7mX+ojFVLM0jCVv
# gBo9opyf2/f5NKTisd8w/+qfKOEuBlqsALVbL8kyhyZ66NBCsoXMC/tGpImm1p3e
# VtP9NPAU1rMwUBYl1GL8XQiVnpvezJdJHjOiS1Z8l+5kqeACGbhPQ7T0rs8VFYUf
# pwvkGw4E/2z19OCUTRcB2OIGvG+mZHuRVsfojLai2P0ZN2wgJZ2Qkf4QSn5ytzgQ
# xuFpk65pdJ+4VLOGpcWyxKoKK4JcZa6qX2kVl3UlRGl4iGrprZ49IrkRX7JKfKP3
# AdPE7+5wF8RQ7Kg+pbSCLUspd8YddWmFIWA8tEUwj50G8L9XJ7/HDQNwhaCppGSR
# OeHyy9Q9EGdkPv2aenXjzb7vEweYD0jbQSdyBy9/SxfMgJMblQg8/cdOxLzKe/lU
# BpOMgoeFSsX3GpeZZlxLCeVy2bHoRCRxD+CXd5g/mb5yJGBKKpsi8i1vrSK/D3CV
# TudDptcK4aGCAyYwggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNV
# BAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNl
# cnQgVHJ1c3RlZCBHNCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBD
# QTECEAqA7xhLjfEFgtHEdqeVdGgwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0B
# CQMxCwYJKoZIhvcNAQcBMBwGCSqGSIb3DQEJBTEPFw0yNjA3MjkwMDE5NTRaMC8G
# CSqGSIb3DQEJBDEiBCCTbiKrMvnH9GjmFz2doM5aNhNVxvvIP+HHQyCmNfzpiTAN
# BgkqhkiG9w0BAQEFAASCAgAM65AAJ5ML4j6nFvkZ9QBUkngDyQD30lsN1Q3cu01A
# q+gKzcbCkWVMt+Qq1QsJHB0YKcXjy4dczFEGRA3D8m8QVb2mGPGl8nwpe5igWqMo
# f6vwzzegRtkTwWNhILhEelh5ChJPegF+vLjt1bZRpSHHyyIc1oMxJ980nALaz1rt
# I+iUCGdLRFvUQPq0WZTspaHh3+IBa+qxaSjUT6BQo1JeuKNGbrC9c9y364NCqbH4
# hqSgCRKrrRRBe2ImkOGYJhBuzK+RXqIDQQ6/RYdtiHxV+uXfk4TqvtMd/AS00xev
# Yn/GHOSu/AmXkrShtSByN4OXoRzXvHc2cxDp3TJ1YBy5gWBGAruyXr9LSRYvy7J5
# Gm6TmL87GiIMac4DzqdtRU0G5f3r7fG5WmVRD6By5buekTitmf0R1cqV4vV68aPK
# IqGbZEuRxgRgltjmsEWUnoAphX5xwSVGuJBOkaJ/edu1QJ2W421soLS3FJPG6G/l
# 5ankPUcldWSVjiZhpvhYAhs8SJIuR7esNb/HpN7H76tR83vcwWTJqEB75Ga8m2S7
# dc6um1QcLlMvuvQ5UMSVhsUH4EQiaQPPyDkQKSnPHd1CLuWFKo+Iqfra8BZ88WYQ
# vLJI1l40UvMSHuULlFASFKZ0BMaKGu00NCO0qaHQ7dszPQlB5TCJzvC4FN+5yerx
# vQ==
# SIG # End signature block
