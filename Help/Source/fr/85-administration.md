---
title: Gérer les utilisateurs, les bannissements et les réglages du serveur
description: Promouvoir des opérateurs, expulser ou bannir, déplacer des personnes, et modifier les comptes et les propriétés du serveur.
keywords: opérateur, expulser, bannir, déplacer, comptes, droits, propriétés du serveur, statistiques
anchor: administration
---

Si votre compte dispose des droits correspondants, vous pouvez modérer les canaux d'un serveur et
modifier ses réglages. Les commandes que vous n'avez pas le droit d'utiliser restent grisées.

## Promouvoir quelqu'un opérateur de canal

Sélectionnez la personne dans l'arbre des canaux, puis appuyez sur Contrôle + Commande + O. Appuyez
de nouveau pour lui retirer ce statut. Si vous n'êtes pas vous-même opérateur et que le canal
possède un mot de passe d'opérateur, tt-Accessible vous le demande.

## Retirer quelqu'un d'un canal ou du serveur

Sélectionnez la personne, puis effectuez l'une des opérations suivantes :

- **La retirer de son canal :** appuyez sur Commande + K.
- **La déconnecter du serveur :** appuyez sur Maj + Commande + K.
- **La déconnecter et la bannir :** choisissez Utilisateur > Expulser et bannir, puis choisissez de
  bannir l'adresse IP ou le nom d'utilisateur.

Chaque commande demande confirmation. Pour supprimer cette étape sur les deux premières, ouvrez les
Préférences, cliquez sur Connexion, puis sélectionnez **Ne pas demander de confirmation lors de
l'expulsion**. « Expulser et bannir » demande toujours confirmation.

## Déplacer des personnes vers un autre canal

- Pour déplacer une personne, sélectionnez-la, appuyez sur Option + Commande + X, puis choisissez le
  canal de destination.
- Pour déplacer tout un canal, cliquez dessus en maintenant la touche Contrôle enfoncée, puis
  choisissez **Déplacer tout le monde**. Sélectionnez les personnes à déplacer — **Tout
  sélectionner** et **Tout désélectionner** vous y aident —, choisissez la destination dans le menu
  local **Déplacer vers le canal**, puis cliquez sur Déplacer.

## Gérer les bannissements

1. Choisissez Serveur > Utilisateurs bannis, ou appuyez sur Maj + Commande + B.
2. Effectuez l'une des opérations suivantes :
   - **Lever un bannissement :** sélectionnez-le, puis cliquez sur Débannir. La personne pourra se
     reconnecter.
   - **Ajouter un bannissement :** cliquez sur Ajouter, puis choisissez **Adresse IP** ou **Nom
     d'utilisateur** et saisissez la valeur.
   - **Mettre la liste à jour :** cliquez sur Rafraîchir.

## Gérer les comptes utilisateurs

1. Choisissez Serveur > Comptes utilisateurs, ou appuyez sur Maj + Commande + U.
2. Cliquez sur Ajouter, ou sélectionnez un compte et cliquez sur Modifier.
3. Dans l'onglet Essentiel, définissez le nom d'utilisateur, le mot de passe, le type de compte —
   **Défaut**, **Administrateur** ou **Désactivé** —, un canal initial et une note.
4. Dans l'onglet Droits, sélectionnez ce que le compte a le droit de faire. Vingt-quatre droits sont
   disponibles : connexions multiples, visibilité de tous les utilisateurs, création et modification
   de canaux, diffusion de messages, expulsion, bannissement, déplacement, qualité d'opérateur,
   envoi et téléchargement de fichiers, modification des propriétés du serveur, transmission de la
   voix, de la vidéo, du bureau et des fichiers média, verrouillage du pseudo ou du statut,
   enregistrement de la voix, visibilité des canaux masqués, et envoi de messages privés ou de
   canal. **Tout activer**, **Tout désactiver** et **Droits par défaut** les règlent d'un clic.
5. Dans l'onglet Avancé, définissez la limite de bande passante audio, où 0 signifie illimité, et
   les limites de commandes.
6. Cliquez sur Enregistrer.

Pour supprimer un compte, sélectionnez-le et cliquez sur Supprimer. Cette action est irréversible.

## Modifier les réglages du serveur

1. Choisissez Serveur > Propriétés du serveur, ou appuyez sur Maj + Commande + P.
2. Dans la section Général, définissez le nom du serveur, le message du jour, le nombre maximal
   d'utilisateurs, les délais d'expiration et les limites de connexion.
3. Dans la section Limites de débit, définissez les débits maximaux pour la voix, la vidéo, les
   fichiers média, le bureau partagé et le total, en octets par seconde, où 0 signifie illimité.
4. Cliquez sur Enregistrer.

La section Réseau et informations du serveur affiche les ports et les versions, à titre indicatif.

Pour que la configuration courante survive à un redémarrage du serveur, choisissez Serveur >
Enregistrer la configuration du serveur.

## Consulter l'activité du serveur

Choisissez Serveur > Statistiques du serveur, ou appuyez sur Maj + Commande + I, pour connaître la
durée de fonctionnement, le nombre d'utilisateurs accueillis, le pic, les données émises et reçues,
et les pings UDP et TCP.

**Voir aussi :** [Régler ce que vous entendez de chaque personne](users.html) ·
[Rejoindre et gérer des canaux](channels.html)
