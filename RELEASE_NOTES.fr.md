## v1.11.1 (build 52) — 28/08/2026

Une seule correction, pour un plantage présent dans toutes les versions depuis la 1.10.0 : lorsque le serveur refusait ce que vous lui demandiez, l'application se fermait au lieu de vous en donner la raison.

### La correction
- **Une action refusée vous en donne maintenant la raison, au lieu de fermer l'application.** Chaque fois que le serveur opposait un refus — modification d'un canal, expulsion ou déplacement d'un utilisateur, envoi d'un message, transfert d'un fichier —, une alerte devait s'ouvrir pour vous expliquer ce qui s'était passé. L'application se fermait à la place, emportant votre connexion et tout ce que vous étiez en train de faire. L'alerte s'affiche désormais comme elle aurait toujours dû le faire, et vous énonce le motif du refus tel que le serveur l'a formulé.

Repéré grâce au rapport de plantage envoyé par **Ron J.**, qui avait remarqué que cela se produisait toujours sur un canal bien précis et a pris la peine de cerner le problème.

### Installation

tt-Accessible installe cette mise à jour pour vous automatiquement. Pour l'installer à la main :

1. Téléchargez `ttaccessible-1.11.1-52.zip` ci-dessous.
2. Décompressez-le et glissez `ttaccessible.app` dans votre dossier `/Applications`, en remplaçant la version précédente.
3. Double-cliquez — aucun avertissement Gatekeeper grâce à la notarisation.

### Téléchargement
[ttaccessible-1.11.1-52.zip](https://github.com/math65/ttaccessible/releases/download/v1.11.1/ttaccessible-1.11.1-52.zip)
