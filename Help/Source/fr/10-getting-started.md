---
title: Premiers pas
description: Installer tt-Accessible, choisir sa langue, se connecter pour la première fois et garder l'application à jour.
keywords: installation, premier lancement, langue, autorisation micro, mise à jour, Sparkle, bêta
anchor: getting-started
---

## Ce qu'il vous faut

- **macOS 12.0 (Monterey) ou une version plus récente.** L'application est un binaire universel :
  elle tourne nativement sur les Mac Apple silicon comme sur les Mac Intel.
- **Un serveur TeamTalk 5**, dont on vous a donné les coordonnées, ou bien un fichier `.tt` ou un
  lien `tt://` que quelqu'un vous a transmis.
- **Un micro** si vous comptez parler. Pour écouter, il n'est pas nécessaire.

Certaines fonctions demandent un système plus récent : à partir de macOS 14.2, l'annulation d'écho
capte l'ensemble du son du Mac, et la diffusion du son d'une application ou de VoiceOver réclame elle
aussi un macOS récent (voir [Diffuser du son](streaming.html)).

## Installation

1. Téléchargez la dernière archive depuis la page des versions du projet.
2. Décompressez-la, puis glissez **tt-Accessible** dans votre dossier Applications.
3. Ouvrez l'application. Le premier lancement peut prendre quelques instants, le temps que macOS
   vérifie le logiciel.

## Au premier lancement

L'application vous demande **Choisissez votre langue** : anglais ou français. Vous pourrez revenir
sur ce choix dans [Préférences → Général](preferences.html#prefs-general) ; il faut alors relancer
l'application pour que le changement s'applique partout.

La première fois que vous activez le micro, macOS demande l'autorisation de l'utiliser. Si vous
refusez, l'application signale que *L'accès au micro a été refusé par macOS.* et il faut alors
l'accorder dans Réglages Système → Confidentialité et sécurité → Microphone.

## Se connecter pour la première fois

La fenêtre qui s'ouvre au lancement s'appelle **Serveurs TeamTalk**. Elle est vide tant que vous
n'avez pas ajouté de serveur :

- **Commande-N** pour saisir vous-même les coordonnées, ou
- **Serveur → Importer les serveurs TeamTalk…** (Maj-Commande-I) si vous disposez d'un fichier de
  configuration, d'un fichier `.tt` ou d'un lien `tt://`.

Sélectionnez ensuite le serveur dans la liste et appuyez sur **Entrée** ou sur **F2**.

Tout ceci est détaillé dans [Les serveurs](servers.html).

## Rester à jour

tt-Accessible vérifie les mises à jour de lui-même et vous propose de les installer.

- **tt-Accessible → Vérifier les mises à jour…** lance une vérification immédiate.
- Dans [Préférences → Général](preferences.html#prefs-general), la section **Mises à jour** propose
  **Vérifier les mises à jour automatiquement** (activé par défaut) et **Inclure les versions bêta**
  (désactivé par défaut). Les versions bêta peuvent contenir des bugs ; laissez l'option désactivée
  pour ne recevoir que les versions stables.

## Trouver de l'aide

Le menu **Aide** propose également **Voir le projet sur GitHub**, **Signaler un problème…** et, quand
la version le permet, **Contacter le développeur…** — un formulaire qui envoie directement un message
au développeur, avec le journal audio en pièce jointe si vous le souhaitez. Voir
[En cas de problème](troubleshooting.html).
