# 02 - Architecture technique

## 1. Vue d'ensemble

L'architecture retenue repose sur quatre briques :

1. le poste Windows avec VMware Workstation ;
2. une VM Ubuntu runner ;
3. une VM PNETLab ;
4. un bastion WALLIX lance dans PNETLab.

Le point important est que le runner n'est pas le bastion. C'est uniquement la machine de controle qui execute Terraform, Ansible et les scripts.

---

## 2. Pourquoi une VM Ubuntu runner

Le choix d'une VM Ubuntu dediee a ete fait pour des raisons de stabilite.

### Probleme observe sur Windows

Sur ce poste, l'utilisation de WSL / Hyper-V entre en conflit avec VMware Workstation et PNETLab. Cela rendait l'environnement instable :

- parfois VMware fonctionnait et WSL non ;
- parfois WSL fonctionnait et le lab ne demarrait plus correctement.

### Solution retenue

Au lieu de faire tourner l'automatisation dans Windows ou dans WSL, on a cree une VM Ubuntu dediee.

Avantages :

- environnement Linux propre pour Terraform, Ansible, Python et SSH ;
- pas de conflit direct avec la virtualisation de VMware ;
- execution reproductible ;
- depot partage simplement avec VMware Shared Folders.

---

## 3. Architecture detaillee

## 3.1 Poste Windows

Role :

- heberger les VM ;
- lancer ou arreter `wallix-control` et `PNET_4.2.10` ;
- stocker le depot Git.

## 3.2 Runner Ubuntu

Role :

- executer Terraform ;
- executer Ansible ;
- executer les scripts shell et Python ;
- acceder au depot partage.

Ce runner a ete monte comme "control plane" du PoC.

## 3.3 PNETLab

Role :

- heberger les labs `.unl` ;
- heberger les images QEMU ;
- demarrer les noeuds QEMU du lab ;
- exposer le reseau de management.

Le pilotage technique de PNETLab se fait principalement en SSH, pas via l'interface web.

## 3.4 Bastion WALLIX

Role :

- fournir la cible fonctionnelle du PoC ;
- exposer l'interface web et l'API ;
- recevoir la configuration appliquee par Ansible.

---

## 4. Flux technique de bout en bout

Le flux retenu dans le mode PNETLab est le suivant :

1. le runner charge les variables du fichier `secrets_pnetlab.env` ;
2. Terraform prepare l'image WALLIX dans PNETLab ;
3. Terraform verifie si un template reutilisable existe deja ;
4. si non, Terraform lance une installation de build ;
5. une fois l'installation terminee, Terraform commit le disque overlay pour en faire un template ;
6. Terraform cree ou met a jour le lab cible ;
7. Terraform demarre le noeud WALLIX cible ;
8. Terraform decouvre l'IP du bastion via scan du subnet et verification `/api/version` ;
9. un script genere l'inventaire Ansible ;
10. Ansible appelle l'API WALLIX pour appliquer la configuration ;
11. des smoke tests verifient l'accessibilite et l'authentification.

---

## 5. Pourquoi PNETLab est pilote en SSH

Le pilotage par SSH a ete retenu parce qu'il est plus robuste pour ce type de PoC.

Actions faites par SSH :

- upload de l'ISO ;
- upload des labs `.unl` ;
- creation du disque QEMU ;
- demarrage / arret / wipe des noeuds ;
- commit du template avec `qemu-img commit`.

Cela evite de dependre de l'API web PNETLab, qui peut varier selon les versions ou etre plus contraignante.

---

## 6. Role exact de Terraform

Terraform ne configure pas WALLIX lui-meme. Terraform decrit et pilote les objets d'infrastructure.

Dans le mode PNETLab, Terraform sert a :

- preparer l'image QEMU ;
- generer les labs de build et de production ;
- lancer les noeuds PNET ;
- detecter l'IP du bastion ;
- exposer les outputs.

Dans le mode vSphere, Terraform sert a :

- cloner une VM depuis un template vCenter ;
- appliquer la configuration VM ;
- exposer les outputs standard du bastion.

---

## 7. Role exact d'Ansible

Ansible est le moteur de configuration.

Il sert a :

- verifier l'accessibilite du bastion ;
- gerer l'authentification API ;
- changer le mot de passe `admin` ;
- creer des utilisateurs WALLIX ;
- creer des devices, services, groupes et authorizations.

Ansible ne remplace pas l'API WALLIX : il l'utilise.

---

## 8. Pourquoi l'API WALLIX est indispensable

Le bastion WALLIX est un produit applicatif. Pour l'automatiser proprement, il faut utiliser son interface d'administration supportee.

Cette interface est l'API WALLIX.

L'API permet de manipuler :

- les comptes ;
- les profils ;
- les devices ;
- les services ;
- les target groups ;
- les authorizations.

Sans cette API, on serait force de faire de l'automatisation fragile par interface graphique ou par scripts non supportes.

---

## 9. Deux chaines dans le depot

Le depot contient deux chaines distinctes.

### Chaine 1 - `terraform/`

But :

- provisioning vSphere depuis template.

Usage :

- a utiliser si un vCenter est disponible.

### Chaine 2 - `terraform/pnetlab/`

But :

- installation WALLIX depuis ISO dans PNETLab ;
- creation du template ;
- lancement du bastion.

Usage :

- c'est la chaine qui a ete reellement montee et testee localement.

---

## 10. Point d'attention important

Le bastion automatique du PoC n'est pas le meme objet que le lab manuel historique.

Il faut distinguer :

- le lab automatique nomme `Wallix-Auto`, stocke dans PNETLab sous le chemin interne `User1/Wallix-Auto.unl`
- le lab manuel historique nomme `LAB_Wallix`, stocke dans PNETLab sous le chemin interne `LAB_Wallix.unl`

Cette distinction est importante pour eviter de penser qu'un redemarrage ou une reconfiguration agit sur la mauvaise machine.
