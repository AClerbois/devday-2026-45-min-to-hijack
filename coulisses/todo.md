# À faire avant le 3 décembre

Revue complète du repo du 27 novembre : déroulé, docs, Bicep, pipeline, scripts et app. Cocher au fur et à mesure ; les valeurs marquées « au dry-run » se confirment pendant `dry-run.md`.

---

## Bloquants : à régler avant le dry-run

- [x] **1. Le quota laisse passer à peine une question par minute, pour toute la salle**
  - **Fait** : `MaxOutputTokens = 300`, `modelCapacity = 10`, `fallbackModelCapacity = 50`, `charge.ps1` à 10 en parallèle.
  - **Quota (dry-run du 27 novembre)** : rien à demander. La souscription a **50 M TPM** en DataZoneStandard (étendue EUR, pool partagé Suède + France) pour `gpt-4.1-mini` comme pour `gpt-4.1-nano`. `modelCapacity = 10` est donc un choix, pas une limite : on peut monter à 20-30 sans demande.
  - **Reste** : trancher `modelCapacity` au contrôle 0.10 (10 000 TPM ≈ 10 questions par minute pour la salle). Si on monte, vérifier à la carte 04 que `charge.ps1` déclenche encore des 429.
  - **Problème** : le build déploie `gpt-4.1-mini` avec `modelCapacity = 1`, soit 1 000 tokens par minute. Azure compte chaque requête **en incluant `MaxOutputTokens`** (1 000 dans `src/Program.cs`). Dès que la salle scanne le QR code (2'00), l'app est saturée, et toutes les preuves de cartes échouent, pas seulement la 04. Après la carte 04, le repli `gpt-4.1-nano` à 10 000 tokens par minute ne passe qu'une dizaine de questions par minute : « que des 200 » avec `charge.ps1` (60 requêtes) est impossible.
  - **Correction** : `MaxOutputTokens` à 300 partout ; capacité du build entre 10 et 20 ; repli plus large ; la panne de la carte 04 est déclenchée par `charge.ps1`. Valeurs exactes au dry-run.
  - **Conséquence** : ajuster la **demande de quota** (mini et nano, étendue eur) aux valeurs retenues.
  - **Fichiers** : `src/Program.cs`, `infra/main.bicepparam`, `infra/main.bicep` (`fallbackModelCapacity`)

- [x] **2. La carte 03 casse l'app si la carte 01 n'a pas été jouée avant**
  - **Fait** : `Ai__Key` posé par le Bicep (`listKeys()`) en mode clé ; la remise à zéro n'a plus d'étape « reposer la clé ». **Reste** : vérifier au dry-run (contrôle 0.9) que l'app France répond avec sa propre clé.
  - **Problème** : au build, l'app utilise la clé de `src/appsettings.json`, celle du Foundry **suédois**. Le Foundry français a d'autres clés : en France, l'app répond « Le modèle refuse l'authentification ».
  - **Correction** : le Bicep pose `Ai__Key` avec `listKeys()` du Foundry de la région quand `Ai__Auth = key`. La clé reste commitée dans `appsettings.json` pour l'histoire de la fuite, mais l'app utilise celle de sa région. Bonus : plus besoin de reposer la clé après chaque remise à zéro (simplifier la fin de `run.md` et `setup.md` étape 6).
  - **Fichiers** : `infra/modules/webapp.bicep`, `infra/main.bicep`, `coulisses/run.md`, `coulisses/setup.md`

- [x] **3. La carte 03 ne tient pas en 5 minutes, et elle échoue après la carte 01**
  - **Fait** : France pré-déployée (`gh workflow run deploy -f location=francecentral`) à J-1 et dans la remise à zéro ; carte 03, setup, dry-run et README mis à jour, réplique de Christophe ajoutée. **Reste** : mesurer la durée de la bascule au dry-run.
  - **Problème** : elle crée tout en France (Foundry, modèle, plan, Web App, code) : probablement 8 à 15 minutes. Et après la carte 01, l'app française passe en identité managée avec un rôle tout juste créé : la propagation des droits prend plusieurs minutes, donc des 401/403.
  - **Correction** : **pré-déployer la France la veille** (*warm standby*). À la carte, le pipeline n'y pousse que l'état courant : rapide, et le rôle existe déjà. Adapter le discours de la carte 03 : une région de reprise prête, c'est une vraie pratique.
  - **Fichiers** : `coulisses/run.md` (carte 03, J-1), `coulisses/setup.md`, `coulisses/dry-run.md` (dry-run 4), `README.md` (carte 03)

- [x] **4. Le repli de la carte 04 arrive trop tard**
  - **Fait** : aucune nouvelle tentative sur le principal quand un repli existe (2 sinon), délai réseau de 30 s. **Reste** : vérifier à la compilation que `RetryPolicy` et `NetworkTimeout` existent dans la version retenue d'`Azure.AI.OpenAI`.
  - **Problème** : le client Azure réessaie déjà les 429 en respectant le délai demandé par Azure (jusqu'à plusieurs dizaines de secondes). `FallbackChatClient` ne prend le relais qu'après ces tentatives : les requêtes restent bloquées, et `charge.ps1` (60 s de délai) compte des non-réponses.
  - **Correction** : aucune nouvelle tentative sur le client principal quand un repli est configuré (politique de retry à 0 dans les options du client Azure).
  - **Fichiers** : `src/ChatClients.cs`

---

## Importants

- [ ] **5. Le crédit de la souscription**
  - **Constat (dry-run du 27 novembre)** : la souscription est une **Microsoft Azure Sponsorship** (« ACL - Microsoft Azure Sponsorship »), pas une Visual Studio Enterprise. L'hypothèse des 150 $/mois ne tient plus.
  - **Problème** : deux régions en P0v3, plus les répétitions, peuvent épuiser le crédit. Sur un Sponsorship aussi, crédit épuisé = souscription désactivée.
  - **À faire** : vérifier le solde et la date de fin du Sponsorship ; supprimer la France après chaque répétition ; surveiller le crédit jusqu'au 3 décembre. Vérifier aussi que ce type d'abonnement accepte les budgets de la carte 05.
  - **Qui** : Christophe (accès au compte)

- [ ] **6. PIM pour la carte 07**
  - **Problème** : PIM demande une licence Entra ID P2 sur le tenant, probablement absente d'un tenant Visual Studio.
  - **À faire** : vérifier la licence. Sinon, remplacer la preuve PIM par une autre (rôle minimal attribué en CLI, par exemple).
  - **Qui** : Christophe

- [x] **7. Le test de fumée ne teste pas l'app**
  - **Fait** : la page, `/api/status` et une vraie question, 12 essais de 10 s ; un 429 passe avec un avertissement.
  - **Problème** : il vérifie `GET /`, la page statique, qui répond 200 même si le modèle est en panne. Le « dernier run vert » ne prouve rien.
  - **Correction** : tester aussi `GET /api/status` et une vraie question sur `POST /api/chat`.
  - **Fichiers** : `.github/workflows/deploy.yml`

- [ ] **8. La remise à zéro efface du travail**
  - **Problème** : `git reset --hard etat-build` puis le push forcé suppriment tout ce qui a été commité après le tag (correctifs d'Adrien, programme dans `Prompts.cs`…).
  - **Correction** : retaguer `etat-build` après chaque changement voulu, ou remettre à zéro en annulant seulement les commits des cartes.
  - **Fichiers** : `coulisses/run.md` (fin), `coulisses/setup.md` (étape 6)

- [x] **9. `check-quota.ps1` vérifie le repli à la mauvaise capacité**
  - **Fait** : lit les défauts de `main.bicep` puis le bicepparam, vérifie chaque modèle à sa capacité, et compare à la limite (un déploiement déjà en place ne fait plus échouer le contrôle).
  - **Problème** : il vérifie `gpt-4.1-nano` à capacité 1, alors que la carte 04 le déploie à 10 (`fallbackModelCapacity`). Il peut dire OK pendant que la carte échoue.
  - **Correction** : vérifier le repli avec sa propre capacité.
  - **Fichiers** : `coulisses/scripts/check-quota.ps1`

- [x] **9 bis. `check-quota.ps1` disait « MANQUE » partout**
  - **Fait** : Azure nomme le quota `OpenAI.DataZoneStandard.gpt4.1-mini` (sans tiret après `gpt`) ; le script accepte maintenant les deux orthographes.

- [ ] **9 ter. Le tag `etat-build` n'existe pas**
  - **Problème** : le dry-run 1, le retour entre deux cartes et la remise à zéro partent de `etat-build`. `git describe --tags` ne trouve aucun tag.
  - **À faire** : poser le tag une fois le piège de la carte 07 en place (point 9 quater), et le pousser.
  - **Qui** : Christophe

- [ ] **9 quater. Le piège de la carte 07 n'est pas posé, et la carte ne peut pas marcher en l'état**
  - **Problème** : `devOwnerPrincipalId = ''` dans `main.bicepparam` : personne n'est Owner sur le groupe de ressources (contrôle 0.8 rouge). Et surtout, Adrien et Christophe sont **Owner de la souscription** : même après la parade, Adrien reste Owner par héritage, donc la vérification « Adrien n'est plus Owner » échouera.
  - **À faire** : décider qui joue « Adrien » dans la carte. Par exemple, un compte de démo dédié, sans droit sur la souscription, dont l'object id va dans `devOwnerPrincipalId`.
  - **Qui** : Christophe et Adrien

- [ ] **10. Le verrou de la carte 08 peut casser le build en direct**
  - **Problème** : `NuGetAuditMode all` avec NU1901 à NU1904 en erreurs bloque sur **n'importe quel** package vulnérable, y compris les packages en préversion.
  - **À faire** : poser le verrou une fois en local dès maintenant, pendant la mise à jour des packages, et vérifier que seul `Newtonsoft.Json` le fait échouer.
  - **Qui** : Adrien

- [ ] **11. L'app n'a jamais été compilée**
  - **À faire** : mettre à jour les packages et compiler (`setup.md`, étape 2), vérifier `AsIChatClient()` et que les erreurs 429 et 400 du modèle remontent bien en `ClientResultException`. Le job `verify` compile désormais à chaque push.
  - **Qui** : Adrien

---

## Mineurs

- [ ] **12.** `setup.md` donne `coulisses/qr/QR_*.png`, alors que les fichiers sont dans `coulisses/`.
- [ ] **13.** Anciens noms à corriger : `cd devday-chaos` (`run.md`), `gh repo create devday-chaos` et `devday-chaos-infra.zip` (`setup.md`). Le repo s'appelle `devday-2026`.
- [ ] **14.** Une réponse bloquée par le filtre côté réponse arrive en 200 avec un texte vide : la page affiche « Erreur 200 ». Afficher un message à la place (`src/Program.cs`).
- [ ] **15.** `/api/export` montre à tout le monde les 20 dernières questions de la salle. Ne pas le projeter sans regarder ; éventuellement tronquer les questions.
- [ ] **16.** Une requête sans `X-User` n'est jamais limitée : n'importe qui contourne la limite de la carte 04. Plutôt un point à faire relever par Mario qu'un bug.
- [ ] **17.** Carte 05 : l'option « modèle plus petit » (`gpt-4.1-nano`) entre en conflit avec le repli si la carte 04 est passée (deux déploiements du même nom).
- [ ] **18.** Un changement d'app setting **redémarre** l'app quelques secondes : nuancer « l'app relit ses réglages à chaque requête » dans la carte 08 (`run.md`, `dry-run.md`).
- [ ] **18 bis.** Le poste de Christophe n'a pas le SDK .NET : `dotnet list … --vulnerable` (contrôle 0.8, carte 08) et la vérification locale du verrou ne passent pas. L'installer avant la carte 08, ou faire ces contrôles sur le poste d'Adrien.
- [ ] **18 ter.** Le contrôle 0.6 vise moins de 4 min, mais les deux derniers runs ont pris 4 min 7 s et 5 min 1 s. Le point 19 ci-dessous en gagne un peu ; chercher l'étape la plus lente dans le run.
- [ ] **19.** Le pipeline redéploie tout à chaque push, même pour la doc : ajouter un `paths-ignore` sur `coulisses/**` et `**.md` (`.github/workflows/deploy.yml`).

---

## Déjà suivi ailleurs

- Les décisions ouvertes du `README.md` : le tirage, le baromètre, le chrono à l'écran, la projection du repo, le programme du DevDay dans `src/Prompts.cs`.
- Le deck : conducteur à caler sur le déroulé de 45 minutes.
