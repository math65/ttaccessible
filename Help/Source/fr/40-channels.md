---
title: Les canaux
description: Rejoindre et quitter un canal, en créer ou en modifier un, régler le codec audio et échanger des fichiers.
keywords: canal, rejoindre, quitter, créer, modifier, supprimer, mot de passe, codec, Opus, fichiers
anchor: channels
---

## Rejoindre et quitter

- **Commande-J** rejoint le canal sélectionné dans l'arbre ; **Entrée** sur la ligne fait de même.
- **Commande-L** quitte le canal où vous êtes.

L'application confirme à voix haute — *Canal rejoint : …* ou *Canal quitté.* — et l'historique de
session en garde la trace.

Si le canal est protégé, son mot de passe vous est demandé. Une fois le bon mot de passe saisi, il
est conservé : les visites suivantes se font sans rien demander. La commande **Oublier le mot de
passe enregistré**, dans le menu contextuel de l'arbre, l'efface.

Deux options de [Préférences → Connexion](preferences.html#prefs-connection) automatisent tout cela :
*Rejoindre automatiquement le canal principal à la connexion* et *Rejoindre automatiquement le
dernier canal après une reconnexion*. Un serveur enregistré peut par ailleurs définir son propre
**Canal à rejoindre**.

## Créer et modifier un canal

| Raccourci | Commande |
|---|---|
| F7 | Créer un canal |
| Maj-F7 | Modifier le canal |
| F8 | Supprimer le canal |

La suppression est définitive : *Le canal et tous ses sous-canaux seront supprimés.*

Le formulaire d'un canal contient :

- **Nom du canal** et **Sujet**.
- **Mot de passe** — laissez vide pour un canal ouvert.
- **Nombre max d'utilisateurs**.
- **Quota de stockage des fichiers**, en Ko, Mo ou Go. Un quota de 0 signifie que seuls les
  administrateurs peuvent envoyer des fichiers.
- **Canal permanent** — le canal subsiste quand la dernière personne le quitte.
- **Transmission solo (un seul à la fois)**.
- **Désactiver l'activation vocale (PTT uniquement)**.
- **Pas d'enregistrement audio** — voir [Enregistrer](recording.html).
- **Rejoindre le canal après sa création**, à la création.

### Le codec audio

La section **Codec audio** règle l'encodeur Opus utilisé par tout le canal :

- **Canaux audio** — Mono ou Stéréo.
- **Fréquence d'échantillonnage**.
- **Débit (kbps)** — plus il est élevé, meilleure est la qualité et plus la bande passante augmente.
- **Mode d'application** — **VoIP** pour la parole, **Musique** pour la musique.

Les réglages que le formulaire n'affiche pas sont conservés tels quels lorsque vous modifiez un canal
existant.

## Les fichiers du canal

**Serveur → Fichiers du canal** (**Maj-Commande-F**) ouvre la liste des fichiers du canal, avec le
**Nom**, la **Taille** et la mention **Envoyé par**.

- **Envoyer…** dépose un fichier — la commande existe aussi dans **Serveur → Envoyer un fichier…**
  (**Maj-F5**).
- **Télécharger** récupère le fichier sélectionné ; **Entrée** fait la même chose.
- **Supprimer** le retire du canal, après confirmation. La touche **Suppr** fonctionne également.

Les transferts annoncent leur démarrage puis leur fin — *Envoi terminé* ou *Téléchargement terminé*.
Si le canal n'a plus de place, l'application signale que *Ce canal n'a pas assez d'espace de
stockage.*

Les fichiers ajoutés ou supprimés par d'autres apparaissent dans l'historique de session et peuvent
être annoncés.
