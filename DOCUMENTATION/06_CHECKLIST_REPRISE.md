# 06 - Checklist de reprise

## 1. But

Cette checklist sert a une personne qui reprend le projet et veut :

- verifier rapidement que l'environnement est pret ;
- savoir quoi modifier ;
- relancer le PoC sans relire tout le depot.

---

## 2. Checklist environnement

Verifier les points suivants :

- VMware Workstation est installe ;
- la VM PNETLab existe et demarre ;
- la VM runner Ubuntu existe et demarre ;
- le depot est accessible depuis le runner ;
- l'ISO WALLIX est presente dans le depot ;
- le runner peut joindre PNETLab en SSH.

---

## 3. Checklist configuration

Verifier ou creer :

- `secrets_pnetlab.env`

Verifier dedans :

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

Si on veut les users et les assets :

- `WALLIX_MANAGED_USERS_ENABLED=true`
- `WALLIX_ASSETS_ENABLED=true`

Si le DC Windows change :

- mettre a jour `WIN_DC_HOST`
- mettre a jour `WIN_DC_ADMIN_PASSWORD`

---

## 4. Checklist outils

Sur le runner Ubuntu, verifier :

```bash
terraform version
ansible-playbook --version
python3 --version
```

Si necessaire, relancer :

```bash
sudo bash ./scripts/runner/bootstrap-runner.sh
```

---

## 5. Checklist execution

Depuis le runner, lancer :

```bash
bash ./scripts/run-pnetlab.sh
```

Verifier pendant le run :

- `terraform init` passe ;
- `terraform validate` passe ;
- `terraform apply` passe ;
- l'inventaire Ansible est genere ;
- `configure.yml` passe ;
- `assets.yml` passe si active ;
- les smoke tests passent.

---

## 6. Checklist verification finale

Verifier ensuite :

- le bastion repond sur son URL HTTPS ;
- `curl -k https://<ip>/api/version` repond ;
- le compte `admin` fonctionne ;
- les users de demonstration existent si actives ;
- les assets existent si actives ;
- les authorizations existent si actives.

Dans l'etat du PoC verifie localement, l'instance automatisee etait joignable sur :

- `https://192.168.214.10`

---

## 7. Checklist modification fonctionnelle

Si la reprise consiste a etendre le projet, modifier les bons fichiers :

### Ajouter des utilisateurs WALLIX

- `ansible/group_vars/all.yml`

### Ajouter des machines / services / permissions

- `ansible/data/wallix_assets.yml`

### Changer le reseau ou le lab PNET

- `secrets_pnetlab.env`
- `terraform/pnetlab/main.tf` seulement si la logique doit evoluer

### Changer la logique Ansible

- `ansible/playbooks/`
- `ansible/tasks/`

---

## 8. Regle de reprise simple

Si la personne reprend le projet sans contexte, l'ordre minimal a suivre est :

1. lire `DOCUMENTATION/README.md`
2. lire `DOCUMENTATION/03_GUIDE_UTILISATION.md`
3. verifier `secrets_pnetlab.env`
4. lancer `bash ./scripts/run-pnetlab.sh`
5. controler l'interface WALLIX
