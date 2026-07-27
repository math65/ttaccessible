---
title: Enregistrer
description: Enregistrer une conversation en un seul fichier mixé, en un fichier par personne, ou les deux.
keywords: enregistrement, enregistrer, WAV, OGG, Opus, dossier, stems, canal sans enregistrement
anchor: recording
---

## Démarrer et arrêter

| Raccourci | Ce qui est enregistré |
|---|---|
| Commande-R | Un seul fichier mixé, toujours |
| Maj-Commande-R | Ce que dit le **Mode d'enregistrement** des préférences |

**Commande-R** arrête également l'enregistrement, tout comme Maj-Commande-R. L'application annonce
*Enregistrement démarré* puis *Enregistrement arrêté*, et l'état audio (**F9**) indique si un
enregistrement est en cours. Un bouton de la barre d'outils fait la même chose.

La première fois, si aucun dossier n'a été choisi, l'application vous demande où enregistrer.

## Le mode d'enregistrement

[Préférences → Enregistrements](preferences.html#prefs-recording) définit ce que fait
**Maj-Commande-R** :

- **Fichiers séparés (un par utilisateur)** — un fichier par personne, y compris votre propre voix.
- **Les deux** — un fichier mixé *et* les fichiers individuels. C'est le réglage par défaut.

**Commande-R** n'est pas concerné : il produit toujours le fichier mixé unique. C'est toute la raison
d'être des deux raccourcis.

## Format et dossier

- **Format audio** — **WAV** (par défaut, non compressé) ou **OGG (Opus)** (compressé, bien plus
  léger).
- **Dossier d'enregistrement** — désigné par **Choisir…**, retiré par **Effacer**. L'application
  conserve d'un lancement à l'autre le droit d'y écrire.

## Les canaux qui interdisent l'enregistrement

Un canal peut être créé avec l'option **Pas d'enregistrement audio**. Dans un tel canal, Commande-R
et Maj-Commande-R refusent de démarrer et l'application annonce *L'enregistrement n'est pas autorisé
dans ce canal* — sauf si votre compte dispose du droit d'enregistrer la voix.

## La reprise automatique

**Redémarrer automatiquement l'enregistrement en rejoignant un canal** — désactivé par défaut —
relance l'enregistrement quand vous changez de canal, quand la connexion revient, ou quand vous
relancez l'application après une session qui enregistrait. Le mode réellement en cours est restauré :
un enregistrement lancé par Commande-R revient donc en fichier unique, et non selon la préférence de
Maj-Commande-R.

Le changement de canal pendant un enregistrement mixé est géré pour vous : le fichier en cours est
refermé et un nouveau démarre dans le nouveau canal.
