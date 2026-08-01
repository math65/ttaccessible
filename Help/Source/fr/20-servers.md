---
title: Ajouter un serveur et s'y connecter
description: Ajouter, modifier et trier vos serveurs TeamTalk, les importer et les exporter, et se connecter avec un compte BearWare.
keywords: serveur, serveurs enregistrés, import, export, fichier tt, lien tt, BearWare, connexion web
anchor: servers
---

Vous pouvez conserver autant de serveurs TeamTalk que vous le souhaitez dans la fenêtre Serveurs
TeamTalk, qui affiche pour chacun son nom, son hôte, ses ports TCP et UDP, et s'il est sécurisé. Les
mots de passe sont conservés dans votre trousseau de session, pas dans les fichiers de l'app.

## Se connecter à un serveur

1. Accédez à la fenêtre Serveurs TeamTalk dans tt-Accessible.
2. Sélectionnez un serveur dans la liste à l'aide des flèches.
3. Appuyez sur Retour ou sur F2. Vous pouvez aussi choisir Serveur > Se connecter, ou cliquer sur
   Connexion dans la barre d'outils.

Une fois la session ouverte, F2 vous déconnecte.

Si le serveur refuse votre nom d'utilisateur ou votre mot de passe, cliquez sur **Modifier les
identifiants** dans l'alerte pour les corriger et réessayer.

## Ajouter un serveur

1. Choisissez Serveur > Nouveau serveur, ou appuyez sur Commande + N.
2. Saisissez le nom que vous voulez voir dans votre liste, puis l'hôte et les ports TCP et UDP.
3. Sélectionnez **Connexion chiffrée** si le serveur l'exige.
4. Saisissez un pseudo, ou laissez le champ vide pour reprendre votre pseudo par défaut.
5. Saisissez votre nom d'utilisateur et votre mot de passe sur ce serveur, ou laissez-les vides pour
   vous connecter en invité.
6. Pour rejoindre un canal dès la connexion, saisissez son chemin dans **Canal à rejoindre**, et son
   mot de passe s'il en a un.
7. Cliquez sur Enregistrer.

Pour modifier un serveur, sélectionnez-le et appuyez sur Commande + E. Pour le retirer, appuyez sur
Supprimer, puis confirmez.

## Trier la liste des serveurs

Utilisez les menus locaux **Trier**, au-dessus de la liste, pour classer vos serveurs par **Ordre
enregistré**, **Nom**, **Hôte**, **Port TCP** ou **Port UDP**, en ordre **Croissant** ou
**Décroissant**. L'ordre enregistré conserve les serveurs dans l'ordre où vous les avez ajoutés.
Votre choix est mémorisé.

## Importer des serveurs

1. Choisissez Serveur > Importer les serveurs TeamTalk, ou appuyez sur Maj + Commande + I.
2. Choisissez la méthode d'import :
   - **Fichier de configuration** — le fichier de configuration du client TeamTalk officiel. Tous
     ses serveurs sont importés d'un coup.
   - **Fichier .tt** — un serveur unique, le format que partagent le plus souvent les propriétaires
     de serveurs.
   - **Coller un lien tt://** — collez un lien du type `tt://serveur.exemple.com?tcpport=10333`.
3. Si un serveur importé correspond à un serveur que vous avez déjà, cliquez sur **Remplacer** pour
   le mettre à jour. Quand plusieurs entrées se recoupent, cliquez sur **Continuer** pour toutes les
   importer.

tt-Accessible indique combien de serveurs ont été importés et combien ont été ignorés.

Vous pouvez aussi ouvrir un fichier `.tt` depuis le Finder, ou cliquer sur un lien `tt://`. Si une
session est déjà ouverte, tt-Accessible vous prévient que l'ouverture va la fermer. Un serveur
ouvert de cette façon n'est pas enregistré automatiquement : au moment de vous déconnecter,
tt-Accessible vous propose de le sauvegarder sous le nom de votre choix.

## Exporter des serveurs

- Pour exporter le serveur sélectionné, choisissez Serveur > Exporter le serveur, puis choisissez
  **Fichier .tt** ou **Copier le lien tt://**. Pendant une session, vous pouvez aussi sélectionner
  **Inclure un chemin direct** pour que la personne qui ouvre le fichier arrive dans le canal où
  vous êtes.
- Pour tous les exporter, choisissez Serveur > Exporter la liste de serveurs, puis choisissez **Un
  seul fichier** ou **Un fichier par serveur**.
- Pour copier un lien vers le serveur auquel vous êtes connecté, choisissez Serveur > Copier le lien
  du serveur, ou appuyez sur Maj + Commande + L.

## Se connecter avec un compte BearWare

Un compte BearWare gratuit (bearware.dk) vous permet de vous connecter aux serveurs qui acceptent la
connexion web, sans créer de compte sur chacun d'eux.

1. Ouvrez les Préférences, puis cliquez sur BearWare dans la barre latérale.
2. Saisissez votre **Identifiant BearWare** et votre **Mot de passe BearWare**, puis cliquez sur **Se
   connecter**.
3. Ouvrez les réglages de chaque serveur concerné, puis sélectionnez **Utiliser la connexion web
   BearWare**. Les champs d'identifiants locaux disparaissent : ce serveur passe désormais par votre
   compte BearWare.

Si un serveur est réglé sur la connexion web alors qu'aucun compte BearWare n'est configuré, la
connexion échoue et tt-Accessible vous renvoie aux Préférences.

**Voir aussi :** [Découvrir la fenêtre de tt-Accessible](main-window.html) ·
[Rejoindre et gérer des canaux](channels.html)
