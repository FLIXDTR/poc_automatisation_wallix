# 04 - Cartographie du depot

## 1. But de cette cartographie

Le depot contient plusieurs scripts et plusieurs couches d'automatisation. Ce document indique clairement :

- ou se trouve chaque partie ;
- a quoi elle sert ;
- quels fichiers modifier selon le besoin.

---

## 2. Vue d'ensemble

### `terraform/`

Contient le mode historique vSphere.

Fichiers importants :

- `terraform/main.tf`
- `terraform/variables.tf`
- `terraform/outputs.tf`
- `terraform/versions.tf`

Usage :

- a utiliser si le projet cible un vCenter / vSphere.

### `terraform/pnetlab/`

Contient le mode PNETLab, qui est celui valide localement.

Fichiers importants :

- `terraform/pnetlab/main.tf`
- `terraform/pnetlab/variables.tf`
- `terraform/pnetlab/outputs.tf`
- `terraform/pnetlab/templates/lab.unl.tftpl`

Fichiers generes :

- `terraform/pnetlab/build_lab.generated.unl`
- `terraform/pnetlab/target_lab.generated.unl`
- `terraform/pnetlab/terraform.tfstate`

### `ansible/`

Contient la configuration fonctionnelle WALLIX.

Sous-ensembles importants :

- `ansible/playbooks/`
- `ansible/tasks/`
- `ansible/group_vars/`
- `ansible/data/`
- `ansible/inventory/generated/`

### `scripts/`

Contient les scripts d'orchestration et les utilitaires.

Sous-ensembles importants :

- `scripts/run-pnetlab.sh`
- `scripts/run-poc.ps1`
- `scripts/setup-runner-vm.ps1`
- `scripts/runner/`
- `scripts/pnetlab/`

---

## 3. Fichiers les plus importants

## 3.1 Entrees principales

### `scripts/run-pnetlab.sh`

Script principal du PoC local PNETLab.

Si quelqu'un doit relancer le PoC, c'est en general ce script qu'il doit utiliser.

### `scripts/setup-runner-vm.ps1`

Script de creation de la VM runner Ubuntu.

### `scripts/runner/bootstrap-runner.sh`

Script d'installation des outils dans le runner.

---

## 3.2 Terraform PNETLab

### `terraform/pnetlab/main.tf`

Coeur du deploiement PNETLab.

C'est ici que se trouve la logique :

- de preparation de l'image ;
- de generation des labs ;
- de build du template ;
- de lancement du bastion cible ;
- de decouverte de l'IP.

### `terraform/pnetlab/outputs.tf`

Expose les informations utiles a l'orchestration :

- IP du bastion ;
- URL du bastion ;
- etat du template ;
- informations de build.

---

## 3.3 Ansible

### `ansible/playbooks/bootstrap.yml`

Verification initiale du bastion et prerequis API.

### `ansible/playbooks/configure.yml`

Configuration de base WALLIX :

- verification du mot de passe actif ;
- rotation du mot de passe `admin` ;
- chemin de secours via SSH management.

### `ansible/playbooks/users.yml`

Creation des utilisateurs WALLIX de demonstration.

### `ansible/playbooks/assets.yml`

Creation de la configuration fonctionnelle WALLIX :

- devices ;
- groupes ;
- target groups ;
- authorizations.

### `ansible/group_vars/all.yml`

Source de configuration globale Ansible.

On y trouve notamment :

- les variables API WALLIX ;
- les parametres SSH management ;
- la liste des utilisateurs de demonstration.

### `ansible/data/wallix_assets.yml`

Source de verite des assets WALLIX du PoC.

C'est ce fichier qu'il faut modifier pour :

- ajouter une machine ;
- ajouter un service ;
- ajouter un target group ;
- ajouter une authorization.

---

## 3.4 Scripts utilitaires

### `scripts/generate_inventory.py`

Transforme les outputs Terraform en inventaire Ansible.

### `scripts/smoke_test.py`

Realise les controles de fin de run.

### `scripts/wallix_reset_admin.py`

Script de secours pour restaurer l'acces au compte `admin`.

---

## 4. Fichiers a modifier selon le besoin

## 4.1 Changer le reseau ou le lab PNET

Modifier :

- `secrets_pnetlab.env`

Variables typiques :

- `TF_VAR_pnet_lab_path`
- `TF_VAR_pnet_build_lab_path`
- `TF_VAR_mgmt_subnet`
- `TF_VAR_pnet_mgmt_network_name`
- `TF_VAR_pnet_mgmt_network_type`

## 4.2 Changer l'ISO ou l'image WALLIX

Modifier :

- `secrets_pnetlab.env`

Variables typiques :

- `TF_VAR_wallix_iso_path`
- `TF_VAR_wallix_image_name`
- `TF_VAR_wallix_disk_size`

## 4.3 Ajouter des utilisateurs WALLIX

Modifier :

- `ansible/group_vars/all.yml`

Section :

- `wallix_managed_users`

## 4.4 Ajouter des devices / permissions

Modifier :

- `ansible/data/wallix_assets.yml`

Sections :

- `wallix_devices`
- `wallix_usergroups`
- `wallix_targetgroups`
- `wallix_authorizations`

---

## 5. Fichiers generes a ne pas modifier a la main

Les fichiers suivants sont produits par les scripts ou par Terraform :

- `ansible/inventory/generated/hosts.yml`
- `terraform/pnetlab/build_lab.generated.unl`
- `terraform/pnetlab/target_lab.generated.unl`
- `terraform/pnetlab/terraform.tfstate`

Ils peuvent etre inspectes, mais ne doivent pas etre consideres comme la source de verite fonctionnelle.

---

## 6. Source de verite actuelle

La source de verite actuelle du PoC est repartie en trois endroits :

### Variables d'environnement / secrets

- `secrets_pnetlab.env`

### Deploiement infra

- `terraform/pnetlab/main.tf`

### Configuration WALLIX

- `ansible/group_vars/all.yml`
- `ansible/data/wallix_assets.yml`

---

## 7. Lecture rapide du depot

Si quelqu'un doit comprendre vite le projet, il faut lire dans cet ordre :

1. `scripts/run-pnetlab.sh`
2. `terraform/pnetlab/main.tf`
3. `ansible/playbooks/configure.yml`
4. `ansible/playbooks/users.yml`
5. `ansible/playbooks/assets.yml`
6. `ansible/data/wallix_assets.yml`
