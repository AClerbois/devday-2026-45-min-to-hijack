# Infra de démo · DevDay 2026 · « 60 minutes chrono »

Une **Web App** (App Service Linux, .NET 10, déploiement du code) et une ressource **Azure AI Foundry** (kind `AIServices`, un projet, un ou deux modèles), déployées par **GitHub Actions** en **Bicep**.

```
infra/
├─ main.bicep                  orchestration, un paramètre par carte
├─ main.bicepparam             état du BUILD : c'est ce fichier qu'on modifie en direct
└─ modules/
   ├─ foundry.bicep            Foundry, projet, modèles, filtrage (carte 06), logs
   ├─ webapp.bicep             plan, Web App, identité managée, rôle sur Foundry
   ├─ network.bicep            carte 02 : VNet, sous-réseaux, 3 zones DNS privées
   ├─ private-endpoint.bicep   carte 02 : private endpoint de Foundry
   └─ monitoring.bicep         Log Analytics + Application Insights
.github/workflows/deploy.yml   PR : lint + what-if · main : infra puis code (étapes .NET sautées tant que src/ n'existe pas)
coulisses/scripts/
├─ setup-oidc.ps1              une fois : identité du pipeline (OIDC, sans secret), relançable
├─ check-quota.ps1             avant le 1er déploiement : quota des modèles dans les deux régions
└─ charge.ps1                  carte 04 : simule la salle pour épuiser le quota
```

## Jouer une carte

On **ajoute** la ligne de la carte dans `main.bicepparam`, puis commit et push. Le pipeline redéploie l'infra et le code.

`main.bicepparam` ne contient que l'état du build, sans aucune parade ni mention des cartes : on peut le projeter sans rien dévoiler. Les valeurs par défaut de `main.bicep` font le reste. Ce tableau sert d'antisèche : il ne se projette pas.

**Le code des parades est livré dès le build, éteint.** Le Bicep l'allume via des app settings, en même temps que le paramètre infra de la carte : aucun merge en direct, donc aucun conflit quel que soit l'ordre du tirage.

| App setting | Allumé par | Carte |
|---|---|---|
| `Ai__Auth` = `identity` | `useManagedIdentity` ou `disableLocalAuth` | 01 |
| `Ai__FallbackModel` + `Features__RateLimit` = `true` | `fallbackModelName` renseigné | 04 |
| `Features__PromptGuard` = `true` | `enablePromptShields` | 06 |
| `Features__Export` = `false` | `featureFlags` | 08 |

`featureFlags` passe en dernier et peut forcer n'importe quel interrupteur à la main. Le contrat complet attendu de l'app est dans `coulisses/setup.md`.

| Carte | Ligne à ajouter dans `main.bicepparam` | Ce que fait le Bicep | En plus, hors Bicep |
|---|---|---|---|
| **01** Clé fuitée | Un seul push : `useManagedIdentity = true` et `disableLocalAuth = true` | `Ai__Auth=identity`, clés refusées sur Foundry | Retirer la clé de `appsettings.json` dans le même commit. Régénérer les clés en CLI pendant le déploiement (voir piège 2). |
| **02** RSSI : pas de public | `enablePrivate = true` | VNet, private endpoint, 3 zones DNS, Web App intégrée au VNet, accès public de Foundry coupé | Preuve : un appel direct à Foundry depuis le portable est refusé, l'app répond. |
| **03** Région down | rien | La France est prête depuis la veille (*warm standby*) : le pipeline y pousse l'état courant | `gh variable set LOCATION --body francecentral` puis `gh workflow run deploy` (voir piège 9) |
| **04** Quota épuisé | `fallbackModelName` + `fallbackModelVersion` | Second déploiement de modèle, `Ai__FallbackModel` et `Features__RateLimit=true` | Rien : le code du repli et de la limite est livré au build, éteint. |
| **05** Budget ÷ 2 | `appSku = 'B1'`, `logRetentionDays = 30`, `budgetAmount`, `budgetEmails` | Plan réduit, rétention réduite, budget avec alertes à 80 % réel et 100 % prévu | Chiffres avant/après sur une diapo. |
| **06** Injection de prompt | `enablePromptShields = true` | Politique de filtrage stricte, et `Features__PromptGuard=true` | Rien : prompt cadré et filtre de sortie livrés au build, éteints. |
| **07** Audit des accès | piège au build : `devOwnerPrincipalId` = object id d'Adrien | Owner permanent sur le groupe de ressources | Parade en CLI (voir piège 1). |
| **08** CVE zero-day | rien (option : `featureFlags = { Export: false }` dans le commit du correctif) | — | Mitigation en CLI (`az webapp config appsettings set … Features__Export=false`), puis un seul commit : `Newtonsoft.Json` 13.0.3 et verrou NuGet Audit. |
| **09** On-prem | rien | — | `dotnet run` en local avec `Ai__Mode=local` et Foundry Local. |

## Les pièges, à connaître avant la répétition

1. **Le mode incrémental ne supprime rien.** Retirer une ressource ou vider `devOwnerPrincipalId` ne supprime pas l'attribution Owner. La parade de la carte 07 se fait en CLI :
   `az role assignment delete --assignee <adrien> --role Owner -g <rg>`.
   Mario peut en faire un point de la carte : l'IaC ne nettoie pas ce qu'on retire. Les *deployment stacks* (`az stack group create --action-on-unmanage deleteResources`) le font, si vous voulez aller plus loin.
2. **Carte 01 : un seul push, une minute d'erreurs.** Deux pushs (`useManagedIdentity`, puis `disableLocalAuth`) éviteraient toute coupure mais coûtent deux déploiements, soit environ 8 minutes : ça ne tient pas dans le cycle de 8 minutes. On pousse donc les deux d'un coup : Foundry est mis à jour avant la Web App, et l'app renvoie des erreurs pendant environ une minute. Mesurer cette fenêtre au dry-run.
3. **Suppression douce de Foundry.** Une ressource Cognitive Services supprimée reste réservée 48 h. Si vous supprimez le groupe de ressources entre deux répétitions, purgez-la avant de redéployer :
   `az cognitiveservices account purge -g <rg> -n <nom> -l <région>`.
4. **Modèle disponible ne veut pas dire quota disponible.** `gpt-4.1-mini` / `gpt-4.1-nano` version `2025-04-14` existent en `DataZoneStandard` en Suède et en France, mais un abonnement Visual Studio ou d'essai peut avoir **0** de quota (erreur `InsufficientQuota`, « 0 / 0 quota units »). Vérifier avec `./coulisses/scripts/check-quota.ps1`. La demande de quota ne se fait que dans le portail Foundry (étendue **eur** pour `DataZoneStandard`, une demande couvre les deux régions) et peut prendre plusieurs jours.
5. **Le quota est compté par modèle.** Le repli de la carte 04 doit être un autre modèle, pas un second déploiement du même.
6. **Carte 02, le pipeline continue de déployer.** Le plan de contrôle Azure (ARM) reste joignable ; seul le plan de données de Foundry devient privé. Un appel `az` ou `curl` vers l'endpoint IA depuis le portable échoue, et c'est la preuve à montrer.
7. **Le what-if des PR** suppose que le groupe de ressources existe déjà (après un premier déploiement).
8. **Sujet OIDC : deux formats.** GitHub peut présenter `repo:owner/repo:environment:demo` ou, avec identifiants immuables, `repo:owner@<id>/repo@<id>:environment:demo`. Si le credential fédéré ne correspond pas exactement : `AADSTS700213`. `setup-oidc.ps1` enregistre les deux formats ; vérifier aussi que `AZURE_CLIENT_ID` pointe bien vers l'application qui porte ces credentials.
9. **Carte 03 : la France se déploie la veille.** Créer la région de reprise en direct prendrait bien plus que 5 minutes (Foundry, modèle, plan, Web App), et après la carte 01 l'identité managée attendrait la propagation de son rôle. À J-1 : `gh workflow run deploy -f location=francecentral`. Elle double le coût : la supprimer entre les répétitions qui ne testent pas la carte 03.
10. **Carte 01 : la clé de la région.** En mode clé, le Bicep pose `Ai__Key` avec la clé du Foundry de la région (`listKeys()`), qui prime sur `src/appsettings.json`. Sans ça, l'app tomberait en France et après chaque remise à zéro, puisque la clé commitée est celle du premier Foundry. En mode identité, le réglage disparaît.
11. **Le quota compte `MaxOutputTokens`.** Azure réserve, pour chaque requête, les tokens du prompt plus le maximum de la réponse. L'app plafonne à 300 tokens ; à 1 000, une capacité de 10 ne passerait que quelques questions par minute.

## Mise en route

1. Créer le repo **privé** (sinon le secret scanning de GitHub bloque la clé piège de la carte 01).
2. `./coulisses/scripts/check-quota.ps1 -Open` : demander le quota manquant **tôt**, l'approbation n'est pas immédiate.
3. `./coulisses/scripts/setup-oidc.ps1 <owner/repo> <subscription-id>`, puis créer l'environnement GitHub `demo`.
4. Premier push sur `main` : le pipeline crée `rg-devday-2026-devsecops-talk-swedencentral` et déploie.
5. Mesurer la durée d'un déploiement complet : elle conditionne le chrono de chaque carte.
