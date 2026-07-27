---
title: Le mixeur du canal
description: Équilibrer tout un canal à l'oreille — volume, panoramique, sourdine et solo par personne, entièrement au clavier.
keywords: mixeur, tranche, volume, panoramique, sourdine, solo, clavier, VoiceOver
anchor: mixer
---

Le mixeur transforme les personnes présentes dans votre canal en une petite console : une **tranche**
par personne, avec son niveau, sa position stéréo, sa sourdine et son solo. Comme l'application
fabrique elle-même le mélange, vous pouvez placer quelqu'un à gauche et quelqu'un d'autre à droite,
ou remonter une personne trop faible, sans toucher aux autres.

**Commande-5** amène le curseur dans le mixeur. Quand vous êtes seul, il annonce simplement *Aucun
autre utilisateur dans ce canal.*

## Ce que contient une tranche

| Commande | Plage |
|---|---|
| Volume | de 0 à 100 %, par pas de 2 |
| Panoramique | de gauche à droite, centré par défaut |
| Volume du média | le niveau du fichier média que la personne diffuse |
| Panoramique du média | la position stéréo de cette diffusion |
| Sourdine | coupe à la fois la voix et le média de cette personne |
| Solo | coupe tous ceux qui ne sont pas en solo |

Chaque tranche porte le nom de la personne, suivi de son niveau et de la mention *coupé* le cas
échéant : passer d'une tranche à l'autre suffit donc à connaître l'état du canal.

## Le pilotage au clavier

Tant que le curseur est dans le mixeur, des touches simples le commandent directement. Elles sont
ignorées pendant que vous écrivez dans un champ de texte : le chat n'est jamais perturbé.

| Touche | Effet |
|---|---|
| Flèche haut / bas | Volume de la voix de la personne sélectionnée |
| Flèche gauche / droite | Panoramique de la voix |
| Commande-Haut / Commande-Bas | Volume du média — ou le volume principal hors d'une tranche |
| Commande-Gauche / Commande-Droite | Panoramique du média |
| V | Annonce le volume ; deux appuis le remettent à 50 % |
| P | Annonce le panoramique ; deux appuis le recentrent |
| M | Annonce l'état de la sourdine ; deux appuis la basculent |
| S | Annonce l'état du solo ; deux appuis le basculent |
| Commande-P | Annonce le panoramique du média ; deux appuis le recentrent |

Les deux appuis doivent se suivre rapidement. Maintenir une flèche la répète, d'abord lentement puis
plus vite, pour qu'un déplacement long reste maîtrisable.

Chaque action est annoncée immédiatement : vous pouvez équilibrer un canal entièrement à l'oreille,
sans jamais lire l'écran.

## Où vont ces réglages

Les niveaux du mixeur sont les mêmes que ceux de *Régler le volume…* (voir
[Les personnes que vous entendez](users.html)). Leur conservation après une reconnexion ou un
redémarrage dépend du réglage *Mémorisation des volumes par utilisateur*, dans
[Préférences → Audio](preferences.html#prefs-audio).
