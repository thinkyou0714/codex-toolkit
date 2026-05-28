# SecretRedact.psm1 — PowerShell mirror of home/lib/secret_redact.py.
# 8-pattern redaction. Keep this byte-equivalent in behavior with the Python lib.
#
# Usage:
#   Import-Module ~/.codex/lib/SecretRedact.psm1
#   $clean = Invoke-RedactSecrets -Text "Authorization: Bearer abc..."
#
#   pwsh -File SecretRedact.psm1 -Selftest    # 8/8 offline check

$script:RedactPatterns = @(
    @{ Pattern = '(?i)(authorization\s*:\s*bearer\s+)[A-Za-z0-9._\-]+'; Replacement = '${1}***' },
    @{ Pattern = '(?i)(bearer\s+)[A-Za-z0-9._\-]{16,}';                  Replacement = '${1}***' },
    @{ Pattern = '\bsk-[A-Za-z0-9_\-]{16,}\b';                           Replacement = 'sk-***' },
    @{ Pattern = '\bxai-[A-Za-z0-9_\-]{16,}\b';                          Replacement = 'xai-***' },
    @{ Pattern = '(?i)(api[_\-]?key\s*[=:]\s*)[\"'']?[A-Za-z0-9_\-]{16,}[\"'']?'; Replacement = '${1}***' },
    @{ Pattern = '(?i)(x-api-key\s*[=:]\s*)[\"'']?[A-Za-z0-9_\-]{16,}[\"'']?';    Replacement = '${1}***' },
    @{ Pattern = '(?i)(token\s*[=:]\s*)[\"'']?[A-Za-z0-9_\-\.]{20,}[\"'']?';      Replacement = '${1}***' },
    @{ Pattern = '://[^@/\s]+:[^@/\s]+@';                                Replacement = '://***:***@' }
)

function Invoke-RedactSecrets {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true,ValueFromPipeline=$true)][AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $out = $Text
    foreach ($p in $script:RedactPatterns) {
        $out = [regex]::Replace($out, $p.Pattern, $p.Replacement)
    }
    return $out
}

function Invoke-Selftest {
    $cases = @(
        @{ In = 'Authorization: Bearer abcdef0123456789ABCDEF'; Want = 'Authorization: Bearer ***' },
        @{ In = 'plain Bearer abcdef0123456789ABCDEF end';      Want = 'plain Bearer *** end' },
        @{ In = 'key sk-abcdef0123456789ABCD end';              Want = 'key sk-*** end' },
        @{ In = 'tok xai-abcdef0123456789ABCD end';             Want = 'tok xai-*** end' },
        @{ In = 'config api_key=abcdef0123456789ABCD here';     Want = 'config api_key=*** here' },
        @{ In = 'header x-api-key: abcdef0123456789ABCD';       Want = 'header x-api-key: ***' },
        @{ In = 'env token=abcdef0123456789ABCDEFGH end';       Want = 'env token=*** end' },
        @{ In = 'url https://user:pass@example.com/x';          Want = 'url https://***:***@example.com/x' }
    )
    $fails = 0
    for ($i = 0; $i -lt $cases.Count; $i++) {
        $got = Invoke-RedactSecrets -Text $cases[$i].In
        if ($got -ne $cases[$i].Want) {
            $fails++
            Write-Error "FAIL[$($i+1)]: got=$got want=$($cases[$i].Want)"
        }
    }
    $pass = $cases.Count - $fails
    Write-Output "selftest: $pass/$($cases.Count) PASS"
    if ($fails -gt 0) { exit 1 } else { exit 0 }
}

Export-ModuleMember -Function Invoke-RedactSecrets, Invoke-Selftest

# Allow `pwsh -File SecretRedact.psm1 -Selftest` to invoke without an Import-Module ceremony.
if ($MyInvocation.InvocationName -ne '.' -and ($args -contains '-Selftest' -or $args -contains '--selftest')) {
    Invoke-Selftest
}
