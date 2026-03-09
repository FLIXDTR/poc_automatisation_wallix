# 03 - Guide d'utilisation

## 1. Objectif

Ce guide explique comment relancer le PoC et quoi verifier ensuite.

Il est oriente "usage", pas "developpement".

---

## 2. Prerequis

Il faut disposer des elements suivants :

- VMware Workstation sur le poste Windows ;
- une VM PNETLab fonctionnelle ;
- une VM Ubuntu runner fonctionnelle ;
- l'ISO WALLIX disponible localement ;
- un acces reseau entre le runner, PNETLab et le subnet de management du bastion.

Important :

- l'ISO n'est pas suppose etre versionne dans Git ;
- soit il est place a la racine du projet ;
- soit `TF_VAR_wallix_iso_path` est adapte dans `secrets_pnetlab.env`.

---

## 3. Fichiers a remplir

## 3.1 Fichier principal pour le mode PNETLab

Le fichier a utiliser est :

- `secrets_pnetlab.env`

Il doit etre cree a partir de :

- `secrets_pnetlab.env.example`

Commande :

```bash
cp ./secrets_pnetlab.env.example ./secrets_pnetlab.env
```

## 3.2 Variables minimales a verifier

Dans `secrets_pnetlab.env`, verifier au minimum :

- `TF_VAR_pnet_ssh_host`
- `TF_VAR_pnet_ssh_user`
- `TF_VAR_pnet_ssh_password`
- `TF_VAR_pnet_tenant_id`
- `TF_VAR_pnet_session_id`
- `TF_VAR_pnet_lab_path`
- `TF_VAR_pnet_build_lab_path`
- `TF_VAR_mgmt_subnet`
- `TF_VAR_wallix_iso_path`
- `TF_VAR_wallix_image_name`
- `WALLIX_API_USER`
- `WALLIX_API_PASSWORD`
- `WALLIX_ADMIN_NEW_PASSWORD`

### Variables utiles pour la configuration fonctionnelle

- `WALLIX_MANAGED_USERS_ENABLED=true`
- `WALLIX_ASSETS_ENABLED=true`
- `WIN_DC_HOST=<ip_du_dc>`
- `WIN_DC_ADMIN_PASSWORD=<mot_de_passe_local_windows>`

---

## 4. Preparation du runner

Si le runner Ubuntu n'est pas deja pret :

### Cote Windows

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\setup-runner-vm.ps1 -StartVm
```

### Cote runner Ubuntu

Depuis le depot partage :

```bash
sudo bash ./scripts/runner/bootstrap-runner.sh
```

Ce script installe :

- Terraform ;
- Ansible ;
- Python ;
- SSH ;
- `sshpass` ;
- `xorriso` ;
- `jq` ;
- `open-vm-tools`.

---

## 5. Commande principale

Depuis le runner Ubuntu, dans le depot :

```bash
bash ./scripts/run-pnetlab.sh
```

Cette commande est l'entree principale du PoC PNETLab.

---

## 6. Ce que fait la commande

Le script `scripts/run-pnetlab.sh` execute les operations suivantes :

1. charge `secrets_pnetlab.env` ;
2. lance `terraform init` ;
3. lance `terraform fmt -check` ;
4. lance `terraform validate` ;
5. lance `terraform apply` dans `terraform/pnetlab` ;
6. recupere les outputs Terraform ;
7. genere l'inventaire Ansible ;
8. installe les collections Ansible si besoin ;
9. lance `bootstrap.yml` ;
10. lance `configure.yml` ;
11. lance `assets.yml` si `WALLIX_ASSETS_ENABLED=true` ;
12. lance les smoke tests.

---

## 7. Resultat attendu

Si tout se passe bien, le resultat attendu est le suivant :

- un bastion WALLIX tourne dans PNETLab ;
- son IP a ete detectee automatiquement ;
- l'inventaire Ansible a ete genere ;
- le compte `admin` est utilisable avec le mot de passe cible ;
- les utilisateurs de demonstration existent si l'option est activee ;
- les assets definis dans `ansible/data/wallix_assets.yml` existent dans WALLIX ;
- les smoke tests passent.

---

## 8. Verifications a faire apres execution

## 8.1 Verification reseau

Verifier que le bastion repond sur son URL HTTPS.

Dans l'environnement actuel, l'instance automatisee verifiee etait :

- `https://192.168.214.10`

Verification API minimale :

```bash
curl -k https://192.168.214.10/api/version
```

## 8.2 Verification interface web

Se connecter a l'interface web du bastion avec le compte `admin` et le mot de passe final configure.

## 8.3 Verification des utilisateurs

Si `WALLIX_MANAGED_USERS_ENABLED=true`, verifier la presence des comptes :

- `poc_approver`
- `poc_auditor`
- `poc_operation_admin`
- `poc_product_admin`
- `poc_system_admin`
- `poc_user`

## 8.4 Verification des assets

Si `WALLIX_ASSETS_ENABLED=true`, verifier la presence de :

- device `winserver_dc`
- device `runner_vm`
- groupe `poc_admins`
- target group `poc_windows`
- target group `poc_runner`
- authorization `poc_rdp_winserver`
- authorization `poc_ssh_runner`

---

## 9. Points d'attention

## 9.1 Ne pas confondre les labs

Le PoC automatique utilise son propre lab :

- lab PNETLab `Wallix-Auto` (chemin interne PNETLab : `User1/Wallix-Auto.unl`)

Ce n'est pas le meme que :

- le lab manuel historique `LAB_Wallix` (chemin interne PNETLab : `LAB_Wallix.unl`)

## 9.2 Si le DC change d'IP

Il faut mettre a jour :

- `WIN_DC_HOST`

Sinon WALLIX pointera vers la mauvaise machine Windows.

## 9.3 Si le mot de passe `admin` n'est plus connu

Le playbook de configuration sait utiliser un chemin de secours via SSH management WALLIX, a condition que les variables SSH soient correctement renseignees.

---

## 10. Commandes utiles

### Regenerer uniquement les assets WALLIX

Depuis le runner :

```bash
cd ansible
ansible-playbook -i inventory/generated/hosts.yml playbooks/assets.yml
```

### Relancer uniquement la configuration de base WALLIX

```bash
cd ansible
ansible-playbook -i inventory/generated/hosts.yml playbooks/configure.yml
```

### Verifier les outputs Terraform

```bash
terraform -chdir=terraform/pnetlab output
```

### Verifier les smoke tests

```bash
python3 scripts/smoke_test.py --terraform-dir terraform/pnetlab
```

---

## 11. Procedure simple de demonstration

Pour presenter rapidement le PoC a une personne qui decouvre le projet, la sequence la plus simple est :

1. montrer `secrets_pnetlab.env` sans les secrets ;
2. lancer `bash ./scripts/run-pnetlab.sh` depuis le runner ;
3. montrer les outputs Terraform ;
4. montrer la generation de l'inventaire ;
5. montrer l'execution des playbooks Ansible ;
6. ouvrir l'interface WALLIX ;
7. verifier la presence des users et des assets ;
8. montrer que le bastion repond sur `/api/version`.
