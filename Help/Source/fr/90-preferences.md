---
title: Modifier les réglages de tt-Accessible
description: Tous les réglages de tt-Accessible, volet par volet, avec leur valeur par défaut.
keywords: préférences, réglages, général, connexion, BearWare, audio, sons, annonces, enregistrements
anchor: preferences
---

Pour modifier vos réglages, choisissez tt-Accessible > Préférences, ou appuyez sur Commande +
Virgule, puis cliquez sur l'un des sept volets de la barre latérale. Appuyez sur Échap pour fermer
la fenêtre.

<a id="prefs-general"></a>

## Réglages généraux

| Réglage | Par défaut |
|---|---|
| **Pseudo par défaut** — utilisé quand un serveur enregistré n'a pas de pseudo | votre nom de compte macOS |
| **Message de statut par défaut** | vide |
| **Genre** | Neutre |
| **Délai avant absence automatique**, en minutes — 0 la désactive | 3 |
| **Message d'absence** | vide |
| **Utiliser des horodatages relatifs**, du type « il y a 2 min » | désactivé |
| **Utiliser la détection automatique du fichier TeamTalk lors de l'import** | activé |
| **Langue** — Langue du système, Anglais ou Français | Langue du système |

L'absence automatique vous passe en Absent dès que vous cessez d'utiliser le clavier ou la souris
pendant le nombre de minutes choisi, et la lève dès que vous vous en servez réellement de nouveau.
Les annonces de VoiceOver ou d'une plage braille ne comptent pas comme une activité.

La section Mises à jour contient **Vérifier les mises à jour automatiquement**, activé, et
**Inclure les versions bêta**, désactivé.

<a id="prefs-connection"></a>

## Réglages de connexion

| Réglage | Par défaut |
|---|---|
| **Rejoindre automatiquement le canal principal à la connexion** | activé |
| **Reconnexion automatique en cas de perte de connexion** | activé |
| **Rejoindre automatiquement le dernier canal après une reconnexion** | activé |
| **Se connecter au dernier serveur utilisé au démarrage** | désactivé |
| **Se connecter toujours avec le micro coupé** | désactivé |
| **Ne pas demander de confirmation lors de l'expulsion** | désactivé |
| **Buffer de gigue adaptatif**, qui améliore l'audio sur les connexions instables | désactivé |
| **Trier les canaux par** — Nom, ou Nombre d'utilisateurs | Nom |
| **Afficher les personnes par** — Pseudo et nom d'utilisateur, Pseudo seulement, ou Nom d'utilisateur seulement | Pseudo et nom d'utilisateur |

**Abonnements par défaut** détermine ce que tout le monde peut vous envoyer dès la connexion :
messages privés, messages de canal, messages généraux, audio, partages d'écran et fichiers médias.
Les six sont activés.

**Interceptions par défaut** — messages privés, messages de canal, audio, partages d'écran et
fichiers médias — sont toutes désactivées et demandent les droits correspondants sur le serveur.
Modifier l'une ou l'autre liste s'applique immédiatement à la session en cours.

<a id="prefs-bearware"></a>

## Réglages BearWare

Un compte BearWare gratuit (bearware.dk) vous permet de vous connecter aux serveurs qui acceptent la
connexion web. Saisissez votre **Identifiant BearWare** et votre **Mot de passe BearWare**, puis
cliquez sur **Se connecter**. Consultez
[Ajouter un serveur et s'y connecter](servers.html).

<a id="prefs-audio"></a>

## Réglages audio

| Réglage | Par défaut |
|---|---|
| **Périphérique de sortie** — Par défaut du système, un périphérique précis, ou Aucune sortie audio | Par défaut du système |
| **Périphérique d'entrée** | Par défaut du système |
| **Traitement du micro** — Aucun, Réduction de bruit, ou Annulation d'écho + réduction de bruit | Aucun |
| **Canaux d'entrée** — Auto, une entrée mono, une paire stéréo ou une somme mono | Auto |
| **Mode du microphone** — Toujours actif, Push-to-talk, ou Les deux | Toujours actif |
| **Touche de push-to-talk** | non définie |
| **Jouer un son au début et à la fin de la transmission** | activé |
| **Le push-to-talk fonctionne même quand une autre app est au premier plan** | activé |
| **Le raccourci d'activation du microphone fonctionne même quand une autre app est au premier plan** | désactivé |
| **Touche globale d'activation du microphone** | Commande + Maj + A |
| **Mémorisation des volumes par utilisateur** — Désactivé, Session en cours seulement, ou Toujours | Toujours |

Consultez [Configurer vos périphériques audio](audio-setup.html) et
[Parler dans un canal](talking.html).

<a id="prefs-sounds"></a>

## Réglages des sons

**Activer les notifications sonores**, activé, commande l'ensemble des sons, et **Pack de sons**
choisit lequel est utilisé. En dessous, les vingt-six événements sonores se désactivent
individuellement. Consultez [Choisir les sons et les annonces](sounds-announcements.html).

<a id="prefs-announcements"></a>

## Réglages des annonces

**Messages reçus en arrière-plan** détermine ce qui se passe quand quelque chose arrive alors que
tt-Accessible n'est pas au premier plan. **Utiliser le même mode pour tous les types d'événements**,
activé, applique un mode unique à tout ; désactivez-le pour régler séparément les messages privés,
les messages de canal, les messages généraux et l'historique TeamTalk. Les trois modes sont
**Notification système**, le réglage par défaut, **Synthèse vocale macOS** et **VoiceOver via
AppleScript**.

**Annonces d'événements** concerne ce que dit VoiceOver pendant que l'app est au premier plan :
messages de canal, privés et généraux, tous activés, plus **Annoncer l'historique système** — vingt
événements à activer ou désactiver un par un.

<a id="prefs-recording"></a>

## Réglages d'enregistrement

| Réglage | Par défaut |
|---|---|
| **Dossier d'enregistrement** | aucun |
| **Mode d'enregistrement pour Cmd+Maj+R** — Fichiers séparés, ou Les deux | Les deux |
| **Format audio** — WAV ou OGG (Opus) | WAV |
| **Redémarrer automatiquement l'enregistrement en rejoignant un canal** | désactivé |

Commande + R enregistre toujours un seul fichier mixé, quel que soit ce mode. Consultez
[Enregistrer une conversation](recording.html).
