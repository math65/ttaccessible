---
title: Les serveurs
description: Ajouter, modifier, trier, importer et exporter des serveurs TeamTalk, et se connecter avec un compte BearWare.
keywords: serveur, serveurs enregistrés, import, export, fichier tt, lien tt, BearWare, connexion web
anchor: servers
---

La fenêtre **Serveurs TeamTalk** est le point de départ de chaque session. Elle affiche vos serveurs
enregistrés avec leur **Nom**, leur **Hôte**, leurs ports **TCP** et **UDP**, et la mention
**Sécurisé**.

La fenêtre rappelle elle-même l'essentiel : *Entrée ou F2 pour se connecter, Cmd-N pour ajouter,
Cmd-E pour modifier, Suppr pour supprimer.*

## Se connecter

Sélectionnez un serveur avec les flèches et appuyez sur **Entrée** ou sur **F2**. La même commande
figure dans **Serveur → Se connecter** et sur le bouton **Connexion** de la barre d'outils.

Une fois la session ouverte, **F2** devient **Se déconnecter**.

Si le serveur refuse vos identifiants, l'application propose **Modifier les identifiants…** : vous
corrigez le nom d'utilisateur ou le mot de passe sans avoir à ressaisir le reste.

## Ajouter un serveur à la main

**Commande-N**, ou **Serveur → Nouveau serveur**. Le formulaire demande :

| Champ | Ce qu'il contient |
|---|---|
| Nom | Le nom sous lequel le serveur apparaît dans votre liste |
| Hôte | L'adresse du serveur |
| Port TCP / Port UDP | Les ports du serveur |
| Connexion chiffrée | À activer si le serveur l'exige |
| Pseudo | Le nom que les autres voient. Laissez vide pour reprendre votre pseudo par défaut |
| Nom d'utilisateur / Mot de passe | Votre compte sur ce serveur. Laissez vide pour une connexion d'invité |
| Utiliser la connexion web BearWare | Se connecter avec votre compte BearWare à la place (voir plus bas) |
| Canal à rejoindre | Le chemin d'un canal à rejoindre automatiquement après la connexion |
| Mot de passe du canal | Le mot de passe de ce canal, s'il en a un |

Les mots de passe sont conservés dans votre trousseau de session, pas dans les fichiers de
l'application.

Pour revenir sur un serveur, sélectionnez-le et appuyez sur **Commande-E**. Pour le retirer, appuyez
sur **Suppr** ; une confirmation vous est demandée.

## Trier la liste

Les commandes **Trier**, au-dessus du tableau, classent la liste par **Ordre enregistré**, **Nom**,
**Hôte**, **Port TCP** ou **Port UDP**, en ordre **Croissant** ou **Décroissant**. L'ordre enregistré
conserve les serveurs dans l'ordre où vous les avez ajoutés. Votre choix est mémorisé.

## Importer des serveurs

**Serveur → Importer les serveurs TeamTalk…** (**Maj-Commande-I**) vous laisse choisir la source :

- **Fichier de configuration...** — le fichier de configuration du client TeamTalk officiel. Tous ses
  serveurs sont importés d'un coup. tt-Accessible sait reconnaître le format tout seul ; ce
  comportement dépend de l'option *Utiliser la détection automatique du fichier TeamTalk lors de
  l'import*, dans [Préférences → Général](preferences.html#prefs-general).
- **Fichier .tt...** — un serveur unique, le format que partagent le plus souvent les propriétaires
  de serveurs.
- **Coller un lien tt://...** — collez un lien du type `tt://serveur.exemple.com?tcpport=10333`.

Si un serveur importé correspond à un serveur que vous avez déjà, l'application demande s'il faut le
**Remplacer**. Quand plusieurs entrées se recoupent, elle demande une seule fois s'il faut
**Continuer**. Un bilan s'affiche à la fin : *n serveur(s) importé(s), n ignoré(s).*

Vous pouvez aussi ouvrir directement un fichier `.tt` depuis le Finder, ou cliquer sur un lien
`tt://`. Si une session est déjà ouverte, l'application prévient que l'ouverture va la fermer. Et
quand le fichier contient en plus des réglages du client — un pseudo, un genre —, elle énumère ce
qu'elle sait appliquer et vous laisse choisir entre **Appliquer** et **Ignorer**.

Un serveur ouvert de cette façon n'est pas enregistré automatiquement : au moment de vous
déconnecter, l'application vous propose de le **Sauvegarder** sous le nom de votre choix.

## Exporter des serveurs

- **Serveur → Exporter le serveur...** exporte le serveur sélectionné en **Fichier .tt...** ou copie
  un **lien tt://** dans le presse-papiers. Pendant une session, la même commande peut *Inclure un
  chemin direct vers* le canal où vous vous trouvez, pour que la personne qui ouvre le fichier
  arrive au bon endroit.
- **Serveur → Exporter la liste de serveurs…** exporte tout, soit dans **Un seul fichier**, soit à
  raison d'**Un fichier par serveur** dans le dossier de votre choix.

Pendant une session, **Serveur → Copier le lien du serveur** (**Maj-Commande-L**) place un lien vers
le serveur courant dans le presse-papiers.

## La connexion web BearWare

Un compte BearWare gratuit (bearware.dk) permet de se connecter aux serveurs qui acceptent la
connexion web, sans créer un compte sur chacun d'eux.

1. Ouvrez [Préférences → BearWare](preferences.html#prefs-bearware).
2. Saisissez votre **Identifiant BearWare** et votre **Mot de passe BearWare**, puis **Se
   connecter**. Le volet affiche ensuite *Connecté en tant que …* et propose **Se déconnecter**.
3. Dans chaque serveur concerné, activez **Utiliser la connexion web BearWare**. Les champs
   d'identifiants locaux disparaissent : ce serveur passe désormais par votre compte BearWare.

Si un serveur est réglé sur la connexion web alors qu'aucun compte BearWare n'est configuré, la
connexion échoue avec un message qui vous renvoie aux préférences.
