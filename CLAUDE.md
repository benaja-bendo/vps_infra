# CLAUDE.md — vps_infra

## ⚠️ Ce dépôt agit sur la PRODUCTION réelle
Provisioning Ansible du VPS Ubuntu qui héberge tout Mibeko. Il n'y a **ni staging, ni environnement de test** : un playbook joué ici touche la prod.

- **Ne jamais lancer un playbook de sa propre initiative.** Toute exécution demande une autorisation humaine explicite, **opération par opération** — une autorisation ne vaut jamais pour la suivante, ni pour « la même chose ailleurs ». Annoncer avant : la cible, l'effet attendu, ce qui redémarre, et comment revenir en arrière.
- `--check --diff` et `ansible vps -m ping` restent des **connexions à la production** : demander aussi.
- **La lecture des fichiers de ce dépôt est libre** — c'est le mode par défaut d'un agent ici : lire, expliquer, proposer un diff. Pas exécuter.
- Interdits absolus, **même autorisés** : `DROP` / `TRUNCATE` ; `DELETE` physique ; écrire ou supprimer dans MinIO ; rejouer un schéma SQL commençant par des `DROP TABLE … CASCADE` (c'est le cas de `mibeko-python/schema_postgres.sql`) ; publier du corpus par `UPDATE` SQL (la publication passe par l'API Laravel).
- Accès **diagnostic en lecture seule** à la prod (tunnels, rôle Postgres read-only, préflight) : `docs/infra/production.md` (dépôt `docs/`). C'est le point d'entrée normal pour « regarder » la production.

## Ce que ce dépôt fait — et ne fait pas
Il provisionne l'**infrastructure** : Traefik (+ TLS Let's Encrypt), PostgreSQL (pgvector), MinIO, MinerU, Portainer, Adminer, Dozzle, Umami. Il **ne déploie aucune application Mibeko** : l'API Laravel, le service Python, le site et le front sont livrés par la CI de leurs propres dépôts (image GHCR + compose déposé dans `/opt/docker/<app>`), **hors de ce dépôt**. Ajouter un label Traefik à un service applicatif se fait donc là-bas, pas ici.

## Structure et câblage
- `playbook.yml` (`hosts: vps`, `become: true`) : sa liste `roles:` est le **seul** câblage. Aucun `include_role`, `import_role`, `import_playbook` ni `include_tasks` nulle part — inutile de chercher un point d'entrée caché.
- Chaque rôle a un tag homonyme (`ansible-playbook playbook.yml --tags <rôle>`), et suit le même patron : créer `/opt/docker/<service>`, y templater un `docker-compose.yml`, lancer `community.docker.docker_compose_v2`.
- Exception volontaire : `host_guardrails` ne gère aucun Compose. Il installe le timer systemd d'alerte disque et le plafond `SystemMaxUse` de journald (`/etc/systemd/journald.conf.d/mibeko-disk-guard.conf`), et reste séparé de `setup`, dont le tag lancerait un `dist-upgrade` sans rapport.
- **`roles/cloudbeaver` est du code mort** : le rôle est **commenté** dans `playbook.yml`, donc jamais exécuté (ses fichiers subsistent, et `roles/setup` crée encore le dossier `/opt/docker/cloudbeaver`). Ne pas le décommenter sans décision explicite.
- Variables : `group_vars/vps.yml` (réel, **gitignoré**) ; `group_vars/vps.example.yml` (modèle versionné) ; `defaults/` seulement dans `traefik`, `mineru`, `umami`.

## Piège de précédence — `group_vars` gagne toujours
Les variables `mineru_*` (`mineru_version`, `mineru_port`, `mineru_model_source`, `mineru_mem_limit`) sont définies **à la fois** dans `roles/mineru/defaults/main.yml` **et** dans `group_vars/vps.yml`. Ansible fait gagner `group_vars` : **éditer les defaults n'a aucun effet**. Même piège latent pour `traefik_*` et `umami_*` si on les recopie dans `group_vars`. Toujours vérifier `group_vars/vps.yml` avant de conclure qu'une valeur est celle du rôle.

## Secrets — avertissement, à vérifier avant toute conclusion
Le `README.md` présente **Ansible Vault comme recommandé en production**, mais **il n'est utilisé nulle part** : aucun fichier vaulté, aucun `.vault_pass`, aucun `--vault-password-file` dans le dépôt ou `ansible.cfg`. `group_vars/vps.yml` porte donc en clair (sur disque ; le fichier est gitignoré, il n'est **pas** dans l'historique git) les identifiants Postgres, Portainer, MinIO, le hash du dashboard Traefik et les secrets Umami — et plusieurs mots de passe y valent littéralement `changeme` (Postgres, Portainer, MinIO root).

**Impossible de savoir depuis le dépôt si la production tourne réellement avec ces valeurs** : le fichier local peut être en retard sur le serveur. À vérifier auprès de l'utilisateur avant d'en tirer la moindre conclusion, et **ne jamais recopier ces valeurs** dans un rapport, un commit, un log ou un message.

## Pièges vérifiés dans les rôles
- **`--tags postgres` redémarre la base de production.** `roles/postgres/tasks/main.yml` supprime d'abord le conteneur `postgres` (`state: absent`, `keep_volumes: true`) avant de recomposer : les données survivent, mais toute la plateforme est coupée pendant l'opération. Ce n'est pas un rejeu inerte.
- **`--tags setup` fait un `apt upgrade: dist` du VPS entier**, plus réinstallation Docker, UFW et fail2ban. À traiter comme une opération de maintenance système, pas comme une remise en conformité anodine.
- **Hash BasicAuth Traefik** : le template applique `| replace('$', '$$')` (échappement docker-compose), donc la valeur de `traefik_dashboard_users` dans `group_vars` doit contenir des `$` **simples**. `vps.example.yml` montre des `$$` doublés — recopier l'exemple tel quel produit un hash cassé et un dashboard qui n'authentifie jamais.
- **MinIO et Portainer ne sont plus publiés du tout depuis le 13/08/2026.** Leurs routeurs Traefik ont été retirés (`docs/decisions.md`) : `minio.<domain>`, `s3.<domain>` et `portainer.<domain>` répondent désormais 404. Accès par tunnel SSH uniquement — MinIO sur `127.0.0.1:9000` (API) et `9001` (console), Portainer sur `127.0.0.1:9002`. **Ne jamais rétablir de route Traefik sur ces deux services, même derrière `authtraefik`** : Portainer monte `/var/run/docker.sock` (l'atteindre équivaut à être root sur l'hôte) et MinIO porte l'intégralité du corpus. Le dashboard Traefik, Adminer et Dozzle restent publiés derrière `authtraefik`.
  - **Piège à connaître avant de toucher au rôle `minio`** : le réseau `proxy` doit y rester. Ce n'est pas Traefik qui l'exige mais les applications — `mibeko-app`, `mibeko-queue`, `mibeko-scheduler` et `mibeko-python` joignent le stockage par `http://minio:9000` sur ce réseau. Le retirer couperait tout le stockage. À l'inverse, Portainer n'a plus besoin d'aucun réseau partagé et n'y est plus.
- **Le service `minio-createbuckets` est cassé et son journal est trompeur** (constaté le 13/08/2026). Il lance `mc config host add`, commande **retirée** des versions récentes de `mc` : l'alias n'est jamais configuré. Il affiche pourtant « Bucket created successfully » pour `pdfs` et `extractions`, alors que la vérité terrain (`docker exec minio ls /data/`) ne montre qu'un seul bucket, `mibeko-documents` — ces deux buckets n'ont jamais existé, et aucune application ne les utilise. Ne pas se fier à sa sortie. Correctif si on y revient : `mc alias set`, ou retrait pur et simple des deux buckets vestigiaux.
- **MinerU n'a aucune authentification** et c'est du calcul lourd : volontairement **non routé par Traefik** (bind `127.0.0.1:{{ mineru_port }}` + réseau interne `mineru_internal`, les consommateurs visent `http://mineru:8000`). Ne jamais lui ajouter un label Traefik.
- UFW n'ouvre que 22/80/443 ; Postgres, MinIO et MinerU passent par tunnel SSH.
- Plusieurs images sont en `:latest` (MinIO, Adminer, Dozzle, Portainer, Umami) mais les rôles utilisent `pull: missing` : un rejeu ne les met **pas** à jour silencieusement — en revanche un `docker compose pull` manuel sur le VPS, oui.
- **Dozzle v11 (25/09/2026) ajoute des comptes/réglages persistés dans `/data`, et des actions « start/stop/restart »/« shell » activables dans son assistant de configuration.** Le compose ne montait pas `/data` avant cette date : tout compte créé via l'onboarding Dozzle disparaissait à la prochaine recréation du conteneur (silencieux, pas d'erreur). Corrigé par l'ajout du volume nommé `dozzle_data:/data`. **Ne jamais activer « Actions et shell » dans cet assistant** : `docker.sock` étant un socket Unix, le flag `:ro` du bind mount n'empêche pas les appels d'écriture de l'API Docker (`send()`/`recv()` ignorent le mode lecture-seule du point de montage — ce n'est pas une frontière de sécurité, juste une hygiène de montage). Les activer donnerait donc à Dozzle le même accès root-équivalent sur l'hôte que celui refusé à Portainer plus haut, mais derrière un seul mot de passe BasicAuth partagé au lieu de comptes Portainer individuels.
- **Tout service Compose borne ses logs** avec `json-file`, `max-size: 20m`, `max-file: 3`. Conserver l'ancre `x-logging` et l'appliquer à chaque nouveau service, y compris les profils jetables : un seul conteneur sans limite suffit à rouvrir `mibeko-dashboard#30`. **Seule exception : Traefik** (`50m` × 10, `compress: "true"`, depuis le 23/09/2026), parce que son flux porte le journal d'accès et qu'à 20m × 3 il ne gardait qu'environ 36 h. Toute autre exception doit être bornée et consignée dans `docs/decisions.md` de la même façon.
- **Journal d'accès Traefik** : ne garde que trois en-têtes de requête, `Cf-Connecting-Ip`, `Cf-Ipcountry` et `User-Agent` ; tous les autres sont supprimés (`defaultmode=drop`). Ne jamais passer `defaultmode` à `keep`, ni ajouter `Authorization`, `Cookie` ou un en-tête de session : le journal est lisible par tunnel et via Dozzle. `request_Cf-Connecting-Ip` n'est une IP de visiteur fiable que si `ClientHost` appartient aux plages Cloudflare : sur `api`/`app`/`python` (hors proxy), le client écrit ce qu'il veut dans l'en-tête.
- Le rôle `mineru` ne reconstruit l'image que si le tag `mineru_version` est absent, et ne re-télécharge les modèles que si le marqueur `/opt/docker/mineru/.models-downloaded` manque. Un bump de version relance un build **long**.

## Dérives connues du README (le code fait foi)
`cp group_vars/vps.yml.example …` (le fichier s'appelle `group_vars/vps.example.yml`) ; « variables dans `roles/<role>/vars/main.yml` » (aucun dossier `vars/` n'existe) ; « politique d'accès **publique** pour `mibeko-documents` » alors que le compose applique `mc anonymous set none` (bucket privé, vérifié le 13/08/2026 : accès anonyme → 403 `AccessDenied`).

## Dérive dépôt ↔ production — vérifier, ne jamais supposer
Ce dépôt a **déjà été en avance sur la production**, et l'écart s'est révélé dangereux. Constaté le 13/08/2026 en comparant le compose déployé au template :

- Le compose de MinIO **en production** portait encore `mc anonymous set public myminio/mibeko-documents`, alors que le dépôt était passé à `set none` sans être rejoué. Un `--tags minio` joué à ce moment-là aurait rendu le corpus **anonymement lisible sur l'internet**. Résorbé par le déploiement du 13/08.
- Le conteneur Traefik en production **n'a pas** `--providers.file.directory=/dynamic` : le provider file ajouté au dépôt n'a jamais été déployé, donc le middleware `upload-limit` documenté dans le README **n'existe pas en production**.

Avant de conclure quoi que ce soit sur l'état réel d'un service, comparer le template au fichier déployé : `ansible-playbook playbook.yml --tags <rôle> --check --diff` affiche l'écart sans rien appliquer. Un `--check` reste une connexion à la production : demander l'autorisation. Corriger le README plutôt que d'aligner le code dessus.

## Conventions de travail
- Toute écriture autorisée en production est précédée d'un **dump frais** et livrée sous forme **rejouable** (playbook tagué ou script avec `--dry-run`), jamais en commande ad hoc.
- Décision structurante = une ligne datée dans `docs/decisions.md` (dépôt `docs/`, transverse aux 7 dépôts).
- Commits en français, `type(scope): titre court` à l'impératif, corps expliquant le **POURQUOI**. Un sujet cohérent par commit. **Jamais de commit sans l'accord explicite de l'utilisateur.**
