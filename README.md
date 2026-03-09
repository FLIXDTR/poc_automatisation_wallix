# Automatisation WALLIX Bastion

PoC d'automatisation pour deployer et configurer un WALLIX Bastion avec Terraform et Ansible.

Ce depot contient deux chaines principales :

- mode `PNETLab` : construit et lance un WALLIX Bastion a partir d'un ISO dans PNETLab sur VMware Workstation ;
- mode `vSphere` : clone une VM WALLIX depuis un template existant dans vCenter.

Le workflow le plus complet et effectivement valide dans ce depot est le mode `PNETLab`.

## Documentation

Point d'entree principal :

- `DOCUMENTATION/README.md`

Point d'entree rapide depuis la racine :

- `DOCUMENTATION_WALLIX.md`

## Structure du depot

- `ansible/` - playbooks de configuration WALLIX via API
- `terraform/` - stack Terraform vSphere
- `terraform/pnetlab/` - stack Terraform PNETLab
- `scripts/` - scripts d'orchestration, de preparation et de recuperation
- `DOCUMENTATION/` - documentation structuree du projet
- `logs/` - journaux d'execution
- `tmp/` - artefacts temporaires de debug

## Modes supportes

## 1. Mode PNETLab

Objectif :

- preparer l'image WALLIX dans PNETLab
- uploader et patcher l'ISO en auto-boot
- construire un template QEMU reutilisable
- lancer un noeud WALLIX dedie
- decouvrir automatiquement son IP
- configurer WALLIX avec Ansible via l'API

Point d'entree principal :

```bash
bash ./scripts/run-pnetlab.sh
```

Fichier de secrets principal :

- `secrets_pnetlab.env`
- modele : `secrets_pnetlab.env.example`

## 2. Mode local

Objectif :

- reutiliser une VM WALLIX deja installee
- ignorer Terraform
- appliquer uniquement la configuration Ansible

Point d'entree principal :

```powershell
.\scripts\run-poc.ps1 -Mode local
```

Fichier de secrets local :

- `secrets_local.env`
- modele : `secrets_local.env.example`

## 3. Mode vSphere

Objectif :

- cloner une VM WALLIX depuis un template vCenter existant
- exposer les sorties Terraform pour Ansible
- appliquer la configuration WALLIX

Point d'entree principal :

```powershell
.\scripts\run-poc.ps1 -Mode vsphere
```

Fichier de secrets vSphere :

- `.secrets.env`
- modele : `.secrets.env.example`

## Mode d'execution recommande

Il est recommande d'utiliser une VM Ubuntu dediee comme runner dans VMware Workstation plutot que WSL lorsque la stabilite de VMware / PNETLab est prioritaire.

Raison :

- WSL / Hyper-V peut interferer avec VMware Workstation sur certains postes Windows ;
- le depot s'appuie sur des outils Linux natifs comme `ansible`, `sshpass`, `xorriso`, `scp` et des scripts shell.

Scripts de preparation du runner :

- creation de la VM runner sous Windows : `scripts/setup-runner-vm.ps1`
- installation des outils dans Ubuntu : `scripts/runner/bootstrap-runner.sh`

## Demarrage rapide

## Workflow PNETLab

1. Creer le fichier de secrets :

```bash
cp ./secrets_pnetlab.env.example ./secrets_pnetlab.env
```

2. Renseigner au minimum :

- l'acces SSH PNETLab
- le tenant, la session et les chemins de labs
- le subnet de management
- les identifiants API WALLIX

3. Verifier que l'ISO WALLIX est disponible localement.

Important :

- l'ISO n'est pas suppose etre versionne dans Git ;
- le chemin par defaut dans `secrets_pnetlab.env.example` suppose l'ISO a la racine du projet ;
- si l'ISO est stocke ailleurs, il faut adapter `TF_VAR_wallix_iso_path`.

4. Lancer le workflow complet depuis le runner :

```bash
bash ./scripts/run-pnetlab.sh
```

## Workflow local

1. Creer le fichier de secrets :

```bash
cp ./secrets_local.env.example ./secrets_local.env
```

2. Renseigner au minimum :

- `LOCAL_BASTION_HOST`
- `WALLIX_API_USER`
- `WALLIX_API_PASSWORD`
- `WALLIX_ADMIN_NEW_PASSWORD`

3. Lancer :

```powershell
.\scripts\run-poc.ps1 -Mode local -AutoApprove
```

## Ce que fait Terraform

Terraform est utilise ici pour piloter l'infrastructure et l'orchestration de deploiement.

En mode `PNETLab`, il :

- prepare le repertoire d'image QEMU ;
- uploade et patche l'ISO en auto-boot ;
- genere les labs de build et de production en `.unl` ;
- demarre et arrete les noeuds PNETLab ;
- commit l'overlay de build dans un template reutilisable ;
- decouvre l'IP du bastion WALLIX.

En mode `vSphere`, il :

- clone une VM WALLIX depuis un template existant ;
- expose `bastion_ip` et `bastion_url` pour la phase Ansible.

## Ce que fait Ansible

Ansible est utilise pour configurer le produit WALLIX via l'API WALLIX.

Il gere notamment :

- les tests de disponibilite initiaux ;
- la rotation du mot de passe `admin` ;
- la recuperation de l'acces `admin` via SSH management si necessaire ;
- la creation d'utilisateurs de demonstration ;
- la declaration de devices, services, groupes, target groups et authorizations.

Playbooks principaux :

- `ansible/playbooks/bootstrap.yml`
- `ansible/playbooks/configure.yml`
- `ansible/playbooks/users.yml`
- `ansible/playbooks/assets.yml`

## Scripts importants

- `scripts/run-pnetlab.sh` - workflow complet PNETLab
- `scripts/run-poc.ps1` - point d'entree Windows pour `local` et `vsphere`
- `scripts/setup-runner-vm.ps1` - creation de la VM Ubuntu runner
- `scripts/runner/bootstrap-runner.sh` - installation des outils dans le runner
- `scripts/generate_inventory.py` - generation de l'inventaire Ansible a partir des sorties Terraform
- `scripts/smoke_test.py` - verification HTTPS et authentification API
- `scripts/wallix_reset_admin.py` - restauration du compte `admin` WALLIX via SSH management

## Fonctions optionnelles deja presentes

### Utilisateurs WALLIX geres

Activation :

- `WALLIX_MANAGED_USERS_ENABLED=true`

Definition :

- `ansible/group_vars/all.yml`

### Assets WALLIX

Activation :

- `WALLIX_ASSETS_ENABLED=true`

Definition :

- `ansible/data/wallix_assets.yml`

Cette partie couvre deja :

- devices
- services
- comptes locaux
- groupes utilisateurs
- target groups
- authorizations

## Hygiene avant publication

Avant de publier ce depot, verifier que les fichiers locaux sensibles ou volumineux ne sont pas inclus par erreur.

Ne pas publier :

- `.secrets.env`
- `secrets_local.env`
- `secrets_pnetlab.env`
- les ISO locaux
- les states Terraform locaux
- les logs et captures temporaires
- `.venv/`

Le depot ignore deja les principaux fichiers locaux via `.gitignore`, mais cela ne protege que les workflows bases sur Git.

## Etat actuel

Le depot est structure et exploitable comme base de PoC reproductible.

Le chemin local valide aujourd'hui est :

- VMware Workstation
- VM Ubuntu runner
- VM PNETLab
- WALLIX Bastion deployee dans un lab PNETLab dedie
- Terraform pour le deploiement
- Ansible pour la configuration WALLIX

Pour l'architecture detaillee, les etapes d'utilisation et la cartographie du depot, consulter :

- `DOCUMENTATION/README.md`
