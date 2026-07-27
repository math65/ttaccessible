---
title: Les préférences
description: Tous les réglages de tt-Accessible, volet par volet, avec leur valeur par défaut.
keywords: préférences, réglages, général, connexion, BearWare, audio, sons, annonces, enregistrements
anchor: preferences
---

**Commande-virgule** ouvre les préférences. La fenêtre comporte sept volets, listés dans une barre
latérale : Général, Connexion, BearWare, Audio, Sons, Annonces et Enregistrements. Échap referme la
fenêtre, et Commande-point d'interrogation ouvre la section de ce guide qui correspond au volet
affiché.

<a id="prefs-general"></a>

## Général

| Réglage | Par défaut |
|---|---|
| **Pseudo par défaut** — utilisé quand un serveur enregistré n'a pas de pseudo spécifique | votre nom de compte macOS |
| **Message de statut par défaut** | vide |
| **Genre** | Neutre |
| **Délai avant absence automatique**, en minutes — 0 la désactive | 3 |
| **Message d'absence** | vide |
| **Utiliser des horodatages relatifs (ex. « il y a 2 min »)** | désactivé |
| **Utiliser la détection automatique du fichier TeamTalk lors de l'import** | activé |
| **Langue** — Langue du système, Anglais ou Français | Langue du système |

L'absence automatique passe votre statut en *Absent* dès que vous ne touchez plus au clavier ni à la
souris pendant le nombre de minutes choisi, et le rétablit dès que vous y touchez réellement de
nouveau. Les annonces de VoiceOver ou d'une plage braille ne comptent pas comme une activité.

Changer de langue demande de relancer l'application pour que le choix s'applique partout.

La section **Mises à jour** contient **Vérifier les mises à jour automatiquement** (activé) et
**Inclure les versions bêta** (désactivé). Les versions bêta peuvent contenir des bugs.

<a id="prefs-connection"></a>

## Connexion

| Réglage | Par défaut |
|---|---|
| **Rejoindre automatiquement le canal principal à la connexion** | activé |
| **Reconnexion automatique en cas de perte de connexion** | activé |
| **Rejoindre automatiquement le dernier canal après une reconnexion** | activé |
| **Se connecter au dernier serveur utilisé au démarrage** | désactivé |
| **Ne pas demander de confirmation lors de l'expulsion** | désactivé |
| **Buffer de gigue adaptatif (améliore l'audio sur les connexions instables)** | désactivé |
| **Trier les canaux par** — Nom, ou Nombre d'utilisateurs (les plus peuplés d'abord) | Nom |

**Abonnements par défaut** détermine ce que vous recevez de tout le monde dès la connexion : messages
privés, messages de canal, messages généraux, audio, partages d'écran et fichiers médias. Les six
sont activés par défaut.

**Interceptions par défaut** — messages privés, messages de canal, audio, partages d'écran et
fichiers médias — sont toutes désactivées et demandent les droits correspondants sur le serveur.
Modifier l'une ou l'autre liste s'applique immédiatement à la session en cours.

La version « par personne » de ces interrupteurs est décrite dans
[Les personnes que vous entendez](users.html).

<a id="prefs-bearware"></a>

## BearWare

Un compte BearWare gratuit (bearware.dk) permet de se connecter aux serveurs qui acceptent la
connexion web. Saisissez votre **Identifiant BearWare** et votre **Mot de passe BearWare**, puis **Se
connecter** ; le volet indique ensuite sous quel nom vous êtes connecté et propose **Se déconnecter**.

La connexion web s'active ensuite serveur par serveur, dans les réglages de chacun. Voir
[Les serveurs](servers.html).

<a id="prefs-audio"></a>

## Audio

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
| **Touche globale d'activation du microphone** | Commande-Maj-A |
| **Mémorisation des volumes par utilisateur** — Désactivé, Session en cours seulement, ou Toujours | Toujours |

**Actualiser les périphériques** reconstruit la liste, et **Aperçu audio** vous renvoie votre micro
pour un essai. Les détails sont dans [Régler l'audio](audio-setup.html) et
[Prendre la parole](talking.html).

<a id="prefs-sounds"></a>

## Sons

**Activer les notifications sonores** (activé) commande l'ensemble, et **Pack de sons** choisit
lequel est utilisé. En dessous, les vingt-six événements sonores se désactivent individuellement ;
tous sont actifs par défaut.

Les boutons **Nouveau pack...**, **Fichiers requis...**, **Afficher le dossier des packs** et, pour
vos propres packs, **Supprimer** ainsi que **Choisir...** / **Réinitialiser** événement par
événement, permettent de composer votre propre pack. Voir
[Sons et annonces](sounds-announcements.html).

<a id="prefs-announcements"></a>

## Annonces

**Messages reçus en arrière-plan** détermine ce qui se passe quand un message ou un événement arrive
alors que tt-Accessible n'est pas au premier plan. **Utiliser le même mode pour tous les types
d'événements** (activé) applique un **Mode** unique à tout ; désactivez-le pour régler séparément les
messages privés, les messages de canal, les messages généraux et l'historique TeamTalk. Les trois
modes sont **Notification système** (par défaut), **Synthèse vocale macOS** et **VoiceOver via
AppleScript**.

**Synthèse vocale macOS** configure ce mode : **Voix**, **Débit**, **Volume** et un bouton **Tester
la voix**.

**Annonces d'événements** concerne ce qui est dit pendant que l'application *est* au premier plan :
messages de canal, messages privés et messages généraux, activés par défaut, plus **Annoncer
l'historique système** — vingt événements groupés par thème, avec **Tout activer** et **Tout
désactiver**.

<a id="prefs-recording"></a>

## Enregistrements

| Réglage | Par défaut |
|---|---|
| **Dossier d'enregistrement** | aucun |
| **Mode d'enregistrement pour Cmd+Maj+R** — Fichiers séparés, ou Les deux | Les deux |
| **Format audio** — WAV ou OGG (Opus) | WAV |
| **Redémarrer automatiquement l'enregistrement en rejoignant un canal** | désactivé |

Commande-R enregistre toujours un seul fichier mixé, quel que soit le mode ci-dessus. Voir
[Enregistrer](recording.html).
