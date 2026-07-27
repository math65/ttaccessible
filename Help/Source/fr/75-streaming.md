---
title: Diffuser du son
description: Envoyer dans le canal un fichier, une radio internet, un périphérique, une autre application ou VoiceOver.
keywords: diffusion, fichier média, URL, radio, périphérique, application, VoiceOver, lecteur média
anchor: streaming
---

tt-Accessible peut envoyer du son dans le canal en même temps que votre voix : un fichier de musique,
une radio internet, la sortie d'une autre application, ou même VoiceOver, pour que le canal entende
ce que dit votre lecteur d'écran.

Les quatre commandes se trouvent dans le menu **Raccourcis**.

## Diffuser un fichier

**Option-Commande-S** — *Diffuser un fichier média…* — ouvre un sélecteur de fichiers. La prise en
charge vidéo dépend des formats que TeamTalk sait décoder sur votre Mac ; la vidéo 10 bits n'est pas
prise en charge. Quand un fichier contient de la vidéo, le panneau **Vidéo** repliable de la fenêtre
principale l'affiche.

## Diffuser une URL

**Option-Commande-U** — *Diffuser une URL…* — demande l'adresse d'un flux audio, une radio internet
par exemple. Les schémas `http`, `https`, `rtmp`, `rtmps`, `rtsp` et `mms` sont acceptés.

## Diffuser un périphérique, une application ou VoiceOver

**Option-Commande-A** — *Diffuser un périphérique ou une application…* — ouvre une fenêtre avec :

- **Source audio** — une entrée audio de votre Mac, **VoiceOver**, ou une entrée du sous-menu
  **Applications**. **Sélectionner une application…** permet de parcourir n'importe quelle
  application installée, même si elle n'est pas lancée, à partir de macOS 14.2. La diffusion de
  l'audio d'une application ou de VoiceOver demande macOS 13 ou une version ultérieure.
- **Me faire entendre l'audio diffusé** — décoché par défaut, pour ne pas vous imposer d'écouter ce
  que vous diffusez.
- **Couper le son de cette source sur ce Mac pendant la diffusion** — la source devient silencieuse
  chez vous alors que le canal continue de l'entendre. Disponible sur les systèmes récents, et
  seulement pour une application.

La diffusion continue même lorsque la source est silencieuse : une pause dans la musique n'interrompt
donc rien. Votre dernier choix est resélectionné la fois suivante.

Si l'application choisie ne produit aucun son, l'application répond que *La source sélectionnée n'a
aucun audio à capturer pour le moment.*

## Le lecteur média

Pendant une diffusion, la fenêtre **Lecteur média** affiche *Lecture :* suivi de la source, et vous
donne :

| Touche | Action |
|---|---|
| Espace | Lecture ou pause |
| Échap | Arrêt |
| Flèche gauche / droite | Reculer ou avancer de 5 secondes |
| Flèche haut / bas | Volume diffusé |

Le **Volume diffusé** règle le niveau auquel le flux part vers le canal, indépendamment du niveau
auquel vous l'écoutez.

## Arrêter

**Option-Commande-.** (Option-Commande-point) — *Arrêter la diffusion* — met fin au flux.
L'application annonce *Diffusion terminée*, et le début comme la fin sont consignés dans l'historique
de session.

## Ce qu'entendent les autres

Le flux atteint toutes les personnes abonnées à votre **Fichier média**. Chacune peut le faire taire
de son côté sans faire taire votre voix, avec *Couper le flux média localement* — voir
[Les personnes que vous entendez](users.html).
