---
title: La fenêtre principale
description: Les zones de la fenêtre de session, comment circuler avec Commande-1 à Commande-5, et ce qu'annonce l'arbre des canaux.
keywords: fenêtre principale, zones, focus, arbre des canaux, historique de session, barre audio, pseudo, statut
anchor: main-window
---

Une fois la session ouverte, la fenêtre s'intitule **Serveur connecté** suivi du nom du serveur. Tout
s'y trouve au même endroit.

## Les cinq zones

| Raccourci | Zone | Contenu |
|---|---|---|
| Commande-1 | Zone principale | L'arbre des canaux et des utilisateurs |
| Commande-2 | Historique du chat | Les messages échangés dans votre canal |
| Commande-3 | Saisie du message | Le champ de saisie et le bouton **Envoyer** |
| Commande-4 | Historique de session | Tout ce qui s'est passé pendant la session |
| Commande-5 | Mixeur du canal | Une tranche par personne que vous entendez |

Ces raccourcis déplacent le focus clavier — et avec lui le curseur VoiceOver —, ce qui évite de
parcourir toute la fenêtre pour atteindre la partie qui vous intéresse. Ils fonctionnent également
quand la fenêtre **Messages privés** est au premier plan : Commande-1, Commande-2 et Commande-3 y
atteignent la liste des conversations, l'historique et le champ de saisie. Hors session, Commande-1
ramène la fenêtre **Serveurs TeamTalk** et sélectionne la liste.

## L'arbre des canaux

L'arbre présente les canaux du serveur et, sous chacun, les personnes qui s'y trouvent. Les flèches
le parcourent, **Entrée** rejoint le canal sélectionné. Le clic droit — ou le rotor d'actions de
VoiceOver — ouvre le menu **Canal**, avec les commandes décrites dans [Les canaux](channels.html) et
[Les personnes que vous entendez](users.html).

Chaque ligne est annoncée avec ce qui la caractérise :

- Un canal ajoute *canal actuel*, *protégé par mot de passe* ou *caché* quand c'est le cas, et lit
  son sujet lorsqu'il en a un.
- Une personne ajoute *vous*, *administrateur*, *opérateur du canal*, *parle*, *absent* ou
  *question*.

L'ordre des canaux suit le réglage *Trier les canaux par* de
[Préférences → Connexion](preferences.html#prefs-connection) : par **Nom**, ou par **Nombre
d'utilisateurs (les plus peuplés d'abord)**.

## L'historique de session

L'historique de session rassemble les événements de la session : connexions, arrivées et départs,
changements de canal, expulsions, modifications d'abonnement, fichiers ajoutés ou supprimés, absence
automatique et diffusions média. Chaque entrée peut être annoncée à voix haute ou rester silencieuse
— voir [Sons et annonces](sounds-announcements.html).

Les horodatages s'affichent sous forme d'heure ou de durée relative — *il y a 2 min* — selon
l'option *Utiliser des horodatages relatifs* de
[Préférences → Général](preferences.html#prefs-general).

**Maj-Commande-S** exporte l'historique du chat dans un fichier.

## La barre audio

Sous les listes se trouvent :

- Le bouton du micro — **Activer le micro** ou **Couper le micro**.
- Trois curseurs : **Volume d'entrée**, **Volume de sortie** et **Volume des effets sonores**. Chacun
  propose l'action VoiceOver *Réinitialiser à 50 %*.

**F9** énonce l'état audio à tout moment : sortie active ou non, micro prêt ou en train de
transmettre, enregistrement en cours ou non.

## Votre identité sur le serveur

- **F5** — *Changer le pseudo*. Laissez le champ vide pour revenir à votre pseudo par défaut.
- **F6** — *Changer le statut* : un mode (**Disponible**, **Absent** ou **Question**), un genre et,
  si vous le souhaitez, un message de statut.

L'absence automatique peut aussi changer votre statut toute seule quand vous ne touchez plus au
clavier ; voir [Préférences → Général](preferences.html#prefs-general).

## La vidéo

Quand quelqu'un diffuse un fichier vidéo dans le canal, un panneau **Vidéo** repliable apparaît. Il
s'affiche ou se masque à volonté et indique *Pas de vidéo* quand rien ne passe.

## En cas de coupure

Si la connexion tombe, la fenêtre affiche **Reconnexion en cours…** et l'application tente de
rétablir la session — y compris en rejoignant le canal où vous étiez, si les options correspondantes
sont activées dans [Préférences → Connexion](preferences.html#prefs-connection).

## Quitter la session

**F2** vous déconnecte. Si le serveur avait été ouvert depuis un fichier `.tt` ou un lien sans jamais
être enregistré, l'application propose d'abord de le sauvegarder.
