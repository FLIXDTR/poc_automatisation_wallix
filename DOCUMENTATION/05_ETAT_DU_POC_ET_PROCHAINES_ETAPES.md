# 05 - Etat du PoC et prochaines etapes

## 1. Etat reel du PoC

Ce document decrit l'etat reel observe du PoC au moment de la remise.

---

## 2. Ce qui a ete fait techniquement

## 2.1 Partie Terraform

Les travaux importants realises sur Terraform sont les suivants :

- maintien du mode historique vSphere dans `terraform/` ;
- creation d'un vrai mode PNETLab dans `terraform/pnetlab/` ;
- generation automatique des labs de build et de production ;
- creation d'un pipeline de construction de template WALLIX ;
- exposition d'outputs coherents (`bastion_ip`, `bastion_url`, etc.).

## 2.2 Partie Ansible

Les travaux importants realises sur Ansible sont les suivants :

- structuration des playbooks en `bootstrap`, `configure`, `users`, `assets` ;
- gestion plus robuste de l'authentification API ;
- ajout d'un chemin de secours pour recuperer le compte `admin` ;
- creation automatique d'utilisateurs WALLIX par profil ;
- ajout de la gestion des devices, user groups, target groups et authorizations ;
- adaptation des tasks pour rester compatibles avec l'environnement Ansible du runner.

## 2.3 Partie scripts

Les travaux importants realises sur les scripts sont les suivants :

- creation de la VM runner ;
- installation automatique des outils dans le runner ;
- orchestration PNETLab de bout en bout ;
- patch ISO auto-boot ;
- decouverte automatique du bastion ;
- generation automatique de l'inventaire Ansible ;
- smoke tests de fin de run.

---

## 3. Etat verifie dans l'environnement local

Verifications constatees dans l'environnement courant :

- la VM `wallix-control` demarre ;
- la VM `PNET_4.2.10` demarre ;
- le bastion WALLIX du lab automatique repond ;
- l'API `/api/version` retourne bien un WALLIX 12.0.17 ;
- le runner peut joindre le bastion ;
- les playbooks Ansible peuvent etre executes sur ce bastion.

Etat reseau observe :

- runner : `192.168.214.132`
- PNETLab : `192.168.214.128`
- bastion automatique detecte : `192.168.214.10`

Important :

- selon le poste depuis lequel on teste, l'acces direct a `192.168.214.10` peut etre plus fiable depuis le runner que depuis Windows.

---

## 4. Configuration fonctionnelle deja appliquee

Les objets suivants ont deja ete modelises dans WALLIX :

### Utilisateurs de demonstration

- `poc_approver`
- `poc_auditor`
- `poc_operation_admin`
- `poc_product_admin`
- `poc_system_admin`
- `poc_user`

### Groupe utilisateur

- `poc_admins`

### Devices

- `winserver_dc`
- `runner_vm`

### Services

- `rdp` sur `winserver_dc`
- `ssh` sur `runner_vm`

### Target groups

- `poc_windows`
- `poc_runner`

### Authorizations

- `poc_rdp_winserver`
- `poc_ssh_runner`

---

## 5. Limites connues

Le PoC fonctionne, mais il reste des limites normales a ce stade.

### Limites techniques

- le DC Windows n'est pas encore construit automatiquement depuis zero ;
- l'environnement reste tres lie au lab local actuel ;
- la gestion des secrets est locale ;
- il n'y a pas encore de source de verite metier centralisee.

### Limites produit

- la couverture des objets WALLIX n'est pas encore exhaustive ;
- certaines policies plus avancees ne sont pas encore automatisees ;
- le projet n'a pas encore d'interface de self-service.

---

## 6. Prochaines etapes recommandees

La suite logique du projet est de passer d'un PoC technique a une couche d'automatisation exploitable par des non-specialistes.

Ordre recommande :

### Etape 1 - definir une source de verite metier

Exemples :

- base SQL ;
- fichier YAML central ;
- fichier CSV importe ;
- API metier interne.

Cette source doit decrire :

- les utilisateurs ;
- les profils ;
- les groupes ;
- les machines ;
- les services ;
- les comptes ;
- les autorisations.

### Etape 2 - generer la configuration WALLIX a partir de cette source

But :

- ne plus modifier manuellement `wallix_assets.yml` ;
- produire automatiquement la configuration cible.

### Etape 3 - ajouter une interface simple

But :

- permettre a un operateur de renseigner les donnees sans toucher au code ;
- declencher ensuite Terraform + Ansible automatiquement.

### Etape 4 - industrialiser l'execution

But :

- historiser les runs ;
- journaliser les changements ;
- gerer plusieurs environnements ;
- integrer un vrai pipeline.

---

## 7. Risque principal pour la suite

Le risque principal n'est plus l'automatisation technique de base. Elle existe deja.

Le vrai sujet de la phase suivante est la qualite du modele de donnees :

- qui declare quoi ;
- selon quelle source de verite ;
- avec quel niveau de validation ;
- avec quelle gouvernance.

Si cette partie est mal definie, l'automatisation restera fragile meme avec de bons scripts.

---

## 8. Conclusion

Le PoC est suffisamment avance pour servir de base de travail serieuse :

- l'installation du bastion dans PNETLab est automatisee ;
- la configuration WALLIX est automatisee ;
- les assets et permissions de demonstration sont automatisees ;
- les scripts importants sont presents dans le depot ;
- le projet est documente pour reprise.

La suite doit maintenant viser la structuration metier et l'industrialisation, pas la reimplementation des bases.
