---
title: En cas de problème
description: Que vérifier quand il n'y a pas de son, quand le micro reste muet, quand il y a de l'écho, et comment joindre le développeur.
keywords: problème, pas de son, micro, écho, autorisation, trousseau, journal, assistance, bug
anchor: troubleshooting
---

## Je n'entends rien

Déroulez cette liste ; **F9** répond déjà à la première question en énonçant l'état audio.

1. Le volume principal est-il coupé ? **Commande-M** le rétablit.
2. Le curseur **Volume de sortie** de la fenêtre principale est-il au minimum ?
3. Dans [Préférences → Audio](preferences.html#prefs-audio), le **Périphérique de sortie** est-il
   réglé sur **Aucune sortie audio**, ou sur un appareil que vous n'utilisez plus ? **Actualiser les
   périphériques** reconstruit la liste.
4. Cette personne est-elle coupée pour vous ? Sa ligne indique *coupé*, et **Maj-Commande-M** la
   rétablit. Vérifiez aussi son niveau dans [le mixeur](mixer.html).
5. Êtes-vous toujours abonné à son **Audio** ? Voir [Les personnes que vous entendez](users.html).

## Personne ne m'entend

1. Il faut être **dans un canal**. Ailleurs, l'application répond *Vous devez rejoindre un canal
   avant d'activer le micro.*
2. Le micro est-il activé ? **Maj-Commande-A**, ou le bouton de la barre d'outils.
3. Êtes-vous en **push-to-talk** sans avoir défini de touche ? Le volet Audio le signale, et tant
   qu'aucune touche n'est enregistrée le micro se comporte comme en mode « toujours actif ».
4. macOS a-t-il refusé l'accès ? L'application indique alors *L'accès au micro a été refusé par
   macOS.* Accordez-le dans Réglages Système → Confidentialité et sécurité → Microphone.
5. Le bon **Périphérique d'entrée** est-il sélectionné, avec la bonne configuration de **Canaux
   d'entrée** ? Sur une interface audio, le micro est rarement sur l'entrée 1.
6. Un opérateur vous a-t-il bloqué ? L'application annonce *Transmission bloquée par l'opérateur du
   canal.*

**Maj-Commande-H** (le retour audio) tranche la question : si vous vous entendez par le canal, c'est
que vous êtes bien à l'antenne.

## Tout le monde s'entend revenir

C'est de l'écho : vos haut-parleurs sont repris par votre micro. Utilisez un casque, ou réglez
**Traitement du micro** sur **Annulation d'écho + réduction de bruit** dans
[Préférences → Audio](preferences.html#prefs-audio). À partir de macOS 14.2, cette option annule
également VoiceOver et les sons du système.

## Le son s'est cassé après un branchement

L'application détecte les changements de périphérique et redémarre son moteur audio toute seule. Si
quelque chose cloche malgré tout, utilisez **Actualiser les périphériques**. Si le micro s'est arrêté,
l'application le dit : *Le micro s'est arrêté après un changement de périphérique audio. Réactivez-le.*

## L'enregistrement refuse de démarrer

Le canal a probablement été créé avec l'option **Pas d'enregistrement audio** ; l'application annonce
alors *L'enregistrement n'est pas autorisé dans ce canal.* Seul un compte disposant du droit
d'enregistrer la voix peut passer outre. Voir [Enregistrer](recording.html).

## La diffusion d'une application ne marche pas

- Diffuser l'audio d'une application ou de VoiceOver demande **macOS 13 ou une version ultérieure**,
  et parcourir les applications qui ne sont pas lancées demande **macOS 14.2 ou une version
  ultérieure**.
- Si l'application répond *La source sélectionnée n'a aucun audio à capturer pour le moment*,
  vérifiez que l'application visée tourne réellement et produit du son.

Voir [Diffuser du son](streaming.html).

## Le serveur refuse mon mot de passe

- L'alerte **Échec de la connexion** propose **Modifier les identifiants…** pour corriger le nom
  d'utilisateur ou le mot de passe.
- Si le serveur utilise la connexion web BearWare, vérifiez que votre compte est bien connecté dans
  [Préférences → BearWare](preferences.html#prefs-bearware).
- Si macOS refuse l'accès au mot de passe enregistré, l'application vous l'explique : ouvrez
  Trousseau d'accès, supprimez l'entrée **ttaccessible** correspondante, puis réessayez.

## La connexion tombe sans arrêt

Le **Buffer de gigue adaptatif**, dans
[Préférences → Connexion](preferences.html#prefs-connection), améliore l'audio sur les connexions
instables. La reconnexion automatique et le retour dans le dernier canal sont activés par défaut dans
le même volet.

## Signaler un problème

**Aide → Contacter le développeur…** ouvre un formulaire où vous choisissez un type — **Signaler un
problème**, **Suggestion**, **Question** ou **Autre** —, votre adresse email et votre message. La
version de l'application, la version de macOS et vos réglages audio sont joints pour faciliter le
diagnostic.

La case **Joindre le journal de diagnostic audio** ajoute le journal technique, sans lequel un
problème de son reste difficile à diagnostiquer. Reproduisez d'abord le problème, puis envoyez le
message : le journal est effacé à chaque lancement.

Ce journal se trouve dans votre dossier de départ, sous
`Library/Containers/com.math65.ttaccessible/Data/Library/Logs/TTAccessible/audio.log`.

**Aide → Signaler un problème…** ouvre plutôt le suivi de bugs du projet, qui reste le bon endroit
pour tout ce qui est public.
