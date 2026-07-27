---
title: Prendre la parole
description: Activer le micro, utiliser le push-to-talk, régler les volumes et s'entendre soi-même.
keywords: micro, microphone, push-to-talk, PTT, sourdine, volume principal, retour audio, état audio
anchor: talking
---

## Activer le micro

**Maj-Commande-A** active ou coupe le micro. L'application confirme par *Micro activé.* ou *Micro
coupé.*, et le bouton de la barre d'outils indique son état.

Il faut d'abord être dans un canal : ailleurs, l'application répond *Vous devez rejoindre un canal
avant d'activer le micro.*

## Les modes du microphone

[Préférences → Audio](preferences.html#prefs-audio) propose trois façons de travailler, sous **Mode
du microphone** :

- **Toujours actif** — une fois activé, le micro reste ouvert. C'est le réglage par défaut.
- **Push-to-talk (maintenez une touche pour parler)** — vous ne transmettez que pendant que vous
  maintenez une touche.
- **Les deux (coupure avec push-to-talk)** — Maj-Commande-A ouvre une transmission continue, et
  maintenir la touche de push-to-talk transmet dans tous les cas. La relâcher recoupe le son,
  jusqu'à ce que vous appuyiez de nouveau sur Maj-Commande-A ou que vous mainteniez la touche.

Pour le push-to-talk, il faut enregistrer une touche : activez **Touche de push-to-talk**, puis
appuyez sur la touche à maintenir. N'importe quelle touche convient, même une seule ; une
combinaison de touches de modification seule — Commande-Contrôle, par exemple — fonctionne aussi.
La touche Supprimer efface le réglage. Tant qu'aucune touche n'est définie, l'application prévient
que le push-to-talk est inactif et que le micro reste ouvert comme en mode « toujours actif ».

Deux options complètent le tableau :

- **Jouer un son au début et à la fin de la transmission** — activé par défaut.
- **Le push-to-talk fonctionne même quand une autre app est au premier plan** — activé par défaut. Un
  réglage équivalent existe pour le raccourci d'activation du micro, désactivé par défaut. Tous deux
  reposent sur l'autorisation « Surveillance des saisies », que macOS demande la première fois.
  Comme l'application fonctionne en bac à sable, la touche est détectée mais atteint quand même
  l'application au premier plan : préférez donc une combinaison de touches de modification seules, ou
  une touche de fonction de F13 à F19 — ni l'une ni l'autre n'écrit quoi que ce soit là où vous
  travaillez.

## Les volumes

Trois curseurs sont posés dans la fenêtre principale, chacun avec l'action VoiceOver
*Réinitialiser à 50 %* :

- **Volume d'entrée** — le niveau auquel votre micro est envoyé.
- **Volume de sortie** — le niveau auquel vous entendez tout le monde.
- **Volume des effets sonores** — le niveau des sons de notification.

**Commande-M** coupe et rétablit le volume principal, en annonçant *Volume principal coupé* ou
*Volume principal rétabli*.

Chaque personne se règle par ailleurs séparément : voir
[Les personnes que vous entendez](users.html) et [Le mixeur du canal](mixer.html).

## S'entendre soi-même

**Maj-Commande-H** active et désactive le retour audio : votre propre voix vous revient par le canal.
C'est le moyen le plus rapide de vérifier que votre micro, votre gain et votre traitement sont bien
réglés. L'application annonce *Retour audio activé* ou *Retour audio désactivé*.

Pour un essai avant même de vous connecter, utilisez le bouton **Aperçu audio** de
[Préférences → Audio](preferences.html#prefs-audio).

## Savoir où vous en êtes

**F9** énonce l'état audio : sortie active ou non, micro prêt ou en train de transmettre,
enregistrement en cours. C'est la façon la plus directe de répondre à la question « est-ce que je
suis vraiment à l'antenne ? » sans quitter ce que vous faites.

Si l'application annonce *Transmission bloquée par l'opérateur du canal*, un opérateur vous a retiré
le droit de parler dans ce canal.
