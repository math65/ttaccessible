---
title: Parler dans un canal
description: Activer votre micro, utiliser le push-to-talk, régler les volumes et vérifier que vous êtes bien à l'antenne.
keywords: micro, microphone, push-to-talk, PTT, sourdine, volume principal, retour audio, état audio
anchor: talking
---

Vous pouvez parler dès que vous avez rejoint un canal. tt-Accessible peut garder votre micro ouvert,
ou n'envoyer votre voix que pendant que vous maintenez une touche.

## Activer ou couper le micro

Appuyez sur Maj + Commande + A. tt-Accessible confirme par *Micro activé* ou *Micro coupé*, et le
bouton de la barre d'outils indique son état.

Il faut d'abord être dans un canal. Ailleurs, tt-Accessible répond *Vous devez rejoindre un canal
avant d'activer le micro.*

## Choisir la façon dont votre micro transmet

1. Ouvrez les Préférences, puis cliquez sur Audio dans la barre latérale.
2. Cliquez sur le menu local **Mode du microphone**, puis choisissez l'une des options suivantes :
   - **Toujours actif** — le micro reste ouvert une fois que vous l'avez activé.
   - **Push-to-talk** — vous ne transmettez que pendant que vous maintenez une touche.
   - **Les deux** — Maj + Commande + A ouvre une transmission continue, et maintenir la touche de
     push-to-talk transmet quoi qu'il arrive.
3. Pour le push-to-talk, cliquez sur **Touche de push-to-talk**, puis appuyez sur la touche à
   maintenir. N'importe quelle touche convient, même une seule, ou une combinaison de touches de
   modification seule comme Commande + Contrôle. Appuyez sur Supprimer pour l'effacer.

Tant qu'aucune touche n'est enregistrée, le push-to-talk reste inactif et le micro transmet comme en
mode « toujours actif ». tt-Accessible vous en avertit dans le même volet.

Deux options complètent le tableau, juste en dessous :

- **Jouer un son au début et à la fin de la transmission**, qui est activée.
- **Le push-to-talk fonctionne même quand une autre app est au premier plan**, activée elle aussi.
  Un réglage équivalent existe pour l'activation du micro, désactivé.

## Utiliser votre micro depuis une autre app

Quand l'une de ces options est activée, le raccourci répond où que vous soyez : dans votre
navigateur, dans votre éditeur audio, n'importe où.

macOS remet la touche à tt-Accessible avant que l'app au premier plan la voie : rien ne s'écrit là
où vous travaillez. En contrepartie, cette app ne reçoit plus du tout la touche. Si votre éditeur
audio met en pause avec Contrôle + Espace et que vous choisissez Contrôle + Espace ici, il ne met
plus en pause tant que le raccourci est défini. Choisissez-en un que vous n'utilisez pas ailleurs :
une touche de fonction de F13 à F19 est un choix sûr.

Bon à savoir également :

- Un raccourci ordinaire ne demande aucune autorisation.
- Seule exception, une combinaison de touches de modification seules, comme Commande + Contrôle :
  macOS demande l'autorisation « Surveillance des saisies » la première fois, et l'app au premier
  plan reçoit quand même les touches.
- Une touche qui écrit — une lettre, la barre d'espace, Retour, une flèche — est refusée. Elle
  empêcherait ce caractère d'atteindre le moindre champ de texte, y compris la zone de discussion
  ici.
- Tant qu'un champ de mot de passe est actif, où que ce soit sur votre Mac, macOS suspend le
  raccourci. Il refonctionne dès que vous quittez ce champ.

## Régler les volumes

La fenêtre principale comporte trois curseurs, chacun avec l'action VoiceOver *Réinitialiser à
50 %* :

- **Volume d'entrée** — le niveau auquel votre micro est envoyé.
- **Volume de sortie** — le niveau auquel vous entendez tout le monde.
- **Volume des effets sonores** — le niveau des sons de notification.

Pour tout couper ou tout rétablir d'un coup, appuyez sur Commande + M.

Pour régler le niveau d'une seule personne, consultez
[Régler ce que vous entendez de chaque personne](users.html) et
[Équilibrer un canal avec le mixeur](mixer.html).

## Vérifier qu'on vous entend

- Pour entendre votre propre voix par le canal, appuyez sur Maj + Commande + H. Si vous vous
  entendez, vous êtes à l'antenne.
- Pour connaître l'état audio, appuyez sur F9.
- Pour tester votre micro avant de vous connecter, ouvrez les Préférences, cliquez sur Audio, puis
  cliquez sur **Aperçu audio**.

Si tt-Accessible annonce *Transmission bloquée par l'opérateur du canal*, un opérateur vous a retiré
le droit de parler dans ce canal.

**Voir aussi :** [Configurer vos périphériques audio](audio-setup.html) ·
[Si quelque chose ne fonctionne pas](troubleshooting.html)
