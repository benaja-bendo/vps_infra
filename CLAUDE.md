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
- **MinIO est bien exposé publiquement, contrairement à ce que suggère le README.** Les ports hôte sont en `127.0.0.1`, mais le compose déclare aussi des routeurs Traefik `minio.<domain>` (console) et `s3.<domain>` (API S3), en TLS et **sans BasicAuth** : seule la paire d'identifiants MinIO protège l'accès. Même remarque pour Portainer (`portainer.<domain>`, pas de middleware `authtraefik`, auth applicative uniquement) — alors que le dashboard Traefik, Adminer et Dozzle sont, eux, derrière `authtraefik`.
- **MinerU n'a aucune authentification** et c'est du calcul lourd : volontairement **non routé par Traefik** (bind `127.0.0.1:{{ mineru_port }}` + réseau interne `mineru_internal`, les consommateurs visent `http://mineru:8000`). Ne jamais lui ajouter un label Traefik.
- UFW n'ouvre que 22/80/443 ; Postgres, MinIO et MinerU passent par tunnel SSH.
- Plusieurs images sont en `:latest` (MinIO, Adminer, Dozzle, Portainer, Umami) mais les rôles utilisent `pull: missing` : un rejeu ne les met **pas** à jour silencieusement — en revanche un `docker compose pull` manuel sur le VPS, oui.
- Le rôle `mineru` ne reconstruit l'image que si le tag `mineru_version` est absent, et ne re-télécharge les modèles que si le marqueur `/opt/docker/mineru/.models-downloaded` manque. Un bump de version relance un build **long**.

## Dérives connues du README (le code fait foi)
`cp group_vars/vps.yml.example …` (le fichier s'appelle `group_vars/vps.example.yml`) ; « variables dans `roles/<role>/vars/main.yml` » (aucun dossier `vars/` n'existe) ; « politique d'accès **publique** pour `mibeko-documents` » alors que le compose applique `mc anonymous set none` (bucket privé). Corriger le README plutôt que d'aligner le code dessus.

## Conventions de travail
- Toute écriture autorisée en production est précédée d'un **dump frais** et livrée sous forme **rejouable** (playbook tagué ou script avec `--dry-run`), jamais en commande ad hoc.
- Décision structurante = une ligne datée dans `docs/decisions.md` (dépôt `docs/`, transverse aux 7 dépôts).
- Commits en français, `type(scope): titre court` à l'impératif, corps expliquant le **POURQUOI**. Un sujet cohérent par commit. **Jamais de commit sans l'accord explicite de l'utilisateur.**
