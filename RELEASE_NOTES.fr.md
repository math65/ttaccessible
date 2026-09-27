## v1.13.0-beta.1 (build 57) — 27/09/2026

Les curseurs de volume reviennent dans la fenêtre, vous pouvez diffuser plusieurs sources de votre Mac en même temps, et la fenêtre de connexion se parcourt plus simplement avec VoiceOver. L'essentiel de cette bêta est l'œuvre de Rocco Fiorentino.

### Volumes
- **Les curseurs de volume sont de retour dans la fenêtre**, juste au-dessus du mixeur : sortie, entrée, effets sonores et médias. Plusieurs d'entre vous les avaient redemandés. La bande Général du mixeur disparaît.
- **Tab s'arrête une seule fois sur chaque curseur**, et VoiceOver lit son nom. Chaque curseur propose l'action « Réinitialiser à 50 % ».

### Diffuser le son de votre Mac
- **Vous pouvez diffuser plusieurs sources à la fois.** Cochez les périphériques et les apps que vous voulez : un micro et votre lecteur de musique, deux interfaces audio, VoiceOver et une app. Le canal reçoit le tout en une seule diffusion.
- **Une nouvelle liste pour choisir vos sources**, avec un champ de recherche et trois groupes : Utilisées récemment, Périphériques et Applications. Vos cinq dernières sources se trouvent dans Utilisées récemment.
- **À la première ouverture, rien n'est coché.** Rien ne part tant que vous n'avez pas choisi.
- **Option + Commande + A lance et arrête la diffusion.** Pendant une diffusion, la même touche l'arrête, qu'il s'agisse du son de votre Mac, d'un fichier ou d'une adresse. Option + Commande + Point ne sert plus.
- **Les sources fortes ne saturent plus quand elles s'additionnent.** Les crêtes sont adoucies.
- **Une app ne se coupe plus une demi-seconde** quand elle joue un nouveau son, par exemple un aperçu Coup d'œil.

### VoiceOver
- **La fenêtre de connexion n'est plus un groupe dans lequel il faut entrer.** VoiceOver passe directement de la barre latérale aux curseurs, au mixeur, au chat et à l'historique, sans séparation au milieu.
- **Le bouton du micro dit enfin ce qu'il fait** : « Activer le micro » ou « Couper le micro ». Avant, il répétait l'état audio.
- **Maj + Commande + A répond tout de suite**, en même temps que son signal sonore, sans dire d'abord « Activer ou couper le micro ».
- **Un canal qui a un sujet n'est plus lu deux fois.**
- **Dans le mixeur, un double appui n'annonce que la nouvelle valeur**, sans lire l'ancienne avant.
- **Commande + 5 dans un canal vide vous dit que personne d'autre n'est là.**
- Les titres des feuilles sont désormais des titres de section pour VoiceOver.

### Périphériques audio
- **Débrancher le périphérique que vous avez choisi ne le fait plus oublier.** Il reste dans le menu avec la mention « non connecté », et l'app s'en sert de nouveau dès que vous le rebranchez. Vous pouvez toujours choisir Par défaut du système si vous le souhaitez.
- **Le son revient quand vous rebranchez un périphérique**, ou quand macOS redémarre son audio. Jusqu'ici, vous pouviez vous retrouver sans aucun son.
- **Les sons de notification suivent votre sortie audio** quand elle revient, et quand la sortie par défaut du système change.
- **Si votre micro était activé, il se réactive avec son périphérique**, avec le signal sonore habituel. À condition que vous soyez toujours sur le même serveur, que vous n'ayez ni activé ni coupé le micro entre-temps, et que vous n'ayez pas choisi un autre micro.
- **L'aperçu du micro dans les Préférences fonctionne même micro coupé.**

### Corrections
- **Modifier un ancien serveur enregistré pouvait échouer** avec le message « Invalid attempt to change the owner of this item ». La modification est maintenant enregistrée. Signalé par Vlad.
- **Enregistrer Maj + Commande + A comme raccourci dans les Préférences fonctionne.** Cette touche activait ou coupait votre micro au lieu d'être enregistrée.
- L'aide a été vérifiée page par page, en français comme en anglais.

### À savoir
- La réactivation du micro au rebranchement n'a pas encore été essayée avec un vrai périphérique.
- Les messages d'erreur du serveur restent en anglais, quelle que soit la langue de l'app.

### Installation

Si vous avez coché « Inclure les versions bêta » dans Préférences > Général, tt-Accessible vous proposera cette mise à jour. Pour l'installer à la main :

1. Téléchargez `ttaccessible-1.13.0-beta.1-57.zip` ci-dessous.
2. Décompressez-le et glissez `ttaccessible.app` dans votre dossier `/Applications`, à la place de l'ancienne version.
3. Ouvrez l'app. Elle est notarisée : macOS ne vous affichera pas d'avertissement.

### Téléchargement
[ttaccessible-1.13.0-beta.1-57.zip](https://github.com/math65/ttaccessible/releases/download/v1.13.0-beta.1/ttaccessible-1.13.0-beta.1-57.zip)

## v1.12.0 (build 56) — 4 septembre 2026

La fenêtre de connexion s'organise maintenant en deux volets, tous les volumes de l'application se règlent depuis le mixeur, et l'application parle turc. Si vous êtes resté sur le canal stable depuis la 1.11.1, cette version vous apporte aussi tout ce que les bêtas de l'été ont mis au point.

### L'essentiel
- **La fenêtre de connexion est en deux volets** au lieu d'une seule longue colonne — et VoiceOver la parcourt exactement dans le même ordre qu'avant.
- **Tous les volumes se règlent depuis le mixeur**, sur une tranche appelée Général, où Commande + 5 vous emmène directement.
- **L'application est traduite en turc**, et elle ne bascule plus en français chez ceux dont la langue n'est pas prise en charge.
- **Un micro qui cesse d'émettre se relance tout seul et vous prévient**, au lieu de vous laisser muet pendant des heures.
- **L'expulsion et le bannissement suivent les droits que le serveur vous a réellement donnés**, et non le seul statut d'administrateur.

### La fenêtre et le mixeur
- **Deux volets.** Le nom du serveur, ses lignes d'état, le bouton du micro et l'arborescence des canaux occupent une barre latérale ; le mixeur, le chat, la zone de saisie et l'historique occupent le reste. La séparation entre les deux se déplace à la souris et sa position est conservée d'une fois sur l'autre. L'ordre de lecture ne bouge pas : VoiceOver parcourt d'abord la barre latérale, puis le contenu, comme avant.
- **Le mixeur est de nouveau accessible.** VoiceOver passait droit devant sans s'y arrêter.
- **Tous les niveaux généraux tiennent sur la tranche Général** : sortie, médias, micro et effets sonores, dans cet ordre. Commande + 5 vous y dépose. Les flèches gauche et droite choisissent le niveau, les flèches haut et bas le règlent, V l'annonce, deux appuis sur V le remettent au repos, et M coupe ou rétablit tout. Les quatre curseurs qui traînaient dans la fenêtre ont disparu : ces niveaux n'existent plus qu'à un seul endroit.
- **Un seul réglage pour toutes les diffusions à la fois.** Quand quelqu'un diffuse de la musique pendant que les autres parlent, Commande + Majuscule + les flèches haut et bas baissent la musique seule, depuis n'importe où dans la fenêtre, sans toucher à la voix de personne. Une diffusion qui démarre ensuite est prise en compte automatiquement, et la vôtre baisse avec les autres.
- **Les touches règlent les niveaux comme vous vous y attendez.** Les flèches avancent de 1 %, Page précédente et Page suivante de 10 %, Début et Fin vont d'un coup à 100 % et à 0 %. Avec 2 % par appui, impossible de tomber juste, et il fallait cinquante appuis pour atteindre une extrémité. Ces touches agissent sur le niveau que règlent déjà les flèches : elles fonctionnent donc aussi bien sur la tranche d'une personne que sur la tranche Général.
- **Les fenêtres s'ouvrent à la taille prévue.** Plusieurs s'ouvraient minuscules.

### Votre micro
- **Un micro qui cesse d'émettre se relance tout seul, et vous le dit.** Il pouvait rester muet des heures sans que rien ne le signale.
- **Une reconnexion ne vous prend plus le micro** que vous aviez ouvert : vous le retrouvez comme vous l'aviez laissé.
- **Un canal qui ne transporte pas la voix vous le dit**, au lieu d'ouvrir un micro dans le vide.
- **Nouveau : vous pouvez arriver systématiquement avec le micro coupé.** C'est dans Préférences > Connexion, désactivé par défaut. Jusqu'ici l'application vous rendait toujours le micro tel que la session précédente l'avait laissé, ce qui, sur un serveur fréquenté, revient à émettre d'abord et s'en apercevoir ensuite. Un changement de canal n'y change rien, et un canal qui vous avait confisqué le micro vous le rend toujours.

### Les langues
- **Le turc.** Les 1 200 textes de l'application, annonces comprises, et pas seulement les menus. Choisissez-le dans Préférences > Général > Langue, ou laissez faire l'application si votre Mac est déjà en turc. Demandé par Serkan Türkyılmaz. Aucun turcophone ne l'a encore relu : les corrections sont les bienvenues.
- **L'application ne bascule plus en français.** Elle déclarait le français comme langue de repli : toute personne dont le Mac était réglé sur une langue non prise en charge — turc, allemand, espagnol — se retrouvait avec une application en français, et le réglage de langue ne pouvait rien pour les menus dessinés par macOS lui-même. C'est l'anglais désormais.
- **Les anglophones ne reçoivent plus d'unités françaises** dans les statistiques du serveur, la taille des fichiers, le pied des transferts et les lignes de chat.

### Les personnes et la modération
- **Affichez les personnes par pseudo, par nom d'utilisateur, ou par les deux.** Un nouveau menu, qui s'applique partout où quelqu'un est nommé : l'arborescence des canaux et son tri, le chat, les annonces, l'historique, le titre des conversations privées, la fenêtre des utilisateurs connectés et les tranches du mixeur. L'effet est immédiat, sans reconnexion, et si le nom choisi est vide, c'est l'autre qui s'affiche. Ce réglage se trouve maintenant dans Préférences > Connexion, à côté du tri des canaux.
- **L'expulsion et le bannissement suivent les droits du serveur.** Un modérateur qui a le droit sans avoir le statut d'administrateur peut enfin s'en servir.

### Corrections
- **Une action refusée vous en donne la raison au lieu de fermer l'application** — un plantage présent dans toutes les versions depuis la 1.10.0. Déjà publié seul en 1.11.1.
- **macOS 12 :** le menu de l'application conserve Quitter, Services, Masquer, Masquer les autres et Tout afficher, et le menu Édition est bien construit. Signalé et vérifié patiemment par Ron J.
- **La diffusion ne fonctionne plus avec cinq millisecondes de marge**, ce qui expliquait ses arrêts sans raison apparente.
- **Les adresses que vous avez déjà diffusées vous sont proposées.** Appuyez sur Retour pour en relancer une.
- Une espace tapée dans les préférences générales n'est plus effacée, et une personne sans pseudo est nommée au lieu d'apparaître comme une ligne vide.

### Installation

tt-Accessible installe cette mise à jour toute seule. Pour l'installer à la main :

1. Téléchargez `ttaccessible-1.12.0-56.zip` ci-dessous.
2. Décompressez et glissez `ttaccessible.app` dans votre dossier `/Applications`, en remplaçant la version précédente.
3. Double-cliquez — aucun avertissement Gatekeeper, l'application est notarisée.

### Téléchargement
[ttaccessible-1.12.0-56.zip](https://github.com/math65/ttaccessible/releases/download/v1.12.0/ttaccessible-1.12.0-56.zip)
