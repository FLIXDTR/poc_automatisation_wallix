# WALLIX Bastion sur PNETLab (VMware) — PoC d’automatisation (Terraform + Ansible)

Cette documentation décrit **ce qui a été mis en place** dans ce dépôt et **comment l’exécuter** pour :

1) **installer** un WALLIX Bastion à partir d’un ISO **dans PNETLab** (QEMU),
2) **le configurer automatiquement** via **Ansible** (API HTTPS WALLIX),
3) **valider** que tout fonctionne via des **smoke tests**,

… le tout sans dépendre de WSL/Hyper‑V sur Windows (pour éviter les conflits avec VMware Workstation/PNETLab).

> Important
> - Ce PoC vise un déploiement **reproductible** et **rapide**.
> - Il n’est pas une industrialisation “prod-ready” (HA, multi-env, rollback avancé, durcissement complet, etc.).

---

## 1) Concepts et vocabulaire (débutant)

- **ISO** : image disque d’installation (comme un DVD).
- **PNETLab** : plateforme de lab (proche EVE‑NG) qui lance des VMs via **QEMU**.
- **QEMU** : hyperviseur logiciel utilisé par PNETLab (disques `.qcow2`, overlays, etc.).
- **SSH** : accès terminal à distance (très pratique pour automatiser des actions système).
- **Terraform** : “Infra as Code” (décrit et applique un état, garde une **state**).
- **Ansible** : moteur d’automatisation via **playbooks** (tâches idempotentes).
- **API** : interface HTTPS pilotable par scripts (ici : API WALLIX).
- **Inventory Ansible** : fichier qui dit “sur quelle machine exécuter les playbooks” (IP/host).
- **Idempotent** : relancer un run ne casse pas la config ; si c’est déjà OK, ça ne change rien.

---

## 2) Architecture cible (ce qui parle à quoi)

### 2.1 Pourquoi une VM “runner” Linux ?

Sur Windows, deux options classiques existent pour exécuter Terraform/Ansible :

- Installer tous les outils “à la main” (Terraform, Ansible, ssh/scp, dépendances Python…) ;
- Utiliser WSL (Linux sous Windows).

Dans ce PoC, on a choisi une **VM Ubuntu “runner”** parce que :

- **WSL/Hyper‑V** peut casser ou perturber VMware Workstation/PNETLab (conflits de virtualisation) ;
- Beaucoup d’outils nécessaires sont “naturellement” Linux (sshpass, xorriso, etc.) ;
- Un runner dédié rend l’exécution **stable**, **isolée**, et **reproductible**.

### 2.2 Les 3 machines (niveaux)

1) **Ton PC Windows (VMware Workstation)**
   - Héberge les VMs.
   - Lance/arrête les VMs et donne accès console.

2) **VM “runner” Ubuntu (control plane)**
   - Contient tous les outils : Terraform, Ansible, Python, ssh/scp…
   - Exécute le workflow “1 commande”.
   - Accède au dépôt via un dossier partagé VMware (`/mnt/hgfs/WallixRepo`).

3) **VM PNETLab (fabrique)**
   - Stocke les labs : `/opt/unetlab/labs/...`
   - Stocke les images QEMU : `/opt/unetlab/addons/qemu/...`
   - Lance les VMs QEMU (dont WALLIX) et gère leurs overlays : `/opt/unetlab/tmp/<session>/<node>/...`

### 2.3 Pourquoi contrôler PNETLab en SSH ?

Le PoC pilote PNETLab **en SSH** (root) pour des actions système robustes :

- Upload de fichiers (ISO, `.unl`) via `scp`.
- Démarrage/arrêt/wipe des nodes via `unl_wrapper`.
- Commit QEMU (`qemu-img commit`) pour “figer” une installation en template.

Cela évite de dépendre de l’API web PNETLab (qui peut varier selon versions, captcha, sessions…).

---

## 3) Modes supportés dans ce dépôt

Le dépôt propose plusieurs chemins d’exécution, mais **ce document est centré sur PNETLab**.

- **Mode PNETLab** : `bash scripts/run-pnetlab.sh`
  - **Terraform obligatoire** : crée/maintient le lab PNET + construit/boot le bastion.
  - **Ansible obligatoire** : configure WALLIX via API.

- **Mode local** (hors PNETLab) : cible une VM WALLIX déjà installée (skip Terraform).
  - Utile pour configurer un bastion existant rapidement.

- **Mode vSphere** (PoC historique) : provisioning via vCenter/vSphere puis config Ansible.

Référence : `README.md`.

---

## 4) Pré-requis

### 4.1 Sur Windows

- VMware Workstation installé.
- Une VM PNETLab opérationnelle (avec accès réseau depuis le runner).

### 4.2 Dans la VM runner (Ubuntu)

On installe automatiquement :

- `terraform`
- `ansible`
- `python3` + utils
- `ssh`, `scp`, `sshpass`
- `xorriso` (patch ISO auto-boot)
- `jq`
- `open-vm-tools` (partage VMware HGFS)

Script : `scripts/runner/bootstrap-runner.sh`.

---

## 5) Mise en place du runner Ubuntu (recommandé)

### 5.1 Créer la VM runner depuis Windows

Commande (PowerShell) :

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\setup-runner-vm.ps1 -StartVm
```

Pendant l’installation Ubuntu :
- activer **Install OpenSSH server** (recommandé),
- créer un utilisateur (ex: `wallix` ou `runner`),
- terminer l’installation.

> Note : le runner n’a pas besoin de nested virtualization.

### 5.2 Installer les outils dans le runner

Dans Ubuntu (runner), depuis le dépôt partagé :

```bash
sudo bash ./scripts/runner/bootstrap-runner.sh
```

Ce script installe Terraform + Ansible + dépendances et tente de monter le share VMware :
- dépôt : `/mnt/hgfs/WallixRepo`

---

## 6) Configuration : fichier `secrets_pnetlab.env`

### 6.1 Copier le template

Dans le runner :

```bash
cp ./secrets_pnetlab.env.example ./secrets_pnetlab.env
```

Le fichier `secrets_pnetlab.env` est **ignoré par Git** (voir `.gitignore`).

### 6.2 Paramètres essentiels

#### Accès SSH PNETLab (obligatoire)

- `TF_VAR_pnet_ssh_host` : IP de la VM PNETLab
- `TF_VAR_pnet_ssh_user` : souvent `root`
- `TF_VAR_pnet_ssh_password` : mot de passe root (ou utiliser `TF_VAR_pnet_ssh_key_path`)
- `TF_VAR_pnet_tenant_id` : souvent `1`
- `TF_VAR_pnet_session_id` : souvent `1`

#### Chemins de labs (où Terraform écrit les `.unl`)

- `TF_VAR_pnet_lab_path` : exemple `User1/Wallix-Auto.unl`
- `TF_VAR_pnet_build_lab_path` : exemple `User1/Wallix-TemplateBuild.unl`

> Ce PoC **crée un lab séparé** (Wallix-Auto). Il ne modifie pas ton lab existant.

#### Réseau “MGMT” et découverte IP

- `TF_VAR_pnet_mgmt_network_name` : nom affiché dans le lab (ex: `MGMT`)
- `TF_VAR_pnet_mgmt_network_type` : réseau externe PNET (ex: `pnet0`)
- `TF_VAR_mgmt_subnet` : subnet à scanner (ex: `192.168.214.0/24`)

Terraform attend qu’un WALLIX réponde sur :
- `https://<ip>/api/version`

Donc **l’IP WALLIX doit être dans `TF_VAR_mgmt_subnet`**.

> Note (très courant) : selon comment le template WALLIX a été préparé, le Bastion peut être configuré avec une **IP statique** sur un autre sous-réseau (ex: `192.168.10.5/24`).
> - Dans ce cas, mets `TF_VAR_mgmt_subnet=192.168.10.0/24`.
> - Et assure-toi que **la machine qui exécute Terraform/Ansible peut joindre 192.168.10.0/24** (sinon tu ne pourras pas accéder à `https://192.168.10.5`).
>   - Sur Windows + VMware Workstation (VMnet8), le plus simple est d’ajouter une **IP secondaire** sur l’interface `VMware Network Adapter VMnet8` (ex: `192.168.10.1/24`) — commande `netsh`, nécessite un terminal en administrateur.

#### ISO et image QEMU

- `TF_VAR_wallix_iso_path` : chemin ISO (dans ce dépôt : `bastion-12.0.17.iso`)
- `TF_VAR_wallix_image_name` : nom du dossier QEMU sur PNETLab (ex: `linux-wallix-bastion-12.0.17`)
- `TF_VAR_wallix_disk_size` : ex `120G`

#### Credentials API WALLIX (Ansible)

- `WALLIX_API_USER` : souvent `admin`
- `WALLIX_API_PASSWORD` : mot de passe “bootstrap” (après install)
- `WALLIX_ADMIN_NEW_PASSWORD` : mot de passe final souhaité
- `WALLIX_VALIDATE_CERTS` : `false` si cert TLS auto-signé

---

## 7) Exécution “1 commande” (PNETLab)

Depuis le runner (dans le dépôt) :

```bash
bash ./scripts/run-pnetlab.sh
```

Le script :

1) charge `secrets_pnetlab.env`
2) `terraform init/fmt/validate/apply` dans `terraform/pnetlab`
3) génère l’inventaire Ansible : `ansible/inventory/generated/hosts.yml`
4) exécute :
   - `ansible/playbooks/bootstrap.yml`
   - `ansible/playbooks/configure.yml`
5) lance `scripts/smoke_test.py`

---

## 8) Détails : ce que fait Terraform (PNETLab)

Dossier : `terraform/pnetlab/`

### 8.1 Préparation de l’image (ISO + disque)

Script : `scripts/pnetlab/prepare_image.sh`

Fonctions :
- “patch” l’ISO pour **auto-boot** (évite d’attendre une touche au menu)
- upload l’ISO dans `/opt/unetlab/addons/qemu/<image>/cdrom.iso`
- crée le disque base si absent : `/opt/unetlab/addons/qemu/<image>/virtioa.qcow2`

### 8.2 Construction du template (une fois, puis réutilisé)

Objectif : installer une fois, puis **skipper** les runs suivants.

Mécanisme :
- un marker est créé sur PNETLab :
  - `/opt/unetlab/addons/qemu/<image_name>/.template_ready`
- s’il existe, Terraform **ne relance pas** la phase “template build”.

Pour figer l’installation, on commit l’overlay QEMU dans le disque base :
- script : `scripts/pnetlab/commit_template.sh`
- commande clé côté PNETLab : `qemu-img commit`

### 8.3 Création du lab final + démarrage du node

Terraform génère deux fichiers `.unl` (XML) :
- `terraform/pnetlab/build_lab.generated.unl` (build template)
- `terraform/pnetlab/target_lab.generated.unl` (lab final)

Ils sont uploadés via :
- `scripts/pnetlab/upload_lab.sh`

Puis le node est démarré via :
- `scripts/pnetlab/unl_node_power.sh start`

### 8.4 Découverte IP

Terraform utilise un “external data source” :
- `scripts/pnetlab/discover_wallix.py`

Ce script :
- scanne `TF_VAR_mgmt_subnet`
- teste `/api/version` pour trouver la VM WALLIX et récupérer son IP

Terraform expose ensuite les outputs :
- `bastion_ip`
- `bastion_url`

---

## 9) Détails : ce que fait Ansible

Dossier : `ansible/`

Le PoC configure WALLIX via **API HTTPS** (module `ansible.builtin.uri`), pas via SSH sur l’OS.

### 9.1 Playbook bootstrap

Fichier : `ansible/playbooks/bootstrap.yml`

Objectif :
- attendre que HTTPS réponde,
- tester des endpoints “status”,
- afficher un résumé de connectivité.

### 9.2 Playbook configure

Fichier : `ansible/playbooks/configure.yml`

Objectifs :
- s’assurer que l’auth API fonctionne,
- **gérer le cas “password reset challenge”** (certains WALLIX imposent un reset/confirmation à la première connexion API),
- appliquer une baseline (opérations déclarées dans `ansible/group_vars/all.yml`).

#### 9.2.1 Gestion optionnelle des utilisateurs (1 par profil)

Le PoC peut créer automatiquement des comptes “PoC” (un par profil WALLIX) via l’API `/api/users`.

- Définition des comptes : `ansible/group_vars/all.yml` (`wallix_managed_users`)
- Tâches : `ansible/tasks/manage_users.yml`

Activation via variables d’environnement (dans `secrets_pnetlab.env`) :

```bash
WALLIX_MANAGED_USERS_ENABLED=true
# Optionnel : si vide, on réutilise WALLIX_ADMIN_NEW_PASSWORD (PoC)
WALLIX_MANAGED_USERS_PASSWORD=
```

Comportement :
- si l’utilisateur n’existe pas → création via `POST /api/users`
- si l’utilisateur existe déjà → le PoC le laisse en place (il ne modifie pas le profil des comptes existants)

Exécution “après coup” (sans relancer tout le configure) :

```bash
cd ./ansible
ansible-playbook -i inventory/generated/hosts.yml playbooks/users.yml
```

Les opérations “baseline” sont déclaratives et “best effort” :
- Ansible essaie plusieurs endpoints possibles par opération (selon version WALLIX).

Fichiers :
- variables : `ansible/group_vars/all.yml`
- moteur d’opérations : `ansible/tasks/run_operation.yml`

---

## 10) Vérification : résultats attendus

### 10.1 Côté Terraform/PNETLab

Attendus :
- le lab `Wallix-Auto` existe dans PNETLab,
- un node `wallix` est présent et démarré,
- Terraform outputs donnent :
  - `bastion_ip=<ip>`
  - `bastion_url=https://<ip>`
  - `wallix_template_ready=true` (après build template)

### 10.2 Côté WALLIX (UI + API)

Attendus :
- UI accessible : `https://<bastion_ip>/`
- API accessible : `https://<bastion_ip>/api/version`
- API authentifiée :
  - `/api/users` répond en 200 avec Basic auth (au minimum)

### 10.3 Smoke tests automatiques

Script : `scripts/smoke_test.py`

Attendus :
- HTTPS root status OK
- probe `/api/users` en 200
- message final : “All checks passed.”

---

## 11) Rerun / idempotence (relancer sans tout casser)

Relancer :
- `bash ./scripts/run-pnetlab.sh`

Comportement :
- si le template est prêt (`.template_ready`), la phase ISO/template est skippée,
- le lab final est remis à jour si nécessaire,
- Ansible réapplique la baseline (souvent sans “changed” si déjà OK).

---

## 12) Troubleshooting (problèmes fréquents)

### 12.1 “Je vois mon ancien WALLIX dans mon ancien lab”

C’est normal : le PoC crée **un lab séparé** `Wallix-Auto`.
Ton lab existant n’est pas modifié.

Solution :
- ouvrir le lab `Wallix-Auto` dans PNETLab,
- ou bien adapter le PoC pour “injecter” un node dans ton lab existant (évolution).

### 12.2 La découverte IP timeout

Ca arrive si :
- WALLIX a une IP **hors** du subnet `TF_VAR_mgmt_subnet`,
- ou si la VM n’obtient pas d’IP (DHCP, réseau mgmt mal connecté).

Vérifs rapides :
- dans PNETLab, vérifier le réseau du node (interface e0 sur MGMT),
- vérifier que le réseau mgmt choisi (`pnet0` etc.) correspond bien à un réseau avec DHCP/accessibilité.

### 12.3 Ansible warning “world writable directory”

Si le dépôt est sur VMware Shared Folders (HGFS), certaines permissions sont larges.
Ansible peut afficher un warning et ignorer `ansible.cfg`.

Workaround simple :
- copier le repo sur le disque local du runner (ex: `~/WallixRepo`) et relancer depuis là.

### 12.4 Édition du fichier `.env` depuis Windows

Ce fichier est “sourcé” par bash dans Ubuntu.
Éviter :
- BOM UTF‑8
- CRLF

Recommandations :
- éditer dans le runner (Linux),
- ou utiliser VS Code en forçant “LF” + “UTF‑8 (sans BOM)”.

---

## 13) Références : fichiers importants

- Entrée PoC PNETLab : `scripts/run-pnetlab.sh`
- Terraform PNETLab : `terraform/pnetlab/main.tf`
- Template lab XML : `terraform/pnetlab/templates/lab.unl.tftpl`
- Scripts PNETLab :
  - `scripts/pnetlab/prepare_image.sh` (ISO + disk)
  - `scripts/pnetlab/upload_lab.sh` (upload `.unl`)
  - `scripts/pnetlab/unl_node_power.sh` (start/stop/wipe)
  - `scripts/pnetlab/commit_template.sh` (qemu-img commit + marker)
  - `scripts/pnetlab/discover_wallix.py` (discover IP via /api/version)
- Inventaire Ansible (généré) : `ansible/inventory/generated/hosts.yml`
- Ansible :
  - `ansible/playbooks/bootstrap.yml`
  - `ansible/playbooks/configure.yml`
  - `ansible/group_vars/all.yml`
  - `ansible/tasks/run_operation.yml`
- Smoke tests : `scripts/smoke_test.py`
