---
title: Les personnes que vous entendez
description: Régler le volume de quelqu'un, le couper localement, consulter ses informations et choisir ce que vous recevez de lui.
keywords: utilisateur, volume, balance, sourdine, abonnements, interception, informations, utilisateurs connectés
anchor: users
---

Toutes les commandes de cette page s'appliquent à la personne sélectionnée dans l'arbre des canaux,
et se trouvent aussi bien dans le menu **Utilisateur** que dans le menu contextuel de l'arbre.

## Volume et balance

**Commande-U** — *Régler le volume…* — ouvre une fenêtre avec deux curseurs, **Voix** et **Fichier
média**, ainsi que la balance stéréo entre le **Haut-parleur gauche** et le **Haut-parleur droit**.
Les changements s'appliquent au fur et à mesure que vous déplacez le curseur : vous pouvez donc
régler le niveau pendant que la personne parle. Annuler rétablit l'état initial.

L'échelle est régulière d'un bout à l'autre : *0 % = silence · 50 % = volume par défaut · 100 % =
volume maximum*.

La conservation de ces réglages dépend de *Mémorisation des volumes par utilisateur*, dans
[Préférences → Audio](preferences.html#prefs-audio) : jamais, le temps de la session, ou toujours.
Les niveaux sont propres à chaque serveur ; un réglage fait sur l'un ne se reporte pas sur l'autre.

Pour équilibrer tout un canal plus rapidement, voir [Le mixeur du canal](mixer.html).

## Couper quelqu'un localement

- **Maj-Commande-M** — *Couper localement* / *Rétablir localement*. Vous seul cessez de l'entendre.
- **Contrôle-Maj-Commande-M** — *Couper le flux média localement*, qui fait taire le fichier média
  diffusé par la personne tout en laissant sa voix audible.

Les deux sont annoncés, et les deux restent locaux à votre Mac : la personne n'en est pas informée.

## Les informations d'une personne

**Commande-I** ouvre **Informations utilisateur** : identifiant, pseudo, nom d'utilisateur, mode et
message de statut, genre, type de compte, qualité d'opérateur de canal, adresse IP, client, version
et perte de paquets audio.

## Tout le monde sur le serveur

**Serveur → Utilisateurs connectés…** (**Maj-Commande-W**) dresse la liste de toutes les personnes
connectées, et pas seulement de votre canal, avec leur pseudo, leur message de statut, leur nom
d'utilisateur, leur canal, leur adresse IP, leur version et leur identifiant. De là, vous pouvez
consulter les informations d'une personne, les copier, lui écrire en privé ou — avec les droits
nécessaires — la déplacer, l'expulser ou la bannir.

## Les abonnements

Le sous-menu **Utilisateur → Abonnements** détermine ce que vous recevez de la personne
sélectionnée. Chaque entrée s'active ou se désactive :

| Raccourci | Abonnement |
|---|---|
| Contrôle-1 | Messages privés |
| Contrôle-2 | Messages de canal |
| Contrôle-3 | Messages généraux |
| Contrôle-4 | Audio |
| Contrôle-5 | Partage d'écran |
| Contrôle-6 | Fichier média |

Désactiver **Audio** pour quelqu'un est un désabonnement côté serveur : sa voix ne vous est plus
envoyée du tout, contrairement à une simple sourdine locale.

### Les interceptions

Le même sous-menu propose ensuite les interceptions, qui demandent les droits correspondants et
permettent à un administrateur de recevoir ce qui ne lui est pas destiné :

| Raccourci | Interception |
|---|---|
| Contrôle-Maj-1 | Intercepter les messages privés |
| Contrôle-Maj-2 | Intercepter les messages de canal |
| Contrôle-Maj-4 | Intercepter l'audio |
| Contrôle-Maj-5 | Intercepter le partage d'écran |
| Contrôle-Maj-6 | Intercepter le fichier média |

Les abonnements appliqués à tout le monde dès la connexion se règlent dans
[Préférences → Connexion](preferences.html#prefs-connection), sous **Abonnements par défaut** et
**Interceptions par défaut**.
