---
title: Découvrir la fenêtre de tt-Accessible
description: Circuler entre les cinq zones de la fenêtre de session, lire l'arbre des canaux et changer de pseudo ou de statut.
keywords: fenêtre principale, zones, focus, arbre des canaux, historique de session, barre audio, pseudo, statut
anchor: main-window
---

Une fois connecté, la fenêtre s'intitule Serveur connecté, suivi du nom du serveur. Elle se partage
en deux volets. Une barre latérale réunit le nom du serveur, ses lignes d'état, le bouton du micro
et l'arbre des canaux ; le volet voisin contient le mixeur, le chat, la saisie du message et
l'historique de session. Tout s'y trouve : vous n'avez jamais besoin d'en sortir.

La séparation entre les deux volets se déplace, et tt-Accessible retient où vous l'avez laissée.

## Circuler entre les zones

Appuyez sur l'un de ces raccourcis pour placer le focus clavier — et avec lui le curseur VoiceOver —
là où vous en avez besoin :

| Raccourci | Zone |
|---|---|
| Commande + 1 | Zone principale : l'arbre des canaux et des utilisateurs |
| Commande + 2 | Historique du chat |
| Commande + 3 | Saisie du message |
| Commande + 4 | Historique de session |
| Commande + 5 | Mixeur du canal |

Ces raccourcis fonctionnent aussi quand la fenêtre Messages privés est au premier plan : Commande +
1, Commande + 2 et Commande + 3 y atteignent la liste des conversations, l'historique et le champ de
saisie. Hors session, Commande + 1 ramène la fenêtre Serveurs TeamTalk.

## Lire l'arbre des canaux

L'arbre présente les canaux du serveur et, sous chacun, les personnes qui s'y trouvent. Utilisez les
flèches pour le parcourir et appuyez sur Retour pour rejoindre le canal sélectionné. Pour connaître
les actions disponibles sur une ligne, cliquez dessus en maintenant la touche Contrôle enfoncée, ou
utilisez le rotor d'actions de VoiceOver.

Chaque ligne est annoncée avec ce qui la caractérise :

- Un canal ajoute *canal actuel*, *protégé par mot de passe* ou *caché* quand c'est le cas, et lit
  son sujet lorsqu'il en a un.
- Une personne ajoute *vous*, *administrateur*, *opérateur du canal*, *parle*, *absent* ou
  *question*.

Pour modifier l'ordre des canaux, ouvrez les Préférences, cliquez sur Connexion, puis utilisez le
menu local **Trier les canaux par**.

## Suivre ce qui se passe dans la session

L'historique de session rassemble les événements de la session : connexions, arrivées et départs,
changements de canal, expulsions, modifications d'abonnement, fichiers ajoutés ou supprimés, absence
automatique et diffusions média. Pour choisir lesquels sont annoncés, consultez
[Choisir les sons et les annonces](sounds-announcements.html).

Pour conserver la conversation, appuyez sur Maj + Commande + S.

## Utiliser les commandes audio

Le bouton du micro se trouve dans la barre latérale, sous l'arbre des canaux.

Les volumes, eux, sont réunis en tête du mixeur du canal, sur une bande appelée Général :
**Volume de sortie**, **Volume des médias**, **Volume du microphone** et **Volume des effets
sonores**. Commande + 5 vous y dépose ; consultez
[Équilibrer un canal avec le mixeur](mixer.html).

Pour connaître l'état audio à tout moment — sortie active ou non, micro en train de transmettre ou
non, enregistrement en cours ou non —, appuyez sur F9.

## Changer de pseudo ou de statut

- Pour changer de pseudo, appuyez sur F5. Laissez le champ vide pour revenir à votre pseudo par
  défaut.
- Pour changer de statut, appuyez sur F6, puis choisissez **Disponible**, **Absent** ou
  **Question**, un genre et, si vous le souhaitez, un message de statut.

tt-Accessible peut aussi vous passer en absent tout seul quand vous cessez d'utiliser le clavier.
Consultez [Modifier les réglages de tt-Accessible](preferences.html#prefs-general).

## Regarder une vidéo

Quand quelqu'un diffuse un fichier vidéo dans le canal, un panneau Vidéo apparaît ; vous pouvez
l'afficher ou le masquer. Il indique *Pas de vidéo* quand rien ne passe.

## Si la connexion tombe

La fenêtre affiche **Reconnexion en cours** et tt-Accessible tente de rétablir la session, en
rejoignant le canal où vous étiez. Pour activer ou désactiver ces comportements, ouvrez les
Préférences et cliquez sur Connexion.

Pour quitter le serveur, appuyez sur F2. Si vous aviez ouvert le serveur depuis un fichier `.tt` ou
un lien sans l'enregistrer, tt-Accessible vous propose d'abord de le sauvegarder.

**Voir aussi :** [Rejoindre et gérer des canaux](channels.html) ·
[Parler dans un canal](talking.html) · [Raccourcis clavier](shortcuts.html)
