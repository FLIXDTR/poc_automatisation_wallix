# 01 - Resume executif

## 1. Besoin

Le besoin du projet est d'automatiser au maximum le deploiement et la configuration d'un WALLIX Bastion en environnement de lab.

Le cadre retenu dans ce depot est le suivant :

- hyperviseur local : VMware Workstation ;
- plateforme de lab : PNETLab ;
- bastion cible : WALLIX Bastion 12.0.17 ;
- outils d'automatisation imposes : Terraform et Ansible.

---

## 2. Resultat obtenu

Le depot permet aujourd'hui de mettre en place une chaine de PoC qui fait les operations suivantes :

1. preparer une image WALLIX dans PNETLab a partir de l'ISO ;
2. construire un template reutilisable ;
3. demarrer un bastion WALLIX dans un lab dedie ;
4. retrouver automatiquement son adresse IP ;
5. generer l'inventaire Ansible ;
6. configurer WALLIX via l'API ;
7. creer des utilisateurs WALLIX de demonstration ;
8. declarer des machines, groupes, services et permissions dans WALLIX ;
9. verifier que le bastion repond bien.

Ce resultat est fonctionnel et exploitable comme base serieuse pour une industrialisation.

---

## 3. Ce qui est automatise

### Infrastructure / deploiement

- creation d'un runner Linux dedie ;
- installation automatique des outils sur le runner ;
- upload de l'ISO WALLIX dans PNETLab ;
- patch de l'ISO pour auto-boot ;
- creation du disque QEMU ;
- creation des fichiers de lab PNETLab ;
- demarrage / stop / wipe des noeuds ;
- commit du template QEMU ;
- decouverte automatique de l'IP du bastion.

### Configuration WALLIX

- detection de l'URL API ;
- verification de la disponibilite WALLIX ;
- changement du mot de passe `admin` ;
- recuperation du compte `admin` en mode secours si besoin ;
- creation d'utilisateurs WALLIX par profil ;
- declaration d'assets dans WALLIX ;
- creation de groupes utilisateurs ;
- creation de target groups ;
- creation d'autorisations d'acces.

### Verification

- generation de l'inventaire Ansible ;
- smoke tests HTTPS ;
- smoke tests d'authentification API.

---

## 4. Ce qui n'est pas encore automatise

Le PoC n'automatise pas encore les points suivants :

- installation d'un controleur de domaine Windows depuis zero ;
- alimentation des assets WALLIX depuis une vraie base de donnees metier ;
- interface web metier au-dessus des playbooks ;
- pipeline CI/CD complet ;
- gestion multi-environnements ;
- observabilite avancee ;
- securisation "production-grade" complete.

---

## 5. Pourquoi ce projet repose sur Terraform et Ansible ensemble

Les deux outils n'ont pas le meme role.

### Terraform

Terraform sert a decrire et piloter l'infrastructure :

- images ;
- labs ;
- noeuds PNET ;
- deploiement de la machine ;
- decouverte d'IP ;
- outputs techniques.

### Ansible

Ansible sert a decrire et piloter la configuration fonctionnelle de WALLIX :

- compte `admin` ;
- utilisateurs WALLIX ;
- machines declarees dans le bastion ;
- groupes ;
- droits ;
- authorizations.

### API WALLIX

Ansible ne configure pas WALLIX "a l'aveugle". Il utilise l'API WALLIX comme point d'entree technique.

Donc la bonne lecture est :

- Terraform deploie ;
- Ansible orchestre ;
- l'API WALLIX est la cible de configuration.

---

## 6. Etat valide du PoC

Au moment de la remise, les verifications suivantes ont deja ete faites :

- la VM runner demarre ;
- la VM PNETLab demarre ;
- le bastion du lab automatique repond sur `https://192.168.214.10` ;
- l'endpoint `GET /api/version` confirme un WALLIX 12.0.17 ;
- les playbooks de configuration et d'assets ont ete executes ;
- un groupe `poc_admins` existe ;
- des authorizations de type RDP et SSH ont ete appliquees.

---

## 7. Conclusion

Le projet n'est pas une simple preuve de concept theorique. Il existe maintenant une chaine operationnelle qui separe correctement :

- le deploiement ;
- la configuration ;
- la verification ;
- la documentation.

La prochaine phase logique n'est plus de "faire marcher le PoC", mais d'industrialiser le modele de donnees et l'exploitation.
