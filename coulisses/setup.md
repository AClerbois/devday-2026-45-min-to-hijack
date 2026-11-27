# Mise en place de la plateforme

À faire **une fois**, avant la première répétition. Compter environ une heure, plus le temps du premier déploiement.

Une fois en place, la plateforme fonctionne ainsi : chaque push sur `main` déclenche GitHub Actions, qui déploie l'infra (Bicep) puis le code de l'app (.NET). On ne touche jamais au portail Azure.

```
push sur main ──► GitHub Actions ──► 1. Bicep : Web App + Foundry (+ réseau, budget… selon les cartes)
                                    └► 2. .NET : compile src/ et le déploie sur la Web App
```

---

## 1. Prérequis

| Quoi | Pourquoi | Vérifier |
|---|---|---|
| Azure CLI | Déploiement, vérifications, parades | `az version` |
| GitHub CLI | Repo, secrets, lancement du pipeline | `gh auth status` |
| SDK .NET 10 | Build local et carte 09 | `dotnet --version` |
| PowerShell 7.3+ | Toutes les commandes et les scripts de `coulisses/scripts/` | `$PSVersionTable.PSVersion` |
| Une souscription Azure **de démo** | Hors ORES, sans aucune donnée client | — |
| Owner sur cette souscription | Créer les ressources et les rôles | — |
| Droit de créer une inscription d'application dans Entra ID | Identité OIDC du pipeline | — |

---

## 2. Créer le repo

Le repo doit être **privé** : la carte 01 repose sur une vraie clé commitée volontairement, et un repo public déclencherait le secret scanning de GitHub au push.

```powershell
gh repo create devday-chaos --private --clone
cd devday-chaos
```

Dézipper `devday-chaos-infra.zip` à la racine. On obtient :

```
devday-chaos/
├─ README.md                   la session
├─ coulisses/                  ce qui ne se projette pas
│  ├─ README.md                le détail du Bicep et ses pièges
│  ├─ setup.md                 ce fichier
│  ├─ run.md                   le jeu, carte par carte
│  ├─ dry-run.md               valider chaque scénario avant le jour J
│  └─ scripts/
│     ├─ setup-oidc.ps1
│     ├─ check-quota.ps1
│     └─ charge.ps1            carte 04
├─ infra/                      Bicep (on ne modifie que main.bicepparam)
├─ .github/workflows/deploy.yml
└─ src/                        l'app .NET
   ├─ Options.cs               les réglages du contrat ci-dessous
   ├─ ChatClients.cs           Azure ou local, clé ou identité, modèle de secours
   ├─ Program.cs               API, limite par utilisateur, état affiché
   ├─ Prompts.cs               prompt par défaut / durci, filtre de sortie
   ├─ Export.cs                la fonction qui dépend du package vulnérable
   ├─ appsettings.json         Ai:Auth = key, la clé « fuitée » (étape 6)
   └─ wwwroot/index.html       la page et son bandeau d'état
```

> **Le code n'a pas encore été compilé.** Avant la première répétition, Adrien remonte les packages à leur dernière version (sauf `Newtonsoft.Json`, le piège de la carte 08) et compile :
>
> ```powershell
> 'Microsoft.Extensions.AI','Azure.Identity','Azure.Monitor.OpenTelemetry.AspNetCore' | % { dotnet add src package $_ }
> 'Microsoft.Extensions.AI.OpenAI','Azure.AI.OpenAI' | % { dotnet add src package $_ --prerelease }   # sans --prerelease si une version stable existe
> dotnet build src
> ```
>
> Deux points à vérifier selon les versions retenues : le nom `AsIChatClient()` (anciennement `AsChatClient()`), et le fait qu'une erreur 429 ou 400 du modèle remonte bien en `ClientResultException`.

### Le contrat de l'app (`src/`)

**Tout le code des parades est livré dès le build, éteint.** Une carte ne fait qu'allumer un réglage depuis `main.bicepparam` : aucun merge en direct, donc aucun conflit quel que soit l'ordre du tirage. L'app lit ces réglages à chaque requête (`IOptionsMonitor`), et le Bicep les pose en app settings :

| Réglage | Valeurs | Carte | Comportement attendu |
|---|---|---|---|
| `Ai:Mode` | `azure` · `local` | 09 | `local` : Foundry Local (endpoint compatible OpenAI, sans authentification) |
| `Ai:Endpoint`, `Ai:Model` | posés par le Bicep | — | Endpoint Foundry et nom du déploiement principal |
| `Ai:Auth` | `key` (build) · `identity` | 01 | `key` : utilise `Ai:Key` (le piège). `identity` : `DefaultAzureCredential`, sans clé |
| `Ai:Key` | app setting `Ai__Key` posé par le Bicep · commitée dans `appsettings.json` | 01 | En mode clé, le Bicep pose la clé du Foundry **de la région** (elle prime sur `appsettings.json`) : l'app marche en France et après chaque remise à zéro. La clé commitée sert l'histoire de la fuite, et on la retire pendant la carte. En mode identité, l'app setting disparaît |
| `Ai:FallbackModel` | vide (build) · nom du modèle | 04 | Renseigné : sur un 429 du modèle principal, réessayer avec ce modèle |
| `Features:RateLimit` | `false` (build) · `true` | 04 | Limite **par spectateur**, jamais par IP (toute la salle partage le Wi-Fi). Réponse 429 au-delà |
| `Features:PromptGuard` | `false` (build) · `true` | 06 | Prompt système cadré + filtre de sortie (refuser hors sujet, ne pas répéter ses instructions) |
| `Features:Export` | `true` (build) · `false` | 08 | La fonctionnalité qui utilise le package vulnérable : `false` la coupe |

Et une API : `POST /api/chat` avec `{"question": "..."}`, utilisée par les preuves de `run.md` et par `coulisses/scripts/charge.ps1`. Plus `GET /api/status` (l'état affiché par le bandeau) et `GET /api/export`.

La limite par spectateur repose sur l'en-tête `X-User`, envoyé par la page (un identifiant par navigateur) ; une requête sans `X-User` n'est pas limitée. La région affichée se lit dans le nom de la Web App (`app-devday-chaos-<région>`).

Seule la carte 08 touche vraiment au code en direct : la montée de version du package dans le `.csproj`, une ligne.

---

## 3. Vérifier les modèles et le quota

Les modèles par défaut (`gpt-4.1-mini` et, pour la carte 04, `gpt-4.1-nano`, version `2025-04-14`, en `DataZoneStandard`) doivent exister **dans les deux régions** : la région de départ et celle de la carte 03.

```powershell
az login
az account set --subscription <id-souscription>

# Le nom et la version sont imbriqués sous « model » : un simple « -o table » ne les affiche pas.
foreach ($loc in 'swedencentral', 'francecentral') {
  az cognitiveservices model list -l $loc `
    --query "[?starts_with(model.name, 'gpt-4.1')].{name:model.name, version:model.version, skus:join(',', model.skus[].name)}" -o table
}
```

Puis vérifier le **quota**, qui est souvent à 0 sur un abonnement Visual Studio ou d'essai même quand le modèle existe. Il faut **10 000 tokens par minute pour `gpt-4.1-mini`** (le build) et **50 000 pour `gpt-4.1-nano`** (le repli de la carte 04, qui doit absorber `charge.ps1`) ; valeurs à confirmer au dry-run. Le script lit `main.bicep` et `main.bicepparam`, contrôle les deux régions et, s'il manque du quota, indique exactement quoi demander (`-Open` ouvre le portail Foundry) :

```powershell
./coulisses/scripts/check-quota.ps1 -Open
```

Il n'existe pas d'API pour demander du quota : la demande se fait dans le portail Foundry (Management center > Quota > Request quota, étendue **eur** pour `DataZoneStandard`). L'approbation peut prendre plusieurs jours : faire cette étape **tôt**. Si un modèle manque, changer `modelName` / `modelVersion` (et les valeurs de repli) dans `infra/main.bicepparam`.

---

## 4. Créer l'identité du pipeline (OIDC)

Le pipeline se connecte à Azure par OIDC (credential fédéré) : aucun mot de passe n'est stocké dans GitHub.

```powershell
./coulisses/scripts/setup-oidc.ps1 <compte-github>/devday-chaos <id-souscription>
```

Le script :
- crée l'inscription d'application `gh-devday-chaos` et son principal de service ;
- l'autorise à se connecter depuis l'environnement GitHub `demo` et depuis les PR de ce repo ;
- lui donne **Contributor** et **Role Based Access Control Administrator** sur la souscription ;
- remplit les secrets `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` et la variable `LOCATION`.

Créer ensuite l'environnement `demo` (sans reviewer obligatoire, sinon chaque déploiement attend une approbation) :

```powershell
gh api -X PUT repos/<compte-github>/devday-chaos/environments/demo
```

---

## 5. Premier déploiement

```powershell
git add .
git commit -m "build"
git push -u origin main
gh run watch
```

Le pipeline :
1. **verify** : lint et compilation du Bicep, build .NET, liste des packages vulnérables ;
2. **deploy** : crée `rg-devday-2026-devsecops-talk-swedencentral`, déploie l'infra, puis le code ;
3. **test de fumée** : la page, `/api/status` et une vraie question ; affiche `App en ligne → https://app-devday-chaos-swedencentral.azurewebsites.net` et la réponse du modèle. Un 429 passe avec un avertissement (modèle joignable mais saturé).

**Noter la durée totale du run.** Elle conditionne tout le chrono : avec des cartes de 8 minutes, la parade dispose de 5 minutes, donc **un déploiement doit prendre moins de 4 minutes**. Le premier déploiement, lui, se fait la veille de la session.

### La région de reprise (carte 03)

La France est déployée **à l'avance**, avec le même état du build (*warm standby*) :

```powershell
gh workflow run deploy -f location=francecentral; Start-Sleep 5; gh run watch
```

Sans ça, la carte 03 devrait tout créer en direct (Foundry, modèle, plan, Web App) : bien plus que 5 minutes, et après la carte 01 l'identité managée attendrait la propagation de son rôle. Avec la France prête, le pipeline n'y pousse que l'état courant.

Deux régions coûtent deux fois le build : la supprimer entre les répétitions qui ne testent pas la carte 03, et la redéployer à J-1.

### Les deux QR codes

Le nom de la Web App suit la région : les deux URL sont connues d'avance, et ne changent pas d'une répétition à l'autre.

| QR code | URL | Quand le projeter |
|---|---|---|
| Suède | `https://app-devday-chaos-swedencentral.azurewebsites.net` | Au build, et jusqu'à la carte 03 |
| France | `https://app-devday-chaos-francecentral.azurewebsites.net` | Après la carte 03 |

Ils sont **déjà générés** (QR statiques, l'URL est encodée directement, sans serveur tiers) : `coulisses/qr/QR_Suede_swedencentral.png` et `coulisses/qr/QR_France_francecentral.png`. Ils sont aussi dans le deck : Suède sur la diapo 7 (build), France sur la fiche de la carte 03 (diapo 18).

---

## 6. Poser les pièges du build

La session part d'une app volontairement mal configurée. Chaque carte corrige un défaut.

| Piège | Pour la carte | Comment le poser |
|---|---|---|
| Clé API dans la config | 01 | Voir ci-dessous |
| Endpoints publics | 02 | Déjà le cas par défaut (`enablePrivate = false`) |
| Une seule région active | 03 | Déjà le cas : la France est prête (étape 5) mais personne ne l'utilise |
| Quota serré, pas de repli | 04 | Déjà le cas (`modelCapacity = 10`, `fallbackModelName = ''`) : assez pour l'usage normal, pas pour `charge.ps1` |
| Plan P0v3, rétention 90 jours, pas de budget | 05 | Déjà le cas |
| Filtrage par défaut, prompt faible | 06 | Déjà le cas côté infra ; prompt faible dans le code |
| Owner permanent pour Adrien | 07 | Voir ci-dessous |
| Package vulnérable dans l'app | 08 | Déjà planté : `Newtonsoft.Json 12.0.3` (CVE-2024-21907), utilisé par l'export |

**Clé API (carte 01)** :

```powershell
$FDY = az cognitiveservices account list -g rg-devday-2026-devsecops-talk-swedencentral --query "[0].name" -o tsv
az cognitiveservices account keys list -g rg-devday-2026-devsecops-talk-swedencentral -n $FDY --query key1 -o tsv
```

Coller la clé dans `src/appsettings.json`, champ `Ai:Key`, et commiter : c'est la clé « fuitée » de la carte 01.

L'app n'en dépend pas : en mode clé, le Bicep lui pose la clé du Foundry de sa région (`Ai__Key`). Après une remise à zéro, la clé commitée devient une clé morte ; la recoller est facultatif, seulement pour que la « fuite » montre une vraie clé.

**Owner permanent (carte 07)** :

```powershell
az ad user show --id <upn-adrien> --query id -o tsv
```

Coller l'object id dans `infra/main.bicepparam`, ligne `devOwnerPrincipalId`.

**Package vulnérable (carte 08)** : vérifier qu'il remonte bien :

```powershell
dotnet list src package --vulnerable --include-transitive
```

Puis commit, push, et **marquer cet état** : c'est le point de départ de chaque répétition.

```powershell
git commit -am "pièges du build"
git push && gh run watch
git tag etat-build && git push origin etat-build
```

---

## 7. Tester les enchaînements

L'ordre des cartes est tiré au sort : chaque parade doit marcher quelles que soient celles déjà jouées. Depuis `etat-build`, tester au moins les deux enchaînements délicats : **02 puis 03** et **03 puis 02** (le réseau privé doit exister dans la région de repli). Puis faire une répétition avec un ordre tiré au hasard.

---

## 8. Prévoir avant le jour J

- [ ] **Les deux QR codes** (Suède et France, voir l'étape 5), testés avec plusieurs téléphones, en 4G et sur le Wi-Fi de la salle
- [ ] Foundry Local installé et modèle téléchargé la veille sur la machine de scène (carte 09, voir `run.md`)
- [ ] Un passage complet chronométré à trois

Pour remettre la plateforme à zéro entre deux répétitions : voir la fin de `run.md`.
