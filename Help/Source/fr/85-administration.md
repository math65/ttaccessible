---
title: Administration
description: Opérateurs de canal, expulsions, bannissements, déplacements, comptes utilisateurs, propriétés et statistiques du serveur.
keywords: opérateur, expulser, bannir, déplacer, comptes, droits, propriétés du serveur, statistiques
anchor: administration
---

Les commandes de cette page demandent les droits correspondants sur votre compte. Celles que vous
n'avez pas le droit d'utiliser restent grisées.

## L'opérateur de canal

**Contrôle-Commande-O** promeut la personne sélectionnée opérateur du canal, ou lui retire ce statut.
Si vous n'êtes pas vous-même opérateur mais que le canal possède un mot de passe d'opérateur, celui-ci
vous est demandé. Le changement est annoncé : *… est maintenant opérateur du canal*.

## Les expulsions

| Raccourci | Commande |
|---|---|
| Commande-K | Expulser du canal — la personne est retirée de son canal actuel |
| Maj-Commande-K | Expulser du serveur — la personne est complètement déconnectée |
| — | Expulser et bannir — expulsion, puis bannissement par **adresse IP** ou par **nom d'utilisateur** |

Chacune demande confirmation. L'option *Ne pas demander de confirmation lors de l'expulsion*, dans
[Préférences → Connexion](preferences.html#prefs-connection), supprime cette étape pour les deux
premières ; « Expulser et bannir » demande toujours confirmation.

## Déplacer des personnes

- **Option-Commande-X** — *Déplacer vers un canal…* — déplace la personne sélectionnée vers le canal
  de votre choix.
- **Déplacer tout le monde…**, dans le menu contextuel de l'arbre, déplace un canal entier d'un coup.
  La fenêtre liste chaque personne avec une case à cocher, propose **Tout sélectionner** et **Tout
  désélectionner**, ainsi qu'un menu **Déplacer vers le canal :**. Le résultat est annoncé une seule
  fois : *n utilisateurs sur n déplacés vers …*

## Les bannissements

**Serveur → Utilisateurs bannis…** (**Maj-Commande-B**) présente les bannissements du serveur :
pseudo, nom d'utilisateur, type, date, auteur, canal et adresse IP. Vous pouvez **Rafraîchir** la
liste, **Débannir** l'entrée sélectionnée — *Cette personne pourra se reconnecter au serveur* — ou
**Ajouter…** un bannissement par **Adresse IP** ou par **Nom d'utilisateur**.

## Les comptes utilisateurs

**Serveur → Comptes utilisateurs…** (**Maj-Commande-U**) liste les comptes déclarés sur le serveur,
avec leur nom d'utilisateur, le pseudo actuellement en ligne, le mot de passe, le type (**Défaut**,
**Administrateur** ou **Désactivé**), une note et la dernière connexion.

**Ajouter…** et **Modifier…** ouvrent un formulaire à trois onglets :

- **Essentiel** — nom d'utilisateur, mot de passe, type de compte, canal initial, note.
- **Droits** — vingt-quatre interrupteurs, avec **Tout activer**, **Tout désactiver** et **Droits par
  défaut**. Ils couvrent les connexions multiples, la visibilité de tous les utilisateurs, la
  création de canaux temporaires, la modification des canaux, la diffusion de messages, l'expulsion,
  le bannissement, le déplacement, le fait de devenir opérateur, l'envoi et le téléchargement de
  fichiers, la modification des propriétés du serveur, la transmission de la voix, de la vidéo, du
  bureau et des fichiers média, le verrouillage du pseudo ou du statut, l'enregistrement de la voix,
  la visibilité des canaux masqués et l'envoi de messages privés ou de canal.
- **Avancé** — limite de bande passante audio (0 signifie illimité), limite de commandes et
  intervalle.

La suppression d'un compte est irréversible.

## Les propriétés du serveur

**Serveur → Propriétés du serveur…** (**Maj-Commande-P**) ouvre les réglages du serveur lui-même, en
trois sections :

- **Général** — nom du serveur, message du jour, nombre maximal d'utilisateurs, timeout utilisateur,
  délai de connexion, nombre maximal de tentatives, nombre maximal de connexions par IP, sauvegarde
  automatique.
- **Limites de débit** — débits maximaux pour la voix, la vidéo, les fichiers média, le bureau
  partagé et le total, en octets par seconde, où 0 signifie illimité.
- **Réseau et informations du serveur** — ports TCP et UDP, version du serveur et version du
  protocole, donnés à titre d'information.

**Serveur → Enregistrer la configuration du serveur** écrit la configuration courante sur le serveur
pour qu'elle survive à un redémarrage.

## Les statistiques

**Serveur → Statistiques du serveur** (**Maj-Commande-I**) indique la durée de fonctionnement, le
nombre total d'utilisateurs accueillis, le pic, les données émises et reçues au total et pour la
voix, ainsi que les pings UDP et TCP.
