# VPS Infrastructure — Ansible

Projet Ansible pour configurer un serveur VPS Ubuntu avec Docker, les garde-fous de l'hôte et les services nécessaires (Traefik, Portainer, PostgreSQL, Adminer, MinIO, MinerU, Dozzle, Umami).

---

## Table des matières

1. [Prérequis système](#prérequis-système)
2. [Installation rapide (première fois)](#installation-rapide-première-fois)
3. [Reprendre après un clone GitHub](#reprendre-après-un-clone-github)
4. [Structure du projet](#structure-du-projet)
5. [Configuration](#configuration)
6. [Utilisation](#utilisation)
7. [Commandes utiles](#commandes-utiles)
8. [Sécurité](#sécurité)

---

## Prérequis système

Avant de commencer, tu dois avoir sur ta machine locale :

| Outil | Version minimale | Vérification |
|-------|-----------------|--------------|
| Python | >= 3.9 | `python3 --version` |
| pip | >= 22 | `pip3 --version` |
| SSH | – | `ssh -V` |

> **macOS** : Python 3.9+ est disponible via `brew install python@3.11` ou sur [python.org](https://python.org).  
> **Linux/Ubuntu** : `sudo apt install python3 python3-pip python3-venv`

---

## Installation rapide (première fois)

### 1. Cloner le projet

```bash
git clone <url-du-repo>
cd vps_infra
```

### 2. Lancer le script de setup

```bash
bash setup-env.sh
```

Ce script fait automatiquement :
- Vérifie que Python >= 3.9 est disponible
- Crée un environnement virtuel Python isolé dans `./venv/`
- Met à jour `pip` à la dernière version
- Installe toutes les dépendances Python listées dans `requirements.txt`
  - `ansible-core`
  - `docker` (SDK Python pour community.docker)
  - `ansible-lint`, `yamllint` (outils de qualité)
  - `paramiko` (connexions SSH avancées)
- Installe les collections Ansible Galaxy listées dans `requirements.yml`
  - `community.docker`
  - `community.general`

### 3. Activer l'environnement

```bash
source venv/bin/activate
```

> **Important** : tu dois activer l'environnement virtuel **à chaque nouvelle session de terminal** avant d'utiliser les commandes Ansible.

### 4. Configurer l'inventaire

```bash
cp inventory.example.ini inventory.ini
```

Édite `inventory.ini` avec l'IP réelle de ton VPS :

```ini
[vps]
my_server ansible_host=185.XXX.XXX.XXX ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/id_ed25519
```

---

## Reprendre après un clone GitHub

> **Scénario** : tu as poussé le projet sur GitHub depuis une machine et tu le récupères sur une autre (ou après avoir supprimé ton venv).

### Étapes complètes

```bash
# 1. Cloner le repo
git clone <url-du-repo>
cd vps_infra

# 2. Recréer l'environnement virtuel et tout installer
bash setup-env.sh

# 3. Activer l'environnement
source venv/bin/activate

# 4. Configurer l'inventaire (non versionné sur GitHub)
cp inventory.example.ini inventory.ini
# → Édite inventory.ini avec l'IP de ton VPS

# 5. Tester la connexion
ansible vps -m ping

# 6. Lancer le playbook
ansible-playbook playbook.yml
```

### Si l'environnement est corrompu ou obsolète

```bash
bash setup-env.sh --reset
```

L'option `--reset` supprime complètement le dossier `venv/` avant de le recréer proprement.

---

## Structure du projet

```
vps_infra/
├── setup-env.sh             # ← Script de setup de l'environnement (à lancer en premier)
├── requirements.txt         # Dépendances Python (ansible-core, docker SDK, lint…)
├── requirements.yml         # Collections Ansible Galaxy
├── ansible.cfg              # Configuration Ansible
├── inventory.example.ini    # Modèle d'inventaire (versionné)
├── inventory.ini            # Inventaire réel (NON versionné — dans .gitignore)
├── playbook.yml             # Playbook principal
└── roles/
    ├── setup/               # Configuration de base Ubuntu (SSH, Docker, firewall)
    ├── host_guardrails/     # Alerte d'espace disque, isolée du dist-upgrade de setup
    ├── traefik/             # Reverse proxy + TLS (Let's Encrypt) + middlewares partagés (provider file)
    ├── portainer/           # Interface de gestion Docker
    ├── postgres/            # Base de données PostgreSQL
    ├── adminer/             # Interface web PostgreSQL
    ├── minio/               # Stockage objet compatible S3
    ├── corpus_backup/       # Sauvegarde MinIO hors site, sans suppression répliquée
    ├── mineru/              # Serveur MinerU (extraction PDF → MD/JSON, CPU)
    ├── dozzle/              # Viewer de logs Docker
    └── umami/               # Analytics self-hosted (stats.<domain>)
```

---

## Configuration

### Variables d'environnement importantes

Chaque rôle dispose de ses propres variables dans `roles/<role>/vars/main.yml`.  
Les variables sensibles sont à placer dans `group_vars/vps.yml` (non versionné).

| Variable | Description | Exemple |
|---|---|---|
| `domain` | Domaine principal du serveur | `mibeko.com` |
| `traefik_acme_email` | Email pour Let's Encrypt | `admin@mibeko.com` |
| `postgres_password` | Mot de passe PostgreSQL | voir Vault |
| `minio_root_user` | Utilisateur root MinIO | `minioadmin` |
| `minio_root_password` | Mot de passe root MinIO | voir Vault |
| `host_guardrails_enabled` | Déploie le timer d'alerte disque sans rejouer `setup` | `false` |
| `host_guardrails_disk_healthcheck_url` | Ping HTTPS dédié à l'espace disque | voir Healthchecks.io |
| `corpus_backup_enabled` | Déploie la commande et les unités de sauvegarde, sans lancer de copie | `false` |
| `corpus_backup_timer_enabled` | Active le lancement nocturne après validation du premier miroir | `false` |
| `corpus_backup_source_access_key` | Compte MinIO dédié, limité à la lecture du corpus | voir Vault |
| `corpus_backup_offsite_endpoint` | Endpoint S3 du conteneur Infomaniak versionné | `https://s3.pub1.infomaniak.cloud` |
| `corpus_backup_immutable_patterns` | Préfixes dont la disparition côté source fait échouer `verify` | les deux racines `source/` |
| `corpus_backup_acknowledged_orphans` | Disparitions instruites, encore affichées mais non bloquantes | `[]` |
| `umami_db_password` | Mot de passe du user PostgreSQL dédié Umami (sans caractères spéciaux d'URL) | `openssl rand -hex 16` |
| `umami_app_secret` | `APP_SECRET` Umami (signature des sessions) | `openssl rand -hex 32` |

### Créer le fichier group_vars/vps.yml

```bash
cp group_vars/vps.yml.example group_vars/vps.yml  # si disponible
# ou créer manuellement :
cat > group_vars/vps.yml <<EOF
domain: "ton-domaine.com"
traefik_acme_email: "ton@email.com"
postgres_password: "ton_mot_de_passe"
minio_root_user: "minioadmin"
minio_root_password: "ton_mot_de_passe_minio"
EOF
```

---

## Utilisation

### Activer l'environnement (obligatoire à chaque session)

```bash
source venv/bin/activate
```

Pour désactiver :

```bash
deactivate
```

### Vérifier la connexion au VPS

```bash
ansible vps -m ping
```

### Déploiement complet

```bash
ansible-playbook playbook.yml
```

### Déployer un rôle spécifique (via tags)

```bash
ansible-playbook playbook.yml --tags setup
ansible-playbook playbook.yml --tags host_guardrails
ansible-playbook playbook.yml --tags traefik
ansible-playbook playbook.yml --tags portainer
ansible-playbook playbook.yml --tags postgres
ansible-playbook playbook.yml --tags adminer
ansible-playbook playbook.yml --tags minio
ansible-playbook playbook.yml --tags corpus_backup
ansible-playbook playbook.yml --tags mineru
ansible-playbook playbook.yml --tags dozzle
ansible-playbook playbook.yml --tags umami
```

### Mode dry-run (simulation sans modification)

```bash
ansible-playbook playbook.yml --check --diff
```

---

## Commandes utiles

```bash
# Vérifier les versions installées
ansible --version
ansible-lint --version

# Linter le playbook
ansible-lint playbook.yml

# Valider la syntaxe uniquement
ansible-playbook playbook.yml --syntax-check

# Lister les hosts disponibles
ansible-inventory --list

# Mettre à jour les dépendances Python
pip install --upgrade -r requirements.txt

# Mettre à jour les collections Galaxy
ansible-galaxy collection install -r requirements.yml --upgrade

# Recréer complètement l'environnement
bash setup-env.sh --reset
```

---

## Sécurité

- `inventory.ini` est dans `.gitignore` (contient l'IP réelle du VPS)
- `group_vars/vps.yml` est dans `.gitignore` (contient les mots de passe)
- Le dossier `venv/` est dans `.gitignore` (jamais poussé sur GitHub)

### Gérer les secrets avec Ansible Vault (recommandé en production)

```bash
# Chiffrer une valeur
ansible-vault encrypt_string 'mon_mot_de_passe' --name 'postgres_password'

# Chiffrer un fichier entier
ansible-vault encrypt group_vars/vps.yml

# Lancer un playbook avec Vault
ansible-playbook playbook.yml --ask-vault-pass

# Ou avec un fichier de mot de passe (à ajouter dans .gitignore)
echo "mon_vault_password" > .vault_pass
chmod 600 .vault_pass
ansible-playbook playbook.yml --vault-password-file .vault_pass
```

## Accès local à la base de données (PostgreSQL)

Pour des raisons de sécurité, le port 5432 de PostgreSQL n'est pas exposé publiquement sur internet. Il est uniquement accessible localement sur le VPS (`127.0.0.1`). 

Pour vous connecter à la base de données depuis votre machine locale (Mac/PC) avec votre outil préféré (DataGrip, DBeaver, TablePlus, etc.), vous devez créer un **Tunnel SSH**.

### Procédure

1. **Ouvrez un terminal** sur votre machine locale et exécutez la commande suivante :
   ```bash
   ssh -N -L 5432:127.0.0.1:5432 ubuntu@185.143.102.169
   ```
   *Note : Laissez ce terminal ouvert pendant votre session. Il transfère de manière sécurisée le trafic du port 5432 de votre ordinateur vers le port 5432 du VPS.*

2. **Configurez votre client de base de données** avec ces paramètres :
   - **Hôte** : `localhost` (ou `127.0.0.1`)
   - **Port** : `5432`
   - **Utilisateur / Mot de passe** : Ceux définis dans votre configuration (ex: fichier `group_vars/vps.yml`).

3. Une fois votre travail terminé, fermez simplement le tunnel en tapant `Ctrl+C` dans le terminal.

## Accès local à MinIO (API S3 + Console)

Comme PostgreSQL, MinIO n'expose pas ses ports publiquement. Les ports 9000 (API S3) et 9001 (Console) sont accessibles uniquement en local sur le VPS (`127.0.0.1`).

> **Depuis le 13/08/2026 seulement.** Cette phrase était fausse avant cette date : les
> ports étaient bien liés à `127.0.0.1`, mais Traefik routait par ailleurs
> `minio.<domain>` et `s3.<domain>` **sans authentification**, en joignant le
> conteneur par le réseau Docker. Ces routeurs ont été retirés (voir
> `docs/decisions.md` et l'audit `docs/_archive/2026-08-13-audit-vps-infrastructure.md`).
> Ne pas les rétablir : le bucket porte l'intégralité du corpus.

### Procédure

1. **Ouvrez un terminal** sur votre machine locale et démarrez un tunnel SSH :
   ```bash
   ssh -N -L 9000:127.0.0.1:9000 -L 9001:127.0.0.1:9001 ubuntu@185.143.102.169
   ```

2. **Accédez à la console MinIO** :
   - URL : `http://localhost:9001`
   - Identifiants : `minio_root_user` / `minio_root_password` (dans `group_vars/vps.yml`)

3. **Utilisez l'API S3 en local** :
   - Endpoint : `http://localhost:9000`
   - Exemple avec MinIO Client (`mc`) :
     ```bash
     mc alias set local http://localhost:9000 <minio_root_user> <minio_root_password>
     mc ls local
     ```

4. Pour arrêter le tunnel : `Ctrl+C`.

## Protection du disque et rotation des logs Docker

Chaque service Docker versionné fixe le pilote `json-file` à **20 Mio par
fichier et 3 fichiers**. La borne maximale est donc de 60 Mio par conteneur,
au lieu d'un fichier JSON sans limite. Le réglage est porté par chaque Compose,
pas par `/etc/docker/daemon.json` : il s'applique quand le conteneur est recréé
et ne nécessite aucun redémarrage global du daemon Docker.

Les applications (`mibeko-dashboard`, `mibeko-python`, `mibeko-front`,
`mibeko-site`) appliquent le réglage à leur prochain déploiement CI. Les
services de ce dépôt l'appliquent au rejeu de leur rôle. Les rôles doivent être
rejoués séparément : `postgres` retire puis recrée le conteneur et coupe
brièvement toute la plateforme ; `traefik` coupe brièvement le routage ; `minio`
coupe brièvement le stockage. Ne jamais les grouper sous une autorisation
générique.

L'alerte disque est un rôle indépendant de `setup`, car `setup` lance un
`apt upgrade: dist` sans rapport avec ce garde-fou. Créer un check
Healthchecks.io dédié, puis renseigner uniquement dans `group_vars/vps.yml` :

```yaml
host_guardrails_enabled: true
host_guardrails_remove: false
host_guardrails_disk_warning_percent: 80
host_guardrails_disk_critical_percent: 90
host_guardrails_disk_healthcheck_url: "https://hc-ping.com/<uuid-dedie>"
host_guardrails_journald_max_use: "500M"
```

Toutes les cinq minutes, `mibeko-disk-guard.timer` mesure la partition racine.
Sous 80 %, il envoie un ping normal. À partir de 80 %, puis de 90 %, il journalise
respectivement `warning` ou `critical`, appelle `/fail` et fait échouer le service
oneshot. Le même check signale aussi l'absence de ping si le VPS ou le timer
s'arrête. Ne pas réutiliser l'URL de sauvegarde du corpus : un incident disque ne
doit pas changer l'état du contrôle de sauvegarde.

Le même rôle dépose aussi une dérogation journald,
`/etc/systemd/journald.conf.d/mibeko-disk-guard.conf`, qui fixe
`SystemMaxUse={{ host_guardrails_journald_max_use }}` (défaut `500M`) et
redémarre `systemd-journald` pour l'appliquer. Le vacuum de l'incident du
10/08 (`mibeko-dashboard#30`) était ponctuel ; cette limite est permanente et
survit à un redémarrage du VPS.

Déploiement humain, opération Classe 2 :

```bash
# Simulation : connexion production, aucune écriture.
ansible-playbook playbook.yml --tags host_guardrails --check --diff

# Application après revue du diff.
ansible-playbook playbook.yml --tags host_guardrails

# Vérification — alerte disque.
systemctl status mibeko-disk-guard.timer --no-pager
systemctl start mibeko-disk-guard.service
journalctl -u mibeko-disk-guard.service --since today --no-pager

# Vérification — plafond journald.
journalctl --disk-usage
systemctl status systemd-journald --no-pager
```

Le test réel du canal d'alerte consiste à relever temporairement le seuil
d'avertissement **au-dessus** de l'usage courant pour le ping sain, puis à le
placer **au-dessous** de l'usage courant pour provoquer `/fail`; remettre ensuite
80/90 et rejouer le rôle. Chaque changement est une opération distincte et doit
être autorisé comme telle.

Retour arrière : mettre `host_guardrails_enabled: false` et
`host_guardrails_remove: true`, puis rejouer uniquement le tag
`host_guardrails`. Cela arrête le timer, retire la dérogation journald (retour
au réglage par défaut de l'image, redémarrage de `systemd-journald` compris) et
retire les autres fichiers, sans toucher à Docker ni aux données. Pour la
rotation des logs, revenir sur le Compose du service concerné et le
redéployer ; les fichiers de logs déjà tournés ne sont jamais supprimés par le
playbook.

## Sauvegarde hors site du corpus MinIO

Le rôle `corpus_backup` copie les objets un par un vers un conteneur Infomaniak
Object Storage distinct. Il ne construit aucun ZIP et sa consommation mémoire ne
dépend donc pas de la taille totale du corpus.

La cible est une sauvegarde, pas un miroir destructif : la commande emploie
`mc mirror --overwrite --retry`, **jamais `--remove`**. Un objet disparu de la
source reste ainsi récupérable hors site. Le conteneur distant doit en plus avoir
le versionnage Swift activé avant le premier transfert, afin de conserver les
versions précédentes d'un objet écrasé.

Préconditions, à satisfaire manuellement avant tout déploiement :

1. créer dans MinIO un compte dédié qui ne possède que `ListBucket`,
   `GetBucketLocation`, `GetObject` et `GetObjectTagging` sur
   `mibeko-documents` ; la policy prête à importer est
   `roles/corpus_backup/files/minio-corpus-backup-readonly-policy.json`, et le
   rôle refuse le compte racine ;
2. créer `mibeko-documents-backup` dans un projet Infomaniak distinct du VPS et
   y activer `X-Versions-Enabled: true` avec l'API Swift ;
3. générer des identifiants S3 dédiés et renseigner les variables commentées
   dans `group_vars/vps.example.yml`, uniquement dans le fichier gitignoré
   `group_vars/vps.yml` ;
4. choisir un PDF source immuable existant pour
   `corpus_backup_probe_object` : il est relu sur les deux stockages et comparé
   au SHA-256 après chaque cycle.

Le premier déploiement garde obligatoirement le timer désactivé :

```yaml
corpus_backup_enabled: true
corpus_backup_timer_enabled: false
```

L'opérateur déploie ensuite le rôle, puis contrôle le transfert depuis le VPS :

```bash
sudo mibeko-backup-corpus dry-run
sudo mibeko-backup-corpus pilot
sudo mibeko-backup-corpus run
sudo mibeko-backup-corpus verify
```

`pilot` sélectionne de manière déterministe les cinq premières clés source,
copie uniquement ces objets et compare leur SHA-256 sur les deux stockages. Il
est rejouable : un objet cible déjà identique n'est pas réécrit. Le miroir
complet ne doit être lancé qu'après la réussite de ce pilote.

`verify` échoue si une clé source manque à la cible, si une taille diverge ou si
la sonde restaurée n'a pas le même SHA-256. Ce contrôle de clé/taille ne remplace
pas un exercice de restauration : avant d'activer le timer, télécharger aussi un
PDF depuis Infomaniak dans un dossier temporaire et comparer son SHA-256 à la
source.

Les objets présents uniquement hors site sont conservés, mais plus tous égaux :

- sous un préfixe **régénérable** (`exports/`, `extractions/`), l'objet est
  compté et toléré. Un export PDF servi puis purgé, une extraction remplacée par
  une réingestion : la source a le droit d'oublier ce que la cible garde ;
- sous un préfixe **immuable** listé dans `corpus_backup_immutable_patterns`,
  `verify` échoue. Un PDF d'origine ne se régénère pas : s'il n'existe plus que
  hors site, ce n'est pas un historique mais une perte côté MinIO, et le silence
  d'une sauvegarde qui « couvre toute la source » masquerait exactement le
  sinistre qu'elle doit annoncer ;
- une ligne de comparaison que le script ne sait pas découper le fait échouer
  aussi : un format non lu n'est jamais réputé anodin.

Traiter un échec de ce type par la restauration de l'objet depuis la cible.
Quand la disparition est instruite et légitime, l'inscrire — clé exacte — dans
`corpus_backup_acknowledged_orphans` : elle reste affichée à chaque cycle mais
ne le fait plus échouer. Élargir les motifs immuables à la place reviendrait à
désarmer le garde-fou pour tout un préfixe.

> **Piège de compatibilité Infomaniak.** `mc stat` peut afficher
> `Anonymous: Enabled` parce que l'API S3 de Swift ne prend pas en charge les
> bucket policies S3. Ce champ ne fait pas foi. La confidentialité se prouve
> avec `swift stat` : `Read ACL` et `Write ACL` doivent être vides. Une cible
> publique porterait notamment `.r:*,.rlistings` dans `Read ACL`.

> Le même type de valeur trompeuse apparaît côté source avec le compte MinIO
> minimal : faute d'accès aux réglages administratifs du bucket, `mc stat` peut
> annoncer `Un-versioned`, `Anonymous: Enabled` et `0 object`. `mc du` fait foi
> pour l'inventaire courant ; le droit `GetObject` se prouve séparément en relisant
> la sonde SHA-256.

Après ce premier cycle seulement, passer `corpus_backup_timer_enabled` à `true`
et redéployer le rôle. Le timer est persistant (il rattrape un cycle manqué après
redémarrage) et s'exécute vers 04h20 avec un léger délai aléatoire :

```bash
systemctl list-timers mibeko-corpus-backup.timer
journalctl -u mibeko-corpus-backup.service --since today
```

Une URL de ping peut être renseignée dans `corpus_backup_healthcheck_url` pour
signaler les débuts, succès et échecs à un moniteur externe. Désactiver le timer
n'efface jamais la cible ni ses versions.

Retour arrière du seul déploiement hôte : mettre
`corpus_backup_enabled: false` et `corpus_backup_remove: true`, puis rejouer le
tag `corpus_backup`. Le rôle arrête le timer et retire la configuration root-only,
la commande et les unités `systemd`. Il ne supprime jamais les identités, les
buckets, les objets ni l'image Docker mise en cache. Remettre ensuite
`corpus_backup_remove: false` dans les variables.

## Accès local à Portainer

Portainer monte `/var/run/docker.sock` : y accéder équivaut à être **root sur l'hôte
entier**. Il n'est donc plus routé par Traefik depuis le 13/08/2026 (il répondait
jusque-là `200` sur l'internet public, protégé par le seul mot de passe applicatif).
Il n'est pas non plus sur le réseau `proxy` : aucun conteneur applicatif ne peut
l'atteindre.

```bash
ssh -N -L 9102:127.0.0.1:9002 ubuntu@185.143.102.169
```

Puis `http://localhost:9102`. Le port hôte est **9002** et non 9000, ce dernier étant
déjà pris par l'API S3 de MinIO.

---

## MinerU (extraction PDF → Markdown/JSON)

Service d'API qui transforme un PDF en Markdown + JSON structuré (backend
`pipeline`, **CPU**). Il remplace l'API SaaS MinerU : les projets d'ingestion
(worker Python, jobs Laravel) l'appellent en interne, sans coût ni quota.

> **Image maison.** Pas d'image officielle exploitable sans GPU : Ansible
> **construit** l'image `mibeko/mineru-cpu:<version>` directement sur le VPS à
> partir de `roles/mineru/files/Dockerfile`. La 1re construction est **longue**
> (torch + dépendances, plusieurs minutes) ; ensuite l'image est en cache.

### Déploiement

```bash
ansible-playbook playbook.yml --tags mineru
```

Le rôle, de façon **idempotente** :
1. crée le réseau interne `mineru_internal` ;
2. construit l'image **si** le tag `mineru_version` n'existe pas encore (un bump
   de version relance donc le build, sinon non) ;
3. **pré-télécharge les modèles** « pipeline » une seule fois dans le volume
   `mineru-models` (marqueur `/opt/docker/mineru/.models-downloaded`) — évite une
   1re requête de parsing très lente ;
4. démarre le serveur (`restart: unless-stopped`, healthcheck `/health`).

Re-jouer le playbook ne reconstruit rien et ne re-télécharge pas les modèles.

### Sécurité — service interne, jamais public

MinerU **n'a aucune authentification** et c'est un endpoint de calcul lourd : il
n'est **pas** routé par Traefik. Deux accès seulement :

| Depuis | Adresse | Usage |
|---|---|---|
| Un conteneur sur `mineru_internal` | `http://mineru:8000` | **prod** (worker/Laravel) |
| L'hôte VPS / tunnel SSH local | `http://127.0.0.1:8004` | debug, tests `curl` |

Aucun port n'est ouvert dans UFW (bind `127.0.0.1` + réseau Docker privé).

### Brancher un projet consommateur

**Cas 1 — le projet tourne en Docker sur le VPS** (recommandé) : attacher son
conteneur au réseau externe `mineru_internal` et viser le nom de service.

```yaml
# docker-compose.yml du projet consommateur (ex: mibeko-python)
services:
  worker:
    # …
    environment:
      MINERU_BACKEND: local
      MINERU_API_URL: "http://mineru:8000"   # nom du service sur mineru_internal
    networks:
      - mineru_internal
networks:
  mineru_internal:
    external: true
```

**Cas 2 — le projet tourne sur l'hôte** (php-fpm, binaire natif) : viser
`http://127.0.0.1:8004`.

**Cas 3 — depuis ta machine de dev** : tunnel SSH puis `http://localhost:8004`.

```bash
ssh -N -L 8004:127.0.0.1:8004 ubuntu@185.143.102.169
curl http://localhost:8004/health        # → {"status":"healthy", ...}
```

> Rappel API : toujours envoyer `backend=pipeline` (le backend par défaut exige un
> GPU). Pour le français (latin), **omettre** `lang_list` (le modèle `ch` lit le
> latin ; `fr` n'est pas accepté). Géré côté `mibeko-python`.

### Ressources

MinerU CPU est gourmand : prévoir **≥ 6 Go de RAM** disponibles, sinon risque
d'`OOMKilled` en plein parsing. `shm_size` est déjà à 2 Go. Si besoin de plafonner
la mémoire, renseigner `mineru_mem_limit` (ex: `"8g"`) — mais une limite trop
basse tue le parsing. Sur ce VPS (amd64 Linux), l'image tourne en natif (pas
d'émulation), donc plus vite que sur un Mac Apple Silicon.

### Maintenance

```bash
# Logs
docker compose -f /opt/docker/mineru/docker-compose.yml logs -f mineru

# Changer de version : éditer mineru_version (group_vars/vps.yml ou defaults),
# puis rejouer — l'image au nouveau tag est reconstruite automatiquement.
ansible-playbook playbook.yml --tags mineru

# Forcer un re-téléchargement des modèles : supprimer le marqueur puis rejouer.
ssh ubuntu@185.143.102.169 'rm -f /opt/docker/mineru/.models-downloaded'

# Repartir de zéro (modèles inclus) : supprimer le volume ET le marqueur,
# sinon le prochain déploiement sauterait le re-téléchargement.
ssh ubuntu@185.143.102.169 'cd /opt/docker/mineru && docker compose down -v && rm -f .models-downloaded'
```

---

## Umami (analytics self-hosted)

Analytics respectueux de la vie privée (sans cookies, sans données perso),
auto-hébergé sur `stats.<domain>` (ex : `stats.mibeko.fr`). Remplace un service
tiers type Google Analytics ; les fronts (site vitrine, corpus public, app pro)
chargent son `script.js` et lui envoient leurs pageviews.

### Architecture

| Élément | Détail |
|---|---|
| Image | `ghcr.io/umami-software/umami:postgresql-latest` (variante PostgreSQL) |
| Base de données | Base + user PostgreSQL **dédiés** (`umami` / `umami`), créés **de façon idempotente** par le rôle dans l'instance Postgres existante du VPS (conteneur `postgres`, réseau `db_internal`) |
| Réseaux | `proxy` (Traefik) + `db_internal` (accès Postgres) |
| Routage | Traefik, `Host(stats.<domain>)`, TLS Let's Encrypt (`myresolver`), **pas** de BasicAuth (Umami gère sa propre auth ; `/script.js` doit rester public) |
| Port interne | `3000` |

> Le rôle `umami` tourne **après** `postgres` dans le playbook : il attend que
> Postgres accepte les connexions (`pg_isready`), puis crée le user et la base
> dédiés s'ils n'existent pas (aucune donnée existante n'est touchée).

### Déploiement

```bash
# 1. Renseigner les secrets dans group_vars/vps.yml (voir vps.example.yml) :
#    umami_db_password: "<openssl rand -hex 16>"   # sans caractères spéciaux d'URL
#    umami_app_secret:  "<openssl rand -hex 32>"

# 2. Créer l'enregistrement DNS  stats.<domain>  →  IP du VPS (userAction)

# 3. Déployer le rôle
ansible-playbook playbook.yml --tags umami
```

> **⚠️ Mot de passe DB** : `umami_db_password` est injecté tel quel dans
> `DATABASE_URL` (`postgresql://umami:<pwd>@postgres:5432/umami`). Éviter les
> caractères réservés d'URL (`@ : / # ? espace…`) — utiliser un hex simple.

### Créer le site et récupérer le website-id

1. Ouvrir `https://stats.<domain>` et se connecter avec le compte par défaut
   (`admin` / `umami`) — **changer le mot de passe immédiatement** (Settings →
   Profile).
2. Aller dans **Settings → Websites → Add website**, renseigner le nom et le
   domaine (ex : `mibeko.fr`), puis **Save**.
3. Ouvrir le site créé → **Edit** : le **Website ID** (UUID) est affiché, ainsi
   qu'un snippet `<script>` avec `data-website-id`. C'est cet UUID que les fronts
   doivent utiliser.

### Brancher un front

Chaque front charge le script de tracking et pointe vers l'instance + le
website-id. Selon le bundler, exposer ces variables d'environnement :

> **Important** : la variable URL est l'**origine de base** de l'instance Umami
> (`https://stats.<domain>`), **sans** `/script.js`. Chaque front ajoute lui-même
> le suffixe `/script.js` (cf. `mibeko-front/vite.config.ts` et le `Layout.astro`
> du site vitrine). Ne pas y mettre l'URL complète du script, sinon le tag rendu
> pointerait vers `.../script.js/script.js` et ne collecterait rien.

| Front | Variable URL (base) | Variable ID |
|---|---|---|
| Vite (`mibeko-front`, app pro) | `VITE_UMAMI_URL` = `https://stats.<domain>` | `VITE_UMAMI_WEBSITE_ID` = `<website-id>` |
| Astro (`mibeko-site`, `PUBLIC_` exposé au client) | `PUBLIC_UMAMI_URL` = `https://stats.<domain>` | `PUBLIC_UMAMI_WEBSITE_ID` = `<website-id>` |

Exemple de balise rendue par le front :

```html
<script defer
        src="https://stats.mibeko.fr/script.js"
        data-website-id="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"></script>
```

> Le `script.js` d'Umami est servi **sans BasicAuth** (indispensable pour le
> tracking public), contrairement au dashboard Traefik / Dozzle / Adminer.

### Maintenance

```bash
# Logs
docker compose -f /opt/docker/umami/docker-compose.yml logs -f umami

# Mise à jour de l'image (bump du tag dans group_vars ou defaults, puis)
ansible-playbook playbook.yml --tags umami
```

---

## Traefik — middlewares partagés (provider file)

En plus du provider Docker (labels par conteneur), Traefik charge un **provider
file** (`/opt/docker/traefik/dynamic/`) pour les middlewares réutilisables entre
plusieurs services, y compris ceux dont le `docker-compose` vit **hors de ce
dépôt** (images GHCR déployées à part).

Middleware fourni :

| Nom | Rôle | Défaut |
|---|---|---|
| `upload-limit` | Plafonne la taille du corps de requête (`buffering.maxRequestBodyBytes`). Au-delà → `413`. À attacher aux routes d'upload (ex : `python.<domain>`). | ~120 Mo (`traefik_upload_limit_max_body_bytes`, cf. `roles/traefik/defaults/main.yml`) |

**Attacher le middleware** depuis les labels d'un compose applicatif (suffixe
`@file`, car il est défini par le provider file et non par un label Docker) :

```yaml
labels:
  - "traefik.http.routers.python.middlewares=upload-limit@file"
```

> **userAction** : les labels des services applicatifs (ex : `mibeko-python`)
> vivent dans leurs propres composes GHCR, **hors de ce dépôt**. Ce dépôt
> **définit** le middleware ; il faut **ajouter le label ci-dessus** au compose du
> service Python pour l'activer. Après déploiement de Traefik, le middleware est
> visible dans le dashboard (`traefik.<domain>`) sous `upload-limit@file`.

---

## Historique des modifications

### [20/09/2026] - Résolveur ACME TLS-ALPN-01 → HTTP-01 (CDN Cloudflare devant mibeko.fr, vps_infra#1)

`roles/traefik/templates/docker-compose.yml.j2` : le résolveur `myresolver`
passe de `--certificatesresolvers.myresolver.acme.tlschallenge=true` à
`acme.httpchallenge=true` + `acme.httpchallenge.entrypoint=web`.

**Pourquoi** : TLS-ALPN-01 se joue par une connexion TLS spéciale sur le port
443 de l'origine — derrière un CDN qui termine TLS (Cloudflare, activé ce
jour), ce défi n'atteint jamais Traefik et le certificat cesse de se
renouveler. HTTP-01 traverse le proxy tant que le HTTP en clair passe jusqu'à
l'origine (« Always Use HTTPS » désactivé côté Cloudflare, Traefik fait déjà
la redirection). `acme.json` est conservé : les certificats existants restent
valides, seul le mode de renouvellement change.

La chaîne complète (zone Cloudflare, Cache Rules, purge applicative, chaîne
d'IP `CF-Connecting-IP`) est documentée et **fait foi** dans
[`docs/infra/production.md`](../docs/infra/production.md) — ce dépôt ne porte
que le changement de résolveur, seul point qui touche l'Ansible.

### [Mise à jour Récente] - Ajout d'Umami (analytics) + middlewares Traefik partagés

1. **Rôle Umami** (`roles/umami`) :
   - Analytics self-hosted sur `stats.<domain>` (image officielle variante
     PostgreSQL), routé par Traefik avec TLS Let's Encrypt, **sans BasicAuth**
     (auth propre + `script.js` public).
   - Base + user PostgreSQL **dédiés** créés de façon idempotente dans l'instance
     Postgres existante (attente `pg_isready`, `CREATE USER/DATABASE` conditionnels).
   - Secrets `umami_db_password` / `umami_app_secret` dans `group_vars/vps.yml`
     (défauts non sensibles dans `roles/umami/defaults/main.yml`).
2. **Traefik — provider file** (`roles/traefik/defaults` + `dynamic-middlewares.yml.j2`) :
   - Chargement d'un provider file (`--providers.file.directory=/dynamic`) pour
     les middlewares partagés entre services (y compris composes GHCR hors dépôt).
   - Middleware `upload-limit` (~120 Mo) à attacher via `upload-limit@file` aux
     routes d'upload (ex : `python.<domain>`).

### [Mise à jour Récente] - Ajout du service MinerU (extraction PDF en self-hosted)

Ajout d'un rôle `mineru` pour héberger l'extraction PDF → Markdown/JSON sur le VPS,
sans dépendre de l'API SaaS MinerU :

1. **Rôle MinerU** (`roles/mineru`) :
   - Image CPU `mibeko/mineru-cpu` **construite sur le VPS** (backend `pipeline`,
     `linux/amd64`), version épinglée via `mineru_version`.
   - Réseau interne dédié `mineru_internal` ; service **non exposé** par Traefik
     (bind `127.0.0.1:8004` pour debug). Consommateurs → `http://mineru:8000`.
   - Pré-téléchargement idempotent des modèles dans le volume `mineru-models`.
   - Variables configurables dans `roles/mineru/defaults/main.yml` (surchargeables
     dans `group_vars/vps.yml`).


### [Mise à jour Récente] - Configuration MinIO pour l'architecture microservices

Afin d'assurer le bon fonctionnement de l'application Laravel (Tableau de Bord) et du worker Python (Extraction) en production sur le VPS, l'infrastructure a été mise à jour :

1. **Rôle MinIO** (`roles/minio`) :
   - Ajout d'un container éphémère `minio-createbuckets` (utilisant l'image `minio/mc`).
   - Création automatique des buckets au démarrage : `pdfs`, `extractions` et `mibeko-documents`.
   - Le bucket `mibeko-documents` est **privé** (`mc anonymous set none`) : les documents sont servis par Laravel via des URL signées sur l'endpoint interne, jamais en accès anonyme.

> ⚠️ **Ce conteneur `minio-createbuckets` ne fonctionne pas** (constaté le 13/08/2026).
> Il appelle `mc config host add`, commande **retirée** des versions récentes de `mc` :
> l'alias n'est jamais configuré. Il affiche pourtant « Bucket created successfully »
> pour `pdfs` et `extractions`, alors que le disque MinIO ne contient qu'un seul
> bucket, `mibeko-documents`. Ne pas se fier à sa sortie. Sans conséquence
> aujourd'hui — aucune application n'utilise `pdfs` ni `extractions` — mais à
> corriger (`mc alias set`) ou à retirer si on revient sur ce rôle.

> **Note (retrait RabbitMQ)** : le rôle `rabbitmq` et les variables `rabbitmq_*` ont été retirés. L'extraction PDF est désormais traitée de façon synchrone dans les jobs de la file Laravel (`ProcessDocumentExtraction` → MinerU), sans broker de messages.
