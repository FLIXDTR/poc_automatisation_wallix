# Documentation - Automatisation WALLIX

## Objectif du dossier

Cette documentation a ete preparee pour qu'une personne qui reprend le projet puisse :

- comprendre rapidement le besoin traite ;
- comprendre l'architecture retenue ;
- savoir ce qui est effectivement automatise aujourd'hui ;
- savoir comment relancer le PoC ;
- identifier quels fichiers modifier pour aller plus loin.

Ce dossier est volontairement organise en documents courts et specialises, plutot qu'en un seul fichier melangeant tout.

---

## Contenu du dossier

### 1. Resume executif

Fichier :

- `DOCUMENTATION/01_RESUME_EXECUTIF.md`

Contient :

- le besoin ;
- le resultat obtenu ;
- le perimetre du PoC ;
- ce qui est automatise ;
- ce qui ne l'est pas encore.

### 2. Architecture technique

Fichier :

- `DOCUMENTATION/02_ARCHITECTURE_TECHNIQUE.md`

Contient :

- le role du runner Linux ;
- le role de VMware ;
- le role de PNETLab ;
- le role de Terraform ;
- le role d'Ansible ;
- le role de l'API WALLIX ;
- les flux techniques de bout en bout.

### 3. Guide d'utilisation

Fichier :

- `DOCUMENTATION/03_GUIDE_UTILISATION.md`

Contient :

- les prerequis ;
- les fichiers a remplir ;
- la commande principale ;
- le comportement attendu ;
- les points de verification apres execution.

### 4. Cartographie du depot

Fichier :

- `DOCUMENTATION/04_CARTOGRAPHIE_DEPOT.md`

Contient :

- les repertoires importants ;
- les scripts importants ;
- les fichiers a modifier selon le besoin ;
- les fichiers generes automatiquement.

### 5. Etat du PoC et prochaines etapes

Fichier :

- `DOCUMENTATION/05_ETAT_DU_POC_ET_PROCHAINES_ETAPES.md`

Contient :

- l'etat reel du PoC au moment de la remise ;
- ce qui a ete teste ;
- les limites connues ;
- les prochaines etapes recommandeees pour industrialiser.

### 6. Checklist de reprise

Fichier :

- `DOCUMENTATION/06_CHECKLIST_REPRISE.md`

Contient :

- la liste minimale d'actions pour relancer le PoC ;
- les verifications a faire ;
- les fichiers a modifier avant un rerun.

---

## Parcours de lecture recommande

Pour comprendre rapidement le projet :

1. lire `DOCUMENTATION/01_RESUME_EXECUTIF.md`
2. lire `DOCUMENTATION/02_ARCHITECTURE_TECHNIQUE.md`

Pour relancer le PoC :

1. lire `DOCUMENTATION/03_GUIDE_UTILISATION.md`
2. lire `DOCUMENTATION/04_CARTOGRAPHIE_DEPOT.md`

Pour preparer la suite du projet :

1. lire `DOCUMENTATION/05_ETAT_DU_POC_ET_PROCHAINES_ETAPES.md`
2. lire `DOCUMENTATION/06_CHECKLIST_REPRISE.md`

---

## Point important

Le PoC reellement valide localement repose sur :

- VMware Workstation ;
- une VM Ubuntu "runner" ;
- une VM PNETLab ;
- un bastion WALLIX lance dans un lab PNETLab ;
- Terraform pour la creation et le pilotage du lab ;
- Ansible pour la configuration du produit WALLIX via son API.

Le mode `vSphere` existe toujours dans le depot, mais le mode `PNETLab` est celui qui a ete reellement mis en place et teste dans l'environnement local.

## Note sur le contenu du depot

Le depot a ete nettoye pour separer les zones de travail.

Organisation retenue :

- `DOCUMENTATION/` : documentation principale ;
- `archives/` : anciens documents et supports de reference ;
- `logs/` : journaux d'execution ;
- `tmp/` : artefacts temporaires et captures de debug.

Le point d'entree principal est :

- `DOCUMENTATION/README.md`
