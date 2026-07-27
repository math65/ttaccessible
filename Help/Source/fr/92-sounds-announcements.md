---
title: Sons et annonces
description: Choisir un pack de sons, en composer un, et décider de ce que l'application dit à voix haute au premier plan comme en arrière-plan.
keywords: sons, pack de sons, notification, annonce, VoiceOver, synthèse vocale, arrière-plan
anchor: sounds-announcements
---

tt-Accessible vous tient au courant de deux façons : par de courts sons, et par des annonces vocales.
Les deux se règlent événement par événement.

## Les packs de sons

Trois packs sont fournis — **Default**, **Majorly-G** et **Old** — et se choisissent avec **Pack de
sons**, dans [Préférences → Sons](preferences.html#prefs-sounds). **Activer les notifications
sonores** coupe l'ensemble d'un seul geste.

Pour composer le vôtre :

1. **Fichiers requis...** énumère tous les noms de fichiers que l'application recherche et
   l'événement auquel chacun correspond. Préparez un dossier de fichiers WAV portant ces noms. Tout
   fichier absent est remplacé par celui du pack Default.
2. **Nouveau pack...** importe ce dossier. Son nom devient celui du pack.
3. Une fois votre pack sélectionné, **Modifier le pack sélectionné** apparaît : chaque événement
   indique s'il est **Personnalisé** ou **Défaut**, avec **Choisir...** pour désigner un autre
   fichier et **Réinitialiser** pour revenir en arrière.
4. **Afficher le dossier des packs** ouvre le dossier où vos packs sont rangés, et **Supprimer**
   retire celui qui est sélectionné. Supprimer un pack personnalisé l'efface aussi de ce Mac.

Le niveau de ces sons suit le curseur **Volume des effets sonores** de la fenêtre principale.

## Les vingt-six événements sonores

Chacun se désactive séparément :

| | |
|---|---|
| Un utilisateur a rejoint le canal | Un utilisateur a quitté le canal |
| Message privé reçu | Message privé envoyé |
| Message de canal reçu | Message de canal envoyé |
| Connexion perdue | Message général |
| Utilisateur connecté | Utilisateur déconnecté |
| Fichier ajouté ou supprimé | Transfert de fichier terminé |
| Mode question | Raccourci clavier |
| Activation vocale activée | Activation vocale désactivée |
| Tout couper | Tout rétablir |
| Interception démarrée | Interception terminée |
| File de transmission démarrée | File de transmission arrêtée |
| VOX activé | VOX désactivé |
| Microphone activé | Microphone désactivé |

## Les annonces vocales

[Préférences → Annonces](preferences.html#prefs-announcements) distingue deux situations.

### Quand tt-Accessible est au premier plan

**Annonces d'événements** règle ce qui passe par VoiceOver :

- **Annoncer les messages de canal**, **Annoncer les messages privés** et **Annoncer les messages
  généraux** — tous activés par défaut.
- **Annoncer l'historique système**, une liste de vingt événements à activer ou désactiver un par
  un, avec **Tout activer** et **Tout désactiver**. Ils sont regroupés en **Connexion** (connecté,
  déconnecté, connexion perdue), **Canal actuel** (rejoint, quitté), **Présence des utilisateurs**
  (connexion et déconnexion, arrivée et départ d'un canal), **Modération** (expulsion du serveur ou
  du canal, transmission bloquée), **Statut** (absence automatique activée et désactivée),
  **Abonnements** (modification d'un abonnement ou d'une interception), **Fichiers** (ajouté,
  supprimé) et **Diffusion média** (démarrée, terminée).

Désactiver un événement ne fait taire que l'annonce : la ligne reste inscrite dans l'historique de
session.

### Quand une autre application est au premier plan

**Messages reçus en arrière-plan** détermine la façon dont vous êtes prévenu quand tt-Accessible
n'est pas au premier plan :

- **Notification système** — une notification macOS classique. C'est le réglage par défaut.
- **Synthèse vocale macOS** — l'application énonce elle-même le message, avec la **Voix**, le
  **Débit** et le **Volume** réglés juste en dessous. **Tester la voix** essaie les réglages courants.
- **VoiceOver via AppleScript** — c'est VoiceOver qui annonce le message.

**Utiliser le même mode pour tous les types d'événements** est activé par défaut et applique un mode
unique à tout. Désactivez-le pour choisir un mode différent selon qu'il s'agit d'un message privé,
d'un message de canal, d'un message général ou de l'historique TeamTalk — par exemple une annonce
parlée pour les messages privés et une simple notification pour le reste.
