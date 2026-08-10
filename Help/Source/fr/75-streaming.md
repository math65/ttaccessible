---
title: Diffuser du son dans un canal
description: Envoyer un fichier, une radio internet, un périphérique, une autre app ou VoiceOver dans le canal, en même temps que votre voix.
keywords: diffusion, fichier média, URL, radio, périphérique, application, VoiceOver, lecteur média
anchor: streaming
---

Vous pouvez envoyer du son dans le canal en même temps que votre voix : un fichier de musique, une
radio internet, le son d'une autre app, ou VoiceOver lui-même, pour que le canal entende ce que dit
votre lecteur d'écran. Les quatre commandes se trouvent dans le menu Raccourcis.

## Diffuser un fichier

1. Choisissez Raccourcis > Diffuser un fichier média, ou appuyez sur Option + Commande + S.
2. Sélectionnez un fichier audio ou vidéo, puis cliquez sur Diffuser.

La prise en charge vidéo dépend des formats que TeamTalk sait décoder sur votre Mac, et la vidéo 10
bits n'est pas gérée. Quand un fichier contient de la vidéo, le panneau Vidéo de la fenêtre
principale l'affiche.

## Diffuser une radio internet ou une autre URL

1. Choisissez Raccourcis > Diffuser une URL, ou appuyez sur Option + Commande + U.
2. Saisissez l'adresse du flux, puis cliquez sur Diffuser. Les schémas `http`, `https`, `rtmp`,
   `rtmps`, `rtsp` et `mms` sont acceptés.

## Diffuser un périphérique, des apps ou VoiceOver

1. Choisissez Raccourcis > Diffuser du son de ce Mac, ou appuyez sur Option + Commande + A.
2. Dans la liste **Source audio**, cochez ce que vous voulez envoyer. Utilisez les flèches pour
   parcourir la liste et la barre d'espace pour cocher ou décocher.
3. Sélectionnez **Me faire entendre l'audio diffusé** si vous voulez entendre ce que vous envoyez.
   L'option est décochée, pour ne pas vous imposer cette écoute.
4. Sélectionnez **Couper le son de cette source sur ce Mac pendant la diffusion** pour la faire
   taire chez vous alors que le canal continue de l'entendre. Cette option ne s'applique qu'aux
   applications, sur les versions récentes de macOS.
5. Cliquez sur Diffuser.

### Ce que vous pouvez cocher

- **Plusieurs applications à la fois.** Votre lecteur de musique et VoiceOver, par exemple, pour
  que le canal entende ce que vous écoutez et ce que dit votre lecteur d'écran.
- **Tout le son de ce Mac**, quand désigner les apps une par une n'a pas d'intérêt. Le son de
  tt-Accessible lui-même est retiré de la capture, sans quoi le canal s'entendrait revenir.
  Attention : les notifications et les sons du système partent aussi dans le canal.
- **Un périphérique d'entrée**, qui se diffuse seul : cocher un périphérique décoche les
  applications, et inversement. tt-Accessible vous annonce ce qui vient d'être décoché.

Pour désigner une app qui n'est pas lancée, cliquez sur **Sélectionner une application** — cela
nécessite macOS 14.2 ou une version ultérieure. La diffusion de l'audio d'une app, de VoiceOver ou
de tout le Mac nécessite macOS 13 ou une version ultérieure.

La diffusion continue même lorsque la source est silencieuse : une pause dans la musique ne
l'interrompt pas. Votre dernier choix est recoché la fois suivante, même s'il portait sur
plusieurs applications.

Si l'app choisie ne produit aucun son, tt-Accessible répond *La source sélectionnée n'a aucun audio
à capturer pour le moment.*

## Contrôler une diffusion en cours

Pendant une diffusion, la fenêtre principale affiche un bloc de commandes sous les curseurs de son :
le nom de ce qui passe, un bouton pour l'interrompre, un bouton Arrêter et le volume diffusé. Un
fichier média ajoute un curseur Position ; une radio, un périphérique ou une app n'en ont pas,
puisque leur diffusion n'a pas de fin à atteindre.

Ces touches agissent dès que le focus se trouve dans ce bloc :

| Touche | Fichier média | Radio, périphérique ou app |
|---|---|---|
| Espace | Pause ou reprise | Couper ou rétablir le son |
| Échap | Arrêt | Arrêt |
| Flèche gauche ou Flèche droite | Reculer ou avancer de 5 secondes | Sans effet |
| Flèche haut ou Flèche bas | Modifier le volume diffusé | Modifier le volume diffusé |

Option + Commande + M fait la même chose depuis n'importe où dans l'app.

Un périphérique, une app et VoiceOver ne se mettent pas en pause : la source est coupée, mais la
diffusion continue. Le canal vous voit toujours en train de diffuser et n'entend plus rien, jusqu'à
ce que vous rétablissiez le son.

Le volume diffusé règle le niveau auquel le flux part vers le canal, indépendamment du niveau auquel
vous l'écoutez. À 0 %, plus rien ne part.

## Arrêter la diffusion

Choisissez Raccourcis > Arrêter la diffusion, ou appuyez sur Option + Commande + Point.
tt-Accessible annonce *Diffusion terminée*, et le début comme la fin apparaissent dans l'historique
de session.

Toutes les personnes abonnées à votre fichier média l'entendent. Chacune peut le faire taire sans
faire taire votre voix — consultez
[Régler ce que vous entendez de chaque personne](users.html).

**Voir aussi :** [Parler dans un canal](talking.html) ·
[Enregistrer une conversation](recording.html)
