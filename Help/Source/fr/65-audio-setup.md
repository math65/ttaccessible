---
title: Régler l'audio
description: Choisir les périphériques d'entrée et de sortie, activer la réduction de bruit ou l'annulation d'écho, et tester son micro.
keywords: périphérique audio, entrée, sortie, annulation d'écho, AEC, réduction de bruit, aperçu, canaux, casque
anchor: audio-setup
---

Tout ce qui suit se trouve dans [Préférences → Audio](preferences.html#prefs-audio). Les changements
sont appliqués immédiatement, même en pleine session.

## Les périphériques

- **Périphérique de sortie** — **Par défaut du système**, une sortie précise de votre Mac, ou
  **Aucune sortie audio** si vous voulez faire tourner l'application en silence.
- **Périphérique d'entrée** — **Par défaut du système** ou un micro précis.

**Actualiser les périphériques** reconstruit la liste après un branchement ou un débranchement.
L'application détecte de toute façon ces changements toute seule et redémarre son moteur audio : un
casque connecté en cours de session est pris en compte sans que vous ayez à intervenir.

## Le traitement du micro

**Traitement du micro** propose trois réglages :

- **Aucun** — votre micro part tel quel.
- **Réduction de bruit** — supprime le bruit de fond de votre microphone.
- **Annulation d'écho + réduction de bruit** — retire en plus le son de vos haut-parleurs de ce que
  vous envoyez, et comprend toujours la réduction de bruit.

C'est l'annulation d'écho qui permet de travailler **sans casque** : sans elle, tout le monde
s'entend revenir par votre micro. À partir de macOS 14.2, l'application utilise comme référence le
son réellement produit par le Mac : VoiceOver et les sons système sont donc annulés au même titre que
les voix du canal. Sur les systèmes plus anciens, seul l'audio de TeamTalk peut l'être.

## Les canaux d'entrée

**Canaux d'entrée** détermine quelles entrées physiques du périphérique sont utilisées :

- **Auto** — l'application choisit.
- **Entrée _n_ mono** — une entrée unique.
- **Entrées _n_/_n_ stéréo** — une paire stéréo.
- **Somme mono _n_+_n_** — deux entrées additionnées en mono.

Le réglage prend tout son sens avec une interface audio multi-entrées, où le micro est rarement sur
l'entrée 1. Si le périphérique change et que la configuration choisie ne convient plus, l'application
revient sur **Auto** et vous le signale.

## Se tester avant de parler

**Aperçu audio** vous renvoie votre micro, avec le traitement sélectionné, sans être connecté à quoi
que ce soit. Le même bouton — **Arrêter l'aperçu** — met fin à l'essai.

En session, **Maj-Commande-H** (le retour audio) fait la même chose à travers le canal.

## La mémorisation des volumes

**Mémorisation des volumes par utilisateur** décide du sort des niveaux que vous réglez pour chaque
personne :

- **Désactivé** — tout revient à 50 % à la reconnexion.
- **Session en cours seulement** — oublié à la fermeture.
- **Toujours** — mémorisé d'un lancement à l'autre. C'est le réglage par défaut.

Les réglages sont propres à chaque serveur : un niveau défini sur un serveur ne se reporte jamais sur
un autre.

## Si l'audio se comporte mal

L'application tient un journal de diagnostic que vous pouvez consulter ou joindre à un message
adressé au développeur ; voir [En cas de problème](troubleshooting.html).
