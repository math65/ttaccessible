---
title: Configurer vos périphériques audio
description: Choisir vos périphériques d'entrée et de sortie, supprimer l'écho et le bruit de fond, et tester votre micro.
keywords: périphérique audio, entrée, sortie, annulation d'écho, AEC, réduction de bruit, aperçu, canaux, canaux de sortie, interface, casque
anchor: audio-setup
---

Vous pouvez choisir les périphériques utilisés par tt-Accessible et la façon dont il traite votre
micro. Les changements prennent effet immédiatement, même en pleine session.

## Choisir vos périphériques

1. Ouvrez les Préférences, puis cliquez sur Audio dans la barre latérale.
2. Cliquez sur le menu local **Périphérique de sortie**, puis choisissez **Par défaut du système**,
   un périphérique précis, ou **Aucune sortie audio** pour faire tourner tt-Accessible en silence.
3. Cliquez sur le menu local **Périphérique d'entrée**, puis choisissez **Par défaut du système** ou
   un micro précis.

Si vous branchez ou débranchez un appareil et qu'il n'apparaît pas, cliquez sur **Actualiser les
périphériques**. tt-Accessible détecte de toute façon ces changements tout seul et redémarre son
moteur audio : un casque connecté en cours de session est pris en compte sans que vous ayez à
intervenir.

Si vous débranchez un périphérique que vous avez choisi, il reste sélectionné dans son menu, avec
la mention *non connecté*. En attendant son retour, le son passe par la sortie par défaut du système
et le micro est coupé. Dès que vous le rebranchez, tt-Accessible s'en sert de nouveau.

Si votre micro était activé, il se réactive lui aussi, avec le son habituel, à trois conditions :
vous êtes toujours connecté au même serveur, vous ne l'avez ni activé ni coupé entre-temps, et vous
n'avez pas choisi un autre micro.

## Choisir les sorties utilisées

Sur une interface audio ou une console qui possède plusieurs paires de sorties, vous pouvez faire
jouer tt-Accessible sur une autre paire que les sorties 1 et 2.

1. Ouvrez les Préférences, puis cliquez sur Audio.
2. Cliquez sur le menu local **Canaux de sortie**, puis choisissez une option :
   - **Auto (sorties 1 et 2)** : la première paire du périphérique, comme dans les versions
     précédentes.
   - **Sorties 3 et 4**, **Sorties 5 et 6**, etc. : le son est joué en stéréo sur cette paire.
   - **Sortie 7 mono**, etc. : le son est ramené en mono et joué sur cette seule sortie.

Les paires stéréo sont en haut du menu et les sorties seules en dessous : même sur une grande
interface, la paire voulue se trouve vite.

Le menu n'apparaît que si le périphérique a plus de deux sorties ; un casque ou les haut-parleurs
intégrés n'en ont pas besoin. tt-Accessible retient votre choix pour chaque périphérique et
l'applique aussitôt, sans couper le son. Si le périphérique passe dans un mode qui offre moins de
sorties, ou si vous le remplacez par un périphérique stéréo, le menu revient sur Auto ; votre choix
réapparaît quand vous rebranchez le périphérique d'origine.

## Supprimer l'écho et le bruit de fond

1. Ouvrez les Préférences, puis cliquez sur Audio.
2. Cliquez sur le menu local **Traitement du micro**, puis choisissez l'une des options suivantes :
   - **Aucun** — votre micro part tel quel.
   - **Réduction de bruit** — supprime le bruit de fond de votre microphone.
   - **Annulation d'écho + réduction de bruit** — retire en plus le son de vos haut-parleurs de ce
     que vous envoyez.

C'est l'annulation d'écho qui permet de travailler sans casque : sans elle, tout le monde s'entend
revenir par votre micro. À partir de macOS 14.2, tt-Accessible utilise comme référence le son
réellement produit par votre Mac : VoiceOver et les sons du système sont donc annulés au même titre
que les voix du canal. Sur les versions antérieures, seul l'audio de TeamTalk peut l'être.

## Choisir les entrées utilisées

Cliquez sur le menu local **Canaux d'entrée**, juste sous le menu Périphérique d'entrée, puis
choisissez **Auto**, une entrée mono, une paire stéréo, ou une somme mono de deux entrées. Ce réglage compte avec une interface audio, où le micro
est rarement sur l'entrée 1.

Si vous changez de périphérique et que la configuration ne convient plus, tt-Accessible revient sur
Auto et vous le signale.

## Tester votre micro

1. Ouvrez les Préférences, puis cliquez sur Audio.
2. Cliquez sur **Aperçu audio**. Votre micro vous est renvoyé avec le traitement sélectionné, sans
   être connecté à quoi que ce soit.
3. Cliquez sur **Arrêter l'aperçu** pour mettre fin à l'essai.

En session, appuyez plutôt sur Maj + Commande + H pour vous entendre à travers le canal.

## Conserver les niveaux réglés pour les autres

Dans le volet Audio, sous **Mémorisation des volumes par utilisateur**, sélectionnez l'une des
options suivantes :

- **Désactivé** — tous les niveaux reviennent à 50 % à la reconnexion.
- **Session en cours seulement** — les niveaux sont oubliés à la fermeture.
- **Toujours** — les niveaux sont mémorisés d'un lancement à l'autre.

Les niveaux sont propres à chaque serveur : un réglage fait sur l'un ne se reporte jamais sur les
autres.

**Voir aussi :** [Parler dans un canal](talking.html) ·
[Si quelque chose ne fonctionne pas](troubleshooting.html)
