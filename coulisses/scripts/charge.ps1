#Requires -Version 7.3
# Carte 04 : simule la salle qui utilise l'app en même temps, pour épuiser le quota du modèle.
# Avant la parade : des erreurs en cascade (429 de Foundry, ou 5xx si l'app ne les gère pas).
# Après la parade (modèle de repli) : que des 200.
#
# usage : ./coulisses/scripts/charge.ps1 $URL [-Requests 60] [-Concurrency 10] [-Question "..."]
param(
    [Parameter(Mandatory, Position = 0, HelpMessage = "URL de l'app, ex. https://app-devday-xxxxxx.azurewebsites.net")]
    [string]$Url,
    [int]$Requests = 60,
    # 10 en parallèle : sature le modèle principal (capacité 10), pas le repli (capacité 50). À régler au dry-run.
    [int]$Concurrency = 10,
    [string]$Question = 'Résume le programme du DevDay en trois phrases.'
)

$ErrorActionPreference = 'Stop'
$endpoint = "$($Url.TrimEnd('/'))/api/chat"
$body = @{ question = $Question } | ConvertTo-Json -Compress

Write-Host "$Requests requêtes vers $endpoint, $Concurrency en parallèle…`n"
$sw = [Diagnostics.Stopwatch]::StartNew()

$results = 1..$Requests | ForEach-Object -ThrottleLimit $Concurrency -Parallel {
    $t = [Diagnostics.Stopwatch]::StartNew()
    try {
        $r = Invoke-WebRequest -Method Post -Uri $using:endpoint -Body $using:body `
            -ContentType 'application/json; charset=utf-8' -SkipHttpErrorCheck -TimeoutSec 60
        $code = [int]$r.StatusCode
    }
    catch { $code = 0 }    # pas de réponse : délai dépassé, connexion refusée…
    $t.Stop()
    $ok = $code -eq 200
    Write-Host -NoNewline ($ok ? '.' : 'x') -ForegroundColor ($ok ? 'Green' : 'Red')
    [pscustomobject]@{ Code = $code; Ms = $t.ElapsedMilliseconds }
}
$sw.Stop()

# --- Bilan
Write-Host "`n"
$results | Group-Object Code | Sort-Object Name | ForEach-Object {
    $label = switch ([int]$_.Name) {
        200 { 'OK' }
        429 { 'trop de requêtes (quota ou limite par spectateur)' }
        0 { 'pas de réponse' }
        { $_ -ge 500 } { "erreur serveur (souvent un 429 de Foundry mal géré par l'app)" }
        default { '' }
    }
    $color = $_.Name -eq '200' ? 'Green' : 'Red'
    Write-Host ("  {0,4} × {1,-3} {2}" -f $_.Count, ($_.Name -eq '0' ? '---' : $_.Name), $label) -ForegroundColor $color
}
$ok = @($results | Where-Object Code -eq 200)
$p50 = if ($ok) { ($ok.Ms | Sort-Object)[[int][math]::Floor($ok.Count / 2)] } else { '-' }
Write-Host ("`n  {0:P0} de succès · médiane {1} ms (réponses 200) · {2:N1} s au total" -f ($ok.Count / $Requests), $p50, $sw.Elapsed.TotalSeconds)
