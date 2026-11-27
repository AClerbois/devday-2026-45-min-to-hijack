# 60 minutes chrono : on ship une app IA à trois, et le public sabote

Session du **DevDay 2026**, track Développeurs · **3 décembre 2026** · Palais des Congrès de Mons · créneau réel : **45 minutes**.

Par **Adrien Clerbois** (le dev), **Christophe Troessaert** (l'architecte) et **Mario Acebes** (le RSSI).

> **Repo privé.** Il contient la liste des cartes chaos : ne pas le partager avant la session, la surprise fait partie du jeu.

| Document | Pour quoi |
|---|---|
| `README.md` | La session : concept, déroulé, cartes, architecture (ce fichier) |
| `coulisses/setup.md` | Mettre en place la plateforme, une fois |
| `coulisses/run.md` | Les commandes de chaque carte, pendant la session |
| `coulisses/dry-run.md` | Valider chaque scénario avant le jour J : vérifications, durées, résultats |
| `coulisses/todo.md` | Ce qui reste à corriger avant le jour J, par priorité |
| `coulisses/scripts/` | Identité du pipeline, vérification du quota, charge de la carte 04 |
| `coulisses/README.md` | Le détail du Bicep et ses pièges |

---

## L'abstract soumis

> Le titre et le jeu restent « 60 minutes chrono ». Le créneau réel est de **45 minutes** : le déroulé plus bas est calé dessus.

Défi en direct : partir de zéro et déployer une app IA fonctionnelle sur Azure en une heure. Toutes les 10 minutes, la salle tire une carte chaos :
« la clé API a fuité sur GitHub »,
« le RSSI refuse l'accès public »,
« la région Azure est down »,
« le client veut finalement du on-prem ».

Chaque rôle doit réagir, négocier et adapter l'architecture.
C'est drôle, un peu stressant, et ça montre concrètement pourquoi DevSecOps n'est pas qu'un mot sur une slide.

## L'objectif

Faire comprendre l'intérêt du **DevSecOps** sur des problématiques **concrètes et actuelles** d'entreprise.

Ce que le public doit retenir :
- pourquoi dev, archi et sécurité doivent décider **ensemble** ;
- les réflexes qui font tenir une app IA quand tout change ;
- ce que ça coûte quand ce n'est pas prévu dès le premier jour.

Le message de fond, à dire dès les règles du jeu : **on survit au chaos parce que la plateforme est préparée, pas parce qu'on est des héros.** La boîte à outils est prête ; le chaos décide de ce qu'on allume.

---

## Les trois rôles

| Qui | Rôle sur scène | Ce qu'il défend | Ce qu'il montre |
|---|---|---|---|
| **Adrien** | Le dev | Livrer, vite | Le code .NET, le pipeline, les corrections dans le code |
| **Christophe** | L'architecte | Faire tenir les deux | L'infra en Bicep, les identités, le réseau, les régions |
| **Mario** | Le RSSI | Verrouiller | Le modèle de menaces, les garde-fous, l'audit |

Les désaccords sont **joués, et préparés** : pour chaque carte, on sait à l'avance qui veut quoi et quel compromis l'emporte.

Celui qui n'a pas le clavier tient le chrono et annonce les minutes restantes.

---

## Les règles du jeu

1. L'app et l'infra sont écrites en code dans ce repo. La plateforme a été déployée la veille par le pipeline : on montre le dernier run vert, pas une installation.
2. 6 minutes pour présenter l'app et mettre la version du build en ligne.
3. Toutes les 8 minutes, un spectateur tire une carte chaos dans un paquet de 8 et la lit à voix haute.
4. Négociation à trois (1 min 30), puis **vote à main levée « Qui a raison ? »** (20 s).
5. Correction en direct (5 min), puis la leçon en une phrase.
6. On tire 3 cartes. La 4e, c'est le client qui l'impose : **on-prem**, à la 32e minute.
7. À la fin : l'architecture d'arrivée face à celle du départ.

---

## Le déroulé (créneau de 45 min)

| Temps | Séquence | Qui mène |
|---|---|---|
| 0'00 | Ouverture : le chrono démarre, les trois rôles et l'objectif (sans dévoiler aucune carte) | Christophe |
| 1'00 | Les règles du jeu, montrer le paquet retourné | Mario |
| 2'00 | **L'app et le build** : la plateforme déployée la veille, le dernier run vert, la clé piège déjà dans la config « pour aller vite », le QR code | Adrien, puis les trois |
| 8'00 | **Carte chaos n°1** | selon la carte |
| 16'00 | **Carte chaos n°2** | selon la carte |
| 24'00 | **Carte chaos n°3** | selon la carte |
| 32'00 | **Carte finale : le client veut du on-prem** | Les trois |
| 39'00 | **Débrief** : avant / après, le code qui a sauvé la finale, 3 leçons | Les trois |
| 43'00 | Merci, puis questions | — |

### Le cycle d'une carte (8 min)

| Durée | Étape |
|---|---|
| 1 min | Tirage : un spectateur tire et lit la carte. On projette sa fiche. |
| 1 min 30 | Négociation à trois, puis vote « Qui a raison ? » à main levée |
| 5 min | Parade : une ligne dans `infra/main.bicepparam`, push, le pipeline redéploie. Pendant le déploiement, celui qui n'a pas le clavier explique |
| 30 s | Preuve (le bandeau d'état de l'app) et leçon |

**Le cycle ne tient que si un déploiement prend moins de 4 minutes.** Les cartes plus lentes par nature (02 : réseau privé ; 03 : bascule de région) se lancent dès la fin du vote, et la preuve peut glisser sur le tirage suivant.

Si la salle vote pour la mauvaise option : « La démocratie a parlé. Voici pourquoi elle a tort. » La parade ne change pas.

---

## Les cartes chaos

8 cartes dans le paquet, 3 tirées par session. La carte 09 est hors paquet, imposée à la fin.

| # | Carte | Mène | Vote « Qui a raison ? » | Parade | Leçon |
|---|---|---|---|---|---|
| 01 | La clé API a fuité sur GitHub | Mario | A « on régénère la clé » · **B « on supprime la clé »** | Clés régénérées, identité managée, authentification par clé interdite | Le meilleur secret, c'est celui qui n'existe pas. |
| 02 | Le RSSI refuse l'accès public | Mario contre Adrien | A « on garde le public » · B « on ferme tout » → **ni l'un ni l'autre** | Foundry en privé (private endpoint, DNS privé), le front reste public | Le réseau privé, c'est un paramètre si on l'a prévu, un projet sinon. |
| 03 | La région Azure est down | Christophe | A « on attend » · **B « on redéploie ailleurs »** | La région de reprise, prête depuis la veille, reçoit l'état courant par le pipeline | Si votre infra n'est pas en code, votre plan de reprise est un document Word. |
| 04 | Quota du modèle épuisé | Adrien | A « plus de quota » · **B « repli et limite de débit »** | Modèle de repli, limite par spectateur | Un modèle IA est une dépendance comme une autre : elle sature, elle tombe, elle se facture. |
| 05 | Le budget est divisé par deux | Christophe | A « on rogne les logs » · **B « on réduit le modèle »** | Plan réduit, rétention réduite, budget avec alertes | Le coût est une exigence non fonctionnelle, au même titre que la sécurité. |
| 06 | Injection de prompt | Mario | A « un meilleur prompt suffit » · **B « défense en couches »** | Filtrage strict Foundry, prompt cadré, filtre de sortie | On ne rend pas un LLM incorruptible. On limite ce qu'il peut casser. |
| 07 | Audit des accès demain matin | Christophe, Mario en auditeur | A « Owner permanent » · **B « droits juste à temps »** | Owner retiré, rôles minimaux, PIM, preuve exportée | Le moindre privilège, c'est facile au jour 1 et douloureux au jour 300. |
| 08 | Une CVE zero-day vient de tomber | Mario, Adrien au clavier | A « on attend le correctif » · B « on coupe tout » → **on mesure et on mitige** | Inventaire des dépendances, fonction coupée, correctif, build bloqué si vulnérable | Le jour d'une CVE, la seule question est : suis-je touché ? |
| **09** | **Le client veut finalement du on-prem** (finale) | Les trois | A « on reste dans le cloud » · B « on rapatrie tout » → **les deux, c'est le même code** | Même code en local avec Foundry Local, Wi-Fi coupé, l'app répond | La portabilité se décide à la première ligne de code. |

La carte 08 est une **simulation annoncée comme telle** : une vraie CVE, déjà connue (`Newtonsoft.Json 12.0.3`, CVE-2024-21907), plantée volontairement au build.

La carte 09 tombe bien : souveraineté et rapatriement sont dans toutes les têtes, et Microsoft propose lui-même ce scénario (cloud privé souverain sur Azure Local, Foundry Local pour l'inférence en local). Nuance à placer au débrief : **souverain ne veut pas dire on-prem, et on-prem ne veut pas dire sûr.**

Le détail de chaque carte (négociation, étapes, prérequis, enchaînements délicats) est dans les notes des diapos masquées du deck, et les commandes sont dans `coulisses/run.md`.

---

## L'app

**« Demandez au DevDay »** : un assistant IA qui répond aux questions de la salle sur l'événement. La salle l'utilise via un QR code, ce qui sert les cartes 04 (quota) et 06 (injection).

En bas de la page, un **bandeau d'état** affiche la région, le modèle et le mode d'authentification ; chaque protection n'y apparaît qu'une fois activée. C'est la preuve visible de chaque carte.

### Les pièges posés au build

| Piège | Carte |
|---|---|
| Clé API commitée dans `appsettings.json` « pour aller vite », déjà là au build | 01 |
| Foundry joignable depuis Internet | 02 |
| Une seule région | 03 |
| Quota serré, pas de modèle de repli, pas de limite par spectateur | 04 |
| Plan P0v3, logs gardés 90 jours, pas de budget | 05 |
| Filtrage par défaut, prompt naïf | 06 |
| Adrien Owner permanent du groupe de ressources | 07 |
| `Newtonsoft.Json 12.0.3` utilisé par l'export | 08 |
| — (la portabilité est prévue dès le départ) | 09 |

---

## L'architecture

```
                    GitHub (repo privé)
                    ├─ src/        app .NET 10
                    ├─ infra/      Bicep
                    └─ .github/    GitHub Actions
                          │  push sur main
                          ▼
              GitHub Actions ── OIDC, aucun secret ──► Azure
              1. lint Bicep, build .NET, packages vulnérables
              2. Bicep : infra
              3. déploiement du code + test de fumée

   Azure (une région UE, une seconde pour la carte 03)
   ┌──────────────────────────────────────────────────────────┐
   │  Web App (App Service Linux)  ──identité managée──►  Azure AI Foundry │
   │  .NET 10, code déployé                               projet + modèles  │
   │                                                      DataZone UE       │
   │  ── carte 02 : VNet, private endpoint, DNS privé ──                    │
   │  Log Analytics + Application Insights                                  │
   └──────────────────────────────────────────────────────────┘

   Machine de scène (carte 09) : même code, dotnet run, Foundry Local
```

| Brique | Choix |
|---|---|
| Hébergement | Web App, App Service Linux, déploiement du code (pas de conteneur) |
| IA | Azure AI Foundry, ressource `AIServices`, modèles en `DataZoneStandard` (données dans l'UE) |
| App | ASP.NET Core .NET 10, `Microsoft.Extensions.AI` (`IChatClient`), Azure OpenAI |
| IaC | Bicep, un seul fichier à modifier : `infra/main.bicepparam` |
| CI/CD | GitHub Actions, connexion OIDC, PR → what-if, main → déploiement |
| On-prem | Foundry Local, même code, même config |

**Toutes les parades sont dans le code dès le build, coupées par configuration.** Une carte ajoute une ligne dans `main.bicepparam`, le Bicep le pose en app setting, l'app change de comportement. Aucun merge de branche en direct.

```
src/
├─ Options.cs          les réglages lus à chaque requête (contrat de coulisses/setup.md)
├─ Program.cs          endpoints, limite par spectateur (04), état affiché
├─ ChatClients.cs      Azure ou local (09), clé ou identité (01), repli (04)
├─ Prompts.cs          prompt naïf / cadré, filtre de sortie (06)
├─ Export.cs           la fonction qui dépend du package vulnérable (08)
├─ appsettings.json    la clé piège (01)
└─ wwwroot/index.html  la page et son bandeau d'état
infra/
├─ main.bicep          les paramètres, valeurs par défaut = état du build
├─ main.bicepparam     l'état du build, sans aucune parade : chaque carte y ajoute une ligne
└─ modules/            foundry, webapp, network, private-endpoint, monitoring
.github/workflows/deploy.yml
coulisses/
├─ README.md           le détail du Bicep et ses pièges
├─ setup.md            mise en place, une fois
├─ run.md              les commandes de chaque carte
├─ dry-run.md          valider chaque scénario avant le jour J
└─ scripts/
   ├─ setup-oidc.ps1   une fois : identité du pipeline
   ├─ check-quota.ps1  avant le 1er déploiement : quota des modèles
   └─ charge.ps1       carte 04 : sature le quota
```

---

## Les supports

| Support | Où |
|---|---|
| Le deck (template DevDay) | `DevDay2026_60min_chrono_FR.pptx`, conducteur minute par minute dans les notes, QR Suède sur la diapo 7 et QR France sur la fiche de la carte 03 |
| Les fiches des cartes | Diapos masquées 16 à 23 du deck. En présentation : taper le numéro puis Entrée, et 9 + Entrée pour revenir |
| Les cartes à imprimer | Canevas « Cartes chaos · DevDay 2026 » : 9 rectos + un verso commun, A5, à imprimer sur carton |
| La plateforme | Ce repo : `coulisses/setup.md`, puis `coulisses/run.md` |

---

## Préparation jusqu'au 3 décembre

- [ ] Souscription de démo hors ORES, identité OIDC (`coulisses/setup.md`, étapes 1 à 4)
- [ ] Versions des packages remontées et app compilée par Adrien (`coulisses/setup.md`, étape 2 bis)
- [ ] Modèles et quota vérifiés dans les **deux** régions
- [ ] Premier déploiement fait **la veille** de la session (`etat-build`), en Suède **et en France** (région de reprise de la carte 03), derniers runs verts
- [ ] **Durée d'un déploiement mesurée** : moins de 4 minutes, sinon le cycle de 8 minutes ne tient pas
- [ ] Chaque parade chronométrée : 5 minutes maximum, déploiement compris
- [ ] Enchaînements testés : 02 puis 03, 03 puis 02, et un ordre tiré au hasard
- [ ] Lecture à voix haute des 9 négociations, à trois
- [ ] Foundry Local et son modèle sur la machine de scène, démarrage à froid en moins de 30 s
- [ ] Deux QR codes, Suède et France (les URL sont fixes : `app-devday-chaos-<région>.azurewebsites.net`)
- [ ] Cartes imprimées (après une carte test)
- [ ] Dispositif de salle confirmé avec l'organisation : écrans, micros, micro main pour le tirage
- [ ] Deck envoyé aux organisateurs dans les délais (PDF et .pptx)
- [ ] Une répétition complète chronométrée, avec quelques collègues dans le rôle du public

## Décisions encore ouvertes

- **Le tirage** : un volontaire, ou un spectateur désigné par une gommette sous son siège.
- **Le baromètre** « cloud public, souverain ou on-prem ? », posé au début et à la fin.
- **Le chrono à l'écran** : une page à part toujours visible, une barre dans les diapos, ou un second écran.
- **La projection du repo** : GitHub affiche ce README sur la page d'accueil du repo, avec toutes les cartes, et le dossier `coulisses/` est visible. Soit on n'ouvre jamais la page d'accueil sur scène (seulement l'onglet Actions, `infra/` et `src/`), soit on déplace ce README dans `coulisses/` et on met un README neutre à la racine.
- **Le contenu de l'app** : le programme du DevDay à coller dans `src/Prompts.cs`.
