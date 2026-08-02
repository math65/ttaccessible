---
title: Si quelque chose ne fonctionne pas
description: Que vérifier quand vous n'entendez personne, quand personne ne vous entend, quand il y a de l'écho, et comment joindre le développeur.
keywords: problème, pas de son, micro, écho, autorisation, trousseau, journal, assistance, bug
anchor: troubleshooting
---

La plupart des problèmes audio tiennent à quelques réglages. Appuyez sur F9 à tout moment pour
connaître l'état audio : cela répond déjà à la première question.

## Si vous n'entendez personne

1. Vérifiez que le volume principal n'est pas coupé : appuyez sur Commande + M.
2. Vérifiez le curseur **Volume de sortie** dans la fenêtre principale.
3. Ouvrez les Préférences, cliquez sur Audio, puis vérifiez que **Périphérique de sortie** n'est pas
   réglé sur **Aucune sortie audio** ni sur un appareil que vous n'utilisez plus. Cliquez sur
   **Actualiser les périphériques** pour reconstruire la liste.
4. Vérifiez si cette personne est coupée pour vous : sa ligne indique *coupé*, et Maj + Commande + M
   la rétablit. Vérifiez aussi son niveau dans [le mixeur](mixer.html).
5. Vérifiez que vous êtes toujours abonné à son audio — consultez
   [Régler ce que vous entendez de chaque personne](users.html).

## Si personne ne vous entend

1. Vérifiez que vous avez rejoint un canal. Ailleurs, tt-Accessible répond *Vous devez rejoindre un
   canal avant d'activer le micro.*
2. Vérifiez que le micro est activé : appuyez sur Maj + Commande + A.
3. Si vous utilisez le push-to-talk, vérifiez que vous avez enregistré une touche. Tant que ce n'est
   pas fait, le micro se comporte comme en mode « toujours actif ».
4. Si tt-Accessible indique *L'accès au micro a été refusé par macOS*, choisissez le menu Pomme >
   Réglages Système, cliquez sur Confidentialité et sécurité, cliquez sur Microphone, puis activez
   tt-Accessible.
5. Ouvrez les Préférences, cliquez sur Audio, puis vérifiez le **Périphérique d'entrée** et la
   configuration **Canaux d'entrée**. Sur une interface audio, le micro est rarement sur l'entrée 1.
6. Si tt-Accessible annonce *Transmission bloquée par l'opérateur du canal*, un opérateur vous a
   retiré le droit de parler.

Pour trancher, appuyez sur Maj + Commande + H : si vous vous entendez par le canal, vous êtes à
l'antenne.

## Si un raccourci du micro ne répond plus

1. Vérifiez si un champ de mot de passe est actif quelque part sur votre Mac — dans une autre app ou
   sur un site web. Tant que c'est le cas, macOS suspend les raccourcis qui fonctionnent depuis les
   autres apps, et les rétablit dès que vous quittez ce champ.
2. Ouvrez les Préférences, puis cliquez sur Audio. Quand un raccourci ne peut pas fonctionner,
   tt-Accessible l'indique juste sous le bouton qui le définit. Deux causes : votre touche de
   push-to-talk et votre raccourci d'activation du micro portent les mêmes touches, et un seul des
   deux peut fonctionner ; ou la touche choisie écrit dans les champs de texte, ce qui est refusé.
3. Enregistrez une autre touche : cliquez sur le bouton, puis appuyez sur celle que vous voulez.

## Si tout le monde s'entend revenir

Vos haut-parleurs sont repris par votre micro. Utilisez un casque, ou ouvrez les Préférences,
cliquez sur Audio, puis réglez **Traitement du micro** sur **Annulation d'écho + réduction de
bruit**. À partir de macOS 14.2, cette option annule aussi VoiceOver et les sons du système.

## Si le son s'arrête après un branchement

tt-Accessible détecte les changements de périphérique et redémarre son moteur audio tout seul. Si
quelque chose cloche malgré tout, ouvrez les Préférences, cliquez sur Audio, puis cliquez sur
**Actualiser les périphériques**. Si le micro s'est arrêté, tt-Accessible indique *Le micro s'est
arrêté après un changement de périphérique audio. Réactivez-le.*

## Si l'enregistrement refuse de démarrer

Le canal a probablement été créé avec l'option **Pas d'enregistrement audio**, et tt-Accessible
annonce *L'enregistrement n'est pas autorisé dans ce canal.* Seul un compte disposant du droit
d'enregistrer la voix peut passer outre. Consultez [Enregistrer une conversation](recording.html).

## Si la diffusion d'une app ne fonctionne pas

- La diffusion de l'audio d'une app ou de VoiceOver nécessite macOS 13 ou une version ultérieure, et
  parcourir les apps qui ne sont pas lancées nécessite macOS 14.2 ou une version ultérieure.
- Si tt-Accessible répond *La source sélectionnée n'a aucun audio à capturer pour le moment*,
  vérifiez que l'app visée tourne réellement et produit du son.

Consultez [Diffuser du son dans un canal](streaming.html).

## Si le serveur refuse votre mot de passe

- Cliquez sur **Modifier les identifiants** dans l'alerte pour corriger votre nom d'utilisateur ou
  votre mot de passe.
- Si le serveur utilise la connexion web BearWare, vérifiez que votre compte est connecté : ouvrez
  les Préférences, puis cliquez sur BearWare.
- Si macOS refuse l'accès au mot de passe enregistré, ouvrez Trousseau d'accès, supprimez l'entrée
  **ttaccessible** correspondant à ce serveur, puis réessayez.

## Si la connexion tombe sans arrêt

Ouvrez les Préférences, cliquez sur Connexion, puis sélectionnez **Buffer de gigue adaptatif**, qui
améliore l'audio sur les connexions instables. La reconnexion automatique et le retour dans votre
dernier canal sont déjà activés dans le même volet.

## Signaler un problème

1. Choisissez Aide > Contacter le développeur.
2. Cliquez sur le menu local **Type**, puis choisissez **Signaler un problème**, **Suggestion**,
   **Question** ou **Autre**.
3. Saisissez votre adresse e-mail et votre message.
4. Pour qu'un problème de son soit diagnosticable, sélectionnez **Joindre le journal de diagnostic
   audio**. Reproduisez d'abord le problème, puis envoyez le message : le journal est effacé à
   chaque ouverture de l'app.
5. Cliquez sur Envoyer.

La version de l'app, la version de macOS et vos réglages audio sont joints pour faciliter le
diagnostic. Le journal lui-même se trouve dans votre dossier de départ, sous
`Library/Containers/com.math65.ttaccessible/Data/Library/Logs/TTAccessible/audio.log`.

Pour signaler quelque chose publiquement, choisissez plutôt Aide > Signaler un problème.

**Voir aussi :** [Configurer vos périphériques audio](audio-setup.html) ·
[Parler dans un canal](talking.html)
