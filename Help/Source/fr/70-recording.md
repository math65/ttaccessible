---
title: Enregistrer une conversation
description: Enregistrer un canal en un seul fichier mixé, en un fichier par personne, ou les deux, et choisir où vont les fichiers.
keywords: enregistrement, enregistrer, WAV, OGG, Opus, dossier, stems, canal sans enregistrement
anchor: recording
---

Vous pouvez enregistrer ce qui se dit dans un canal. tt-Accessible peut mixer tout le monde dans un
seul fichier, écrire un fichier par personne, ou faire les deux à la fois.

## Démarrer et arrêter un enregistrement

- Pour enregistrer un seul fichier mixé, appuyez sur Commande + R.
- Pour enregistrer selon le mode défini dans les Préférences, appuyez sur Maj + Commande + R.

Appuyez de nouveau sur le même raccourci pour arrêter. tt-Accessible annonce *Enregistrement
démarré* puis *Enregistrement arrêté*, et F9 vous indique si un enregistrement est en cours. Un
bouton de la barre d'outils fait la même chose.

La première fois, si vous n'avez pas choisi de dossier, tt-Accessible vous demande où enregistrer.

## Choisir ce qu'enregistre Maj + Commande + R

1. Ouvrez les Préférences, puis cliquez sur Enregistrements dans la barre latérale.
2. Cliquez sur le menu local **Mode d'enregistrement**, puis choisissez l'une des options
   suivantes :
   - **Fichiers séparés** — un fichier par personne, y compris votre propre voix.
   - **Les deux** — un fichier mixé et les fichiers individuels.

Commande + R n'est pas concerné : il produit toujours le fichier mixé unique. C'est toute la raison
d'être des deux raccourcis.

## Choisir le format et le dossier

1. Ouvrez les Préférences, puis cliquez sur Enregistrements.
2. Cliquez sur le menu local **Format audio**, puis choisissez **WAV** pour des fichiers non
   compressés ou **OGG (Opus)** pour des fichiers bien plus légers.
3. Cliquez sur **Choisir**, puis sélectionnez le dossier de destination. tt-Accessible conserve d'un
   lancement à l'autre le droit d'y écrire.

## Reprendre l'enregistrement automatiquement

Sélectionnez **Redémarrer automatiquement l'enregistrement en rejoignant un canal** pour relancer
l'enregistrement quand vous changez de canal, quand la connexion revient, ou quand vous rouvrez
tt-Accessible après une session qui enregistrait. Le mode réellement en cours est restauré.

Le changement de canal pendant un enregistrement mixé est géré pour vous : le fichier en cours est
refermé et un nouveau démarre dans le nouveau canal.

## Si un canal interdit l'enregistrement

Un canal peut être créé avec l'option **Pas d'enregistrement audio**. Commande + R et Maj + Commande
+ R refusent alors de démarrer, et tt-Accessible annonce *L'enregistrement n'est pas autorisé dans
ce canal* — sauf si votre compte dispose du droit d'enregistrer la voix.

**Voir aussi :** [Rejoindre et gérer des canaux](channels.html) ·
[Modifier les réglages de tt-Accessible](preferences.html#prefs-recording)
