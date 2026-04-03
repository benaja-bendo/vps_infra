# VPS Infrastructure — Ansible

Projet Ansible pour configurer un serveur VPS Ubuntu avec Docker et les services nécessaires (Traefik, Portainer, PostgreSQL, Adminer, MinIO, Dozzle).

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
    ├── traefik/             # Reverse proxy + TLS (Let's Encrypt)
    ├── portainer/           # Interface de gestion Docker
    ├── postgres/            # Base de données PostgreSQL
    ├── adminer/             # Interface web PostgreSQL
    ├── minio/               # Stockage objet compatible S3
    └── dozzle/              # Viewer de logs Docker
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
ansible-playbook playbook.yml --tags traefik
ansible-playbook playbook.yml --tags portainer
ansible-playbook playbook.yml --tags postgres
ansible-playbook playbook.yml --tags adminer
ansible-playbook playbook.yml --tags minio
ansible-playbook playbook.yml --tags dozzle
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

---

## Historique des modifications

### [Mise à jour Récente] - Intégration RabbitMQ et MinIO pour l'architecture microservices

Afin d'assurer le bon fonctionnement de l'application Laravel (Tableau de Bord) et du worker Python (Extraction) en production sur le VPS, l'infrastructure a été mise à jour :

1. **Nouveau rôle RabbitMQ** (`roles/rabbitmq`) :
   - Déploiement de `rabbitmq:4-management`.
   - Injection de `rabbitmq.conf` et `definitions.json` pour préconfigurer automatiquement :
     - Les files d'attente : `pdf_extraction_tasks`, `pdf_extraction_status` et la Dead Letter Queue (DLQ) `pdf_extraction_tasks_dlq`.
     - L'exchange `pdf_extraction_tasks_dlx` (type `direct`).
     - Le binding de la DLQ avec la routing key `dead_letter`.
   - Interface d'administration accessible via `rabbitmq.{{ domain }}` (port 15672).

2. **Mise à jour du rôle MinIO** (`roles/minio`) :
   - Ajout d'un container éphémère `minio-createbuckets` (utilisant l'image `minio/mc`).
   - Création automatique des buckets au démarrage : `pdfs`, `extractions` et `mibeko-documents`.
   - Configuration de la politique d'accès publique pour `mibeko-documents` afin que les documents puissent être servis par Laravel si nécessaire.

3. **Mise à jour du Playbook et Variables** :
   - Ajout de `rabbitmq` dans `playbook.yml`.
   - Ajout des variables `rabbitmq_user` et `rabbitmq_password` dans `group_vars/vps.example.yml`.

4. **Script de Test de Connexion** :
   - Ajout de `test_connections.py` pour vérifier facilement l'accès local à RabbitMQ (pika) et MinIO (minio) depuis le VPS.
