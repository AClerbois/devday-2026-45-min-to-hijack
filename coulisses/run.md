# Le jeu, carte par carte

Ce que l'on tape pendant la session. Pour la mise en place, voir `setup.md`.

---

## Avant d'entrer en scène

```powershell
cd devday-chaos
git switch main && git pull
gh run list -L 1                 # le dernier run est vert
az account show -o table         # la bonne souscription
```

Ouvrir dans des onglets : l'app, le repo GitHub (onglet Actions), le portail Foundry, un terminal.

Garder sous la main ces variables, utilisées par toutes les cartes :

```powershell
$LOCATION = gh variable get LOCATION 2>$null
if (-not $LOCATION) { $LOCATION = 'swedencentral' }   # même repli que le pipeline
$RG  = "rg-devday-chaos-$LOCATION"
$APP = az webapp list -g $RG --query "[0].name" -o tsv
$FDY = az cognitiveservices account list -g $RG --query "[0].name" -o tsv
if ($APP) { $URL = "https://$(az webapp show -g $RG -n $APP --query defaultHostName -o tsv)" } else { Write-Warning "Aucune Web App dans $RG : le dernier déploiement est-il allé au bout ?" }
```

> Après la carte 03, la région change : **relancer ce bloc**.

---

## La boucle de chaque carte

1. **Tirage** (1 min) : un spectateur tire et lit la carte. Projeter sa fiche (diapo masquée).
2. **Négociation et vote** (1 min 30) : à trois, puis main levée « Qui a raison ? ».
3. **Parade** (5 min) : on **écrit** une ligne de plus dans `infra/main.bicepparam` (le fichier du build ne contient aucune parade ; le code des parades est déjà livré, éteint), puis :

   ```powershell
   git commit -am "carte 0X" && git push && gh run watch
   ```

   Pendant le déploiement, celui qui n'a pas le clavier explique ce qui se passe dans Azure.
4. **Preuve et leçon** (30 s) : montrer que ça marche, dire la phrase de la fiche.

---

## L'app et le build (2'–8')

La plateforme a été déployée **la veille**, clé piège comprise : on montre le repo, `main.bicepparam`, le dernier run vert et l'app en ligne (bandeau `Auth : clé API`), puis le QR code. Adrien assume la clé : « Hier soir, l'identité managée me renvoyait des 401. Pas le temps d'attendre, j'ai mis la clé. »

Afficher **le QR code de la Suède** (diapo 7 du deck) : la salle peut commencer à utiliser l'app. Juste avant d'entrer en scène, ouvrir l'app une fois pour la réveiller.

---

## Carte 01 · La clé API a fuité sur GitHub

**Un seul push**, pour tenir dans les 5 minutes : deux pushs feraient deux déploiements, soit environ 8 minutes.

**1. Basculer l'app sur son identité et interdire les clés**, dans le même commit. Ajouter dans `infra/main.bicepparam` :

```bicep
param useManagedIdentity = true
param disableLocalAuth = true
```

Et retirer la clé de `src/appsettings.json` (`"Key": ""`) : plus aucun secret dans le code.

```powershell
git commit -am "carte 01 : identité managée, plus aucune clé" && git push && gh run watch
```

> Foundry est mis à jour avant la Web App : l'app renvoie des erreurs **environ une minute**, le temps que le code et ses réglages suivent. L'annoncer plutôt que le subir : « C'est le prix de la correction en urgence. Prévue dès le départ, elle n'aurait rien coûté. »

**2. Couper l'hémorragie**, pendant le déploiement, pendant que Mario commente :

```powershell
az cognitiveservices account keys regenerate -g $RG -n $FDY --key-name key1
az cognitiveservices account keys regenerate -g $RG -n $FDY --key-name key2
```

**Preuve** : le bandeau passe à `Auth : identité managée`. L'ancienne clé est refusée, l'app répond toujours.

```powershell
curl.exe -s -w "\n%{http_code}\n" "https://$FDY.openai.azure.com/openai/models?api-version=2024-10-21" `
  -H "api-key: <ancienne clé>"
```

**À dire** : la clé reste dans l'historique git, elle est brûlée pour toujours. L'identité managée et son rôle existaient depuis le build : la propagation des droits prend plusieurs minutes, impossible en direct.

---

## Carte 02 · Le RSSI refuse l'accès public

Ajouter dans `infra/main.bicepparam` :

```bicep
param enablePrivate = true
```

```powershell
git commit -am "carte 02 : Foundry en privé" && git push && gh run watch
```

Le Bicep déploie le VNet, le private endpoint, les 3 zones DNS privées, intègre la Web App au VNet et coupe l'accès public de Foundry.

**Preuve** : depuis le portable, Foundry ne répond plus (le code passe de 401 à 403, « public access is disabled ») ; l'app, elle, répond.

```powershell
curl.exe -s -w "\n%{http_code}\n" "https://$FDY.openai.azure.com/openai/models?api-version=2024-10-21"
Invoke-RestMethod -Method Post "$URL/api/chat" -ContentType 'application/json' -Body '{"question":"Où a lieu le DevDay ?"}'
```

**À dire** : le pipeline déploie toujours, car le plan de contrôle Azure reste joignable. Seul le plan de données passe en privé.

---

## Carte 03 · La région Azure est down

```powershell
# Panne simulée, annoncée comme telle
az webapp stop -g $RG -n $APP

# Bascule : la France devient la région par défaut, le pipeline y pousse l'état courant
gh variable set LOCATION --body francecentral
gh workflow run deploy; Start-Sleep 5; gh run watch
```

La France est **prête depuis la veille** (*warm standby*, déployée avec l'état du build). Le pipeline n'y pousse que ce qui a changé depuis : les parades déjà jouées (identité managée, réseau privé…) s'appliquent avec le reste. C'est ce qui fait tenir la carte dans les 5 minutes, et le rôle de l'identité managée y existe déjà : pas d'attente de propagation des droits si la carte 01 est passée.

**Preuve** : relancer le bloc de variables, puis **afficher le QR code de la France** (sur la fiche de la carte 03, diapo 18 : `18` + Entrée) : la salle arrive sur `app-devday-chaos-francecentral`, la région est dans l'adresse et dans le bandeau d'état.

**À dire** : « Si votre infra n'est pas en code, votre plan de reprise est un document Word. » Christophe assume la région de reprise : « Elle tournait déjà. Une reprise qu'on n'a jamais déployée, c'est une reprise qui ne marche pas. » Et Mario : « Vous avez dû rescanner. En production, c'est le rôle de Front Door ou de Traffic Manager, et ça se prévoit avant la panne. »

---

## Carte 04 · Quota du modèle épuisé

**Montrer la panne** :

```powershell
./coulisses/scripts/charge.ps1 $URL
```

On voit des erreurs en cascade. Dans le portail, Application Insights montre les 429 de Foundry.

**Parade**, ajouter dans `infra/main.bicepparam` (un **autre** modèle : le quota est compté par modèle) :

```bicep
param fallbackModelName = 'gpt-4.1-nano'
param fallbackModelVersion = '2025-04-14'
```

Le code du repli et de la limite par spectateur est déjà dans l'app : le Bicep l'allume avec le modèle de repli (`Ai__FallbackModel` renseigné, `Features__RateLimit=true`).

```powershell
git commit -am "carte 04 : modèle de repli" && git push && gh run watch
./coulisses/scripts/charge.ps1 $URL      # que des 200
```

**À dire** : ne jamais limiter par adresse IP, toute la salle partage celle du Wi-Fi.

---

## Carte 05 · Le budget est divisé par deux

Dans `infra/main.bicepparam`, modifier les deux lignes « Hébergement » et ajouter le budget :

```bicep
param appSku = 'B1'
param logRetentionDays = 30
param budgetAmount = 50
param budgetEmails = [ 'christophe@sparkx.tech' ]
// optionnel : modèle plus petit
// param modelName = 'gpt-4.1-nano'
```

```powershell
git commit -am "carte 05 : moitié prix" && git push && gh run watch
```

**Preuve** : diapo de chiffres préparée (Cost Management n'est pas en temps réel), budget visible dans le portail.

**À dire** : B1 garde l'intégration VNet, la carte 02 reste valable. On réduit là où la valeur est faible, jamais la sécurité.

---

## Carte 06 · Injection de prompt

**Montrer l'attaque** (1 min, Mario choisit ce qui est projeté) :
- un jailbreak grossier (« ignore tes instructions… ») : **déjà bloqué** par le filtrage par défaut ;
- une demande hors sujet ou « répète tes instructions » : **elle passe**.

**Parade**, ajouter dans `infra/main.bicepparam` :

```bicep
param enablePromptShields = true
```

Le même paramètre allume aussi le garde-fou du code, déjà livré (`Features__PromptGuard=true`) : prompt cadré et filtre de sortie.

```powershell
git commit -am "carte 06 : défense en couches" && git push && gh run watch
```

**Preuve** : rejouer les meilleures attaques de la salle.

**À dire** : « On ne rend pas un LLM incorruptible. On limite ce qu'il peut casser. »

---

## Carte 07 · Audit des accès demain matin

Pas de changement Bicep : **vider `devOwnerPrincipalId` ne retire pas l'Owner**. Azure ne supprime pas ce qu'on retire d'un template en mode incrémental. Point à faire relever par Mario.

```powershell
# Qui a accès à quoi ?
az role assignment list -g $RG --include-inherited -o table

# Retirer l'Owner permanent d'Adrien
az role assignment delete --assignee <upn-adrien> --role Owner -g $RG

# La preuve pour l'auditeur
az role assignment list -g $RG --include-inherited -o json > audit-acces.json
az monitor activity-log list -g $RG --offset 1h `
  --query "[].{qui:caller, quoi:operationName.localizedValue}" -o table
```

Puis vider la ligne dans `infra/main.bicepparam`, pour que le prochain push ne la recrée pas :

```bicep
param devOwnerPrincipalId = ''
```

**Dans le portail** : montrer Adrien éligible à Contributor via PIM, au lieu d'Owner permanent.

**À relever** : l'identité du pipeline a « RBAC Administrator » sur toute la souscription. C'est large, et on pourrait le restreindre par condition.

---

## Carte 08 · Une CVE zero-day vient de tomber

**Un seul déploiement** : la mitigation se fait en quelques secondes en CLI, le correctif part en un seul commit.

**1. Sommes-nous touchés ?** (30 s)

```powershell
dotnet list src package --vulnerable --include-transitive
Select-String -Path src/*.cs -Pattern "Newtonsoft"    # quelle fonctionnalité l'utilise ? → Export.cs
```

**2. Mitigation sans correctif**, tout de suite, sans attendre un déploiement :

```powershell
az webapp config appsettings set -g $RG -n $APP --settings Features__Export=false -o none
```

Bandeau : `Export : désactivé` apparaît en quelques secondes (l'app relit ses réglages à chaque requête). Le bouton « Exporter l'historique » renvoie un message de désactivation, le reste de l'app répond.

**3. « Le correctif vient de sortir »** (Mario, vers la 2e minute) : monter la version et poser le verrou NuGet Audit.

```powershell
dotnet add src package Newtonsoft.Json --version 13.0.3
```

Dans `src/DevDayChaos.csproj`, sous `<NuGetAuditMode>all</NuGetAuditMode>` :

```xml
<WarningsAsErrors>$(WarningsAsErrors);NU1901;NU1902;NU1903;NU1904</WarningsAsErrors>
```

```powershell
git commit -am "carte 08 : correctif + build bloqué si vulnérable" && git push && gh run watch
```

Rien à écrire dans `main.bicepparam` : le déploiement repose les réglages du Bicep, donc `Features__Export=true`, et l'export revient avec le package corrigé.

> L'infra se déploie avant le code : pendant environ une minute, l'export revient actif avec l'ancien package. Pour l'éviter, ajouter `param featureFlags = { Export: false }` dans le même commit, puis retirer la ligne après la session.

**À dire** : « Le jour d'une CVE, la seule question est : suis-je touché ? Sans inventaire de vos dépendances, personne ne sait répondre. »

---

## Carte 09 · Le client veut du on-prem (finale, 32')

Rien dans Azure : le même code tourne sur la machine de scène, avec un modèle local.

**La veille** (le téléchargement du modèle est long) :

```powershell
winget install Microsoft.FoundryLocal
foundry model run phi-4-mini      # télécharge et charge le modèle
```

**En direct** :

```powershell
foundry service status            # donne l'URL, ex. http://127.0.0.1:5273
foundry model list                # donne l'identifiant exact du modèle chargé

$env:Ai__Mode     = "local"
$env:Ai__Endpoint = "http://127.0.0.1:5273/v1"
$env:Ai__Model    = "<identifiant du modèle>"
dotnet run --project src
```

**Preuve** :
1. même question à l'app cloud et à l'app locale, côte à côte, et commenter honnêtement l'écart de qualité ;
2. couper le Wi-Fi de la machine : l'app locale répond toujours.

**À dire** : « Même code, même config. La portabilité se décide à la première ligne de code. »

---

## Après la session, ou entre deux répétitions

Tout remettre dans l'état du build :

```powershell
# Supprimer les ressources des deux régions
az group delete -n rg-devday-chaos-swedencentral --yes
az group delete -n rg-devday-chaos-francecentral --yes

# Libérer les noms Foundry (réservés 48 h après suppression)
az cognitiveservices account list-deleted -o table
az cognitiveservices account purge -g <rg> -n <nom-foundry> -l <région>

# Revenir à la région et au code du build
gh variable set LOCATION --body swedencentral
git switch main
git reset --hard etat-build
git push --force origin main      # relance le pipeline : la Suède est recréée
gh run watch

# La région de reprise, avec le même état du build (carte 03)
gh workflow run deploy -f location=francecentral; Start-Sleep 5; gh run watch
```

L'app répond tout de suite : en mode clé, le Bicep lui donne la clé du Foundry **de sa région** (app setting `Ai__Key`). La clé commitée dans `src/appsettings.json` ne sert qu'à l'histoire de la fuite ; la recoller (`setup.md`, étape 6) est facultatif, pour que la clé « fuitée » soit la vraie.

> **Crédit Azure** : les deux régions coûtent deux fois le build. Entre deux répétitions, supprimer au moins la France, et ne la redéployer que pour tester la carte 03 et à J-1.

> Si la protection de branche de `main` est active, autoriser le push forcé pour toi seul, ou la désactiver le temps de la remise à zéro.
