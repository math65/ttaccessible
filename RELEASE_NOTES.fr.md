## v1.12.0-beta.6 (build 53) — 28/08/2026

Deux corrections, toutes deux issues de retours de testeurs. La première concerne un plantage présent dans chaque version depuis la 1.10.0 ; il paraît aussi aujourd'hui sous le nom de v1.11.1, pour les personnes restées sur le canal stable.

### Corrections
- **Une action refusée vous en donne maintenant la raison, au lieu de fermer l'application.** Chaque fois que le serveur opposait un refus — modification d'un canal, expulsion ou déplacement d'un utilisateur, envoi d'un message, transfert d'un fichier —, une alerte devait s'ouvrir pour vous expliquer ce qui s'était passé. L'application se fermait à la place, emportant votre connexion et tout ce que vous étiez en train de faire. Repéré grâce au rapport de plantage de **Ron J.**, qui avait remarqué que cela se produisait toujours sur un canal bien précis et a pris la peine de cerner le problème.
- **Le menu de l'application retrouve réellement Services, Masquer, Masquer les autres et Tout afficher sous macOS 12.** La bêta 5 l'annonçait à tort : les éléments étaient bien insérés, puis SwiftUI reconstruisait le menu et les emportait aussitôt. Ils sont désormais déclarés là où le menu se construit, le remède qui avait déjà fait tenir Quitter en bêta 3. Signalé, puis démenti, par **Ron J.**

### À savoir
Les messages d'erreur venant du serveur s'affichent toujours en anglais, quelle que soit la langue dans laquelle vous utilisez l'application : « Command not authorized » et ses 44 semblables proviennent de la bibliothèque TeamTalk, non traduits. Maintenant que ces alertes s'affichent enfin, leur traduction est la prochaine étape.

### Installation

tt-Accessible installe cette mise à jour pour vous automatiquement. Pour l'installer à la main :

1. Téléchargez `ttaccessible-1.12.0-beta.6-53.zip` ci-dessous.
2. Décompressez-le et glissez `ttaccessible.app` dans votre dossier `/Applications`, en remplaçant la version précédente.
3. Double-cliquez — aucun avertissement Gatekeeper grâce à la notarisation.

### Téléchargement
[ttaccessible-1.12.0-beta.6-53.zip](https://github.com/math65/ttaccessible/releases/download/v1.12.0-beta.6/ttaccessible-1.12.0-beta.6-53.zip)
