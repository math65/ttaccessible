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
