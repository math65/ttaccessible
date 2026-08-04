## v1.11.0 (build 46) — 04/08/2026

Cette version dote enfin l'application d'un vrai guide d'utilisation, accessible depuis le menu Aide. Elle revoit aussi de fond en comble les raccourcis utilisables depuis une autre application : ils ne réclament plus d'autorisation système, et la touche que vous appuyez ne vient plus s'écrire dans l'application où vous travaillez. Enfin, un volume réglé sur 0 % coupe désormais réellement le son.

### L'essentiel
- **Un guide d'utilisation complet, dans le menu Aide (⌘?)** — 18 rubriques, en français et en anglais.
- **Un raccourci micro utilisé depuis une autre application ne demande plus l'autorisation « Surveillance de la saisie ».**
- **La touche est réellement captée** : elle ne s'écrit plus dans l'application que vous utilisez.
- **0 % sur un curseur de volume, c'est le silence.** C'était jusqu'ici un niveau discret, mais parfaitement audible.

### Le guide d'utilisation
- **⌘? ouvre un guide complet dans l'aide de macOS.** Vous y trouverez le premier lancement, l'ajout d'un serveur, la circulation dans la fenêtre principale, les canaux, la prise de parole, les messages, le mixeur de canal, le réglage de votre matériel audio, l'enregistrement, la diffusion, les utilisateurs et l'administration, chaque panneau des préférences, les sons et les annonces, les profils, la liste complète des raccourcis, et la marche à suivre quand quelque chose ne fonctionne pas.
- **Écrit pour être suivi, pas seulement lu.** Chaque rubrique annonce ce que vous allez pouvoir faire, puis déroule des étapes numérotées qui nomment le menu, le bouton et le menu local exacts.
- **Disponible en français et en anglais.** L'aide de macOS choisit sa langue d'après celle de votre Mac et non celle de l'application : chaque page d'accueil renvoie donc vers l'autre langue si vous tombez sur la mauvaise.

### Les raccourcis micro depuis une autre application
- **Plus d'autorisation « Surveillance de la saisie »** pour un raccourci ordinaire, c'est-à-dire une touche accompagnée de Commande, Contrôle ou Option. Seul un raccourci composé uniquement de touches de modification, que l'on presse et relâche telles quelles, la réclame encore.
- **La touche ne parvient plus à l'application au premier plan.** Auparavant, votre raccourci coupait bien le micro, mais son caractère s'écrivait aussi dans ce que vous étiez en train d'utiliser. À savoir : l'application qui se servait du même raccourci de son côté cesse de le recevoir tant que le vôtre est défini — Reaper, par exemple, perd son Contrôle-Espace aussi longtemps que vous le gardez.
- **Un raccourci qui écrirait quelque chose est maintenant refusé au moment où vous l'enregistrez**, et les solutions vous sont annoncées : F13 à F20, ou l'ajout de Commande, Contrôle ou Option. Un raccourci de ce type enregistré avant cette version est refusé lui aussi, avec l'explication dans les préférences, plutôt que d'avaler cette lettre partout où vous écrivez.
- **Le menu Utilisateur affiche enfin le raccourci que vous avez choisi**, au lieu de toujours annoncer ⌘⇧A.
- **Les touches F13 à F20 portent leur nom.** Elles s'affichaient sous la forme « Key 105 » et ne pouvaient pas apparaître dans le menu, alors que ce sont précisément celles qu'il vaut mieux choisir.

### Corrections
- **Un raccourci micro réattribué fonctionne aussi quand tt-Accessible est au premier plan.** Une fois modifié dans les préférences, il fonctionnait partout sauf dans l'application elle-même.
- **Sur les claviers AZERTY, le raccourci affiché correspond à la touche pressée.** Un raccourci ⌘⇧ sur la touche « 1 » s'affichait ⌘⇧& dans le menu et ⌘⇧1 dans les préférences : deux libellés pour un seul raccourci, que VoiceOver énonçait comme deux choses différentes.
- **Votre raccourci n'est plus enregistré deux fois au lancement.** Signalé par Rocco Fiorentino.
- **VoiceOver nomme deux endroits où l'on entrait à l'aveugle** : le tableau des droits, lors de la modification d'un compte, qui s'annonçait « tableau » et rien d'autre, ainsi que les zones de défilement des fenêtres de propriétés du serveur et d'informations sur un utilisateur.
- **Un raccourci micro reste sans effet tant qu'un champ de mot de passe est actif quelque part sur votre Mac.** C'est macOS qui protège votre saisie, et non un défaut : c'est désormais écrit dans la page de dépannage.

### Téléchargement
[ttaccessible-1.11.0-46.zip](https://github.com/math65/ttaccessible/releases/download/v1.11.0/ttaccessible-1.11.0-46.zip)

## v1.10.0 (build 45) — 26/07/2026

Cette version vous permet de diffuser dans un canal le son d'une application — ou celui de VoiceOver — en gardant votre voix calée dessus. La reconnexion automatique vous ramène désormais vraiment dans le canal que vous occupiez, les mots de passe de canaux sont mémorisés, et les modérateurs peuvent vider un canal en une seule opération.

### L'essentiel
- **Diffusez le son de n'importe quelle application** dans votre canal — ou celui de VoiceOver — et plus seulement celui d'un périphérique d'entrée. Raccourci : **⌥⌘A**.
- **Votre voix reste calée sur ce que vous diffusez** : vos auditeurs entendent les deux ensemble.
- **La reconnexion automatique vous ramène pour de bon**, dans le même canal, et autant de fois que la connexion tombe.
- **Les mots de passe de canaux sont retenus** : un canal protégé cesse de vous les redemander.

### Diffuser une application ou VoiceOver
- **⌥⌘A propose maintenant trois types de sources** : un périphérique d'entrée, VoiceOver, ou une application en cours d'exécution. Les applications sont regroupées dans leur propre sous-menu.
- **Vous pouvez désigner une application qui n'est pas encore lancée.** La capture s'y accroche d'elle-même dès qu'elle produit du son, et lui survit si vous la quittez puis la relancez en pleine diffusion.
- **Vous pouvez couper le son de la source sur votre Mac pendant que vous la diffusez**, pour que seul le canal l'entende. Désactivé par défaut, et jamais retenu d'une diffusion à l'autre.
- **Votre voix est retardée pour coller au flux.** Une diffusion accuse près d'une seconde de latence : sans cela, vous arriveriez en avance sur votre propre musique ou votre instrument. Le décalage est mesuré en direct et suit la dérive pendant que vous parlez.
- Les applications et VoiceOver demandent macOS 14.2 ou plus récent. De macOS 13 à 14.1, seules les applications déjà lancées peuvent être captées ; sur macOS 12, seuls les périphériques d'entrée sont proposés.

### Reconnexion
- **Une coupure de connexion vous reconnecte réellement, et vous remet dans le canal que vous occupiez** — retrouvé par son chemin, ce qui fonctionne même quand le serveur redémarre et renumérote ses canaux.
- **Et cela fonctionne à chaque fois, plus seulement une fois par session.** Une deuxième coupure vous laissait auparavant déconnecté.
- **Une expulsion ou un bannissement ne vous reconnecte plus quelques secondes plus tard.**
- Les tentatives s'espacent — 5 secondes, puis 10, 30 et 60 — et s'arrêtent au bout de cinq minutes environ, plutôt que de marteler un serveur qui ne répond plus.

### Mots de passe de canaux
- **Un canal protégé que vous avez rejoint une fois ne vous redemande plus rien.** Le mot de passe est conservé dans votre trousseau, par canal et par serveur.
- **Cela vaut aussi au lancement** : « rejoindre le dernier canal » ne vous dépose plus à la racine du serveur faute de mot de passe.
- **« Oublier le mot de passe enregistré »** dans le menu contextuel d'un canal, affiché uniquement lorsqu'il y a effectivement quelque chose à oublier.
- **Si le mot de passe change côté serveur, celui qui était enregistré est écarté** au lieu d'être resoumis puis proposé à nouveau dans la zone de saisie.
- Faire pointer un serveur enregistré vers un autre hôte ou un autre port efface ses mots de passe de canaux : ils ne partiront jamais vers un serveur différent.

### Modération
- **Déplacez tous les occupants d'un canal en une fois**, depuis le menu contextuel du canal — avec une liste à cocher pour en laisser certains sur place, et une action VoiceOver disponible sur la ligne du canal.
- Le résultat est annoncé et signalé une seule fois (« 5 utilisateurs sur 6 déplacés vers… »), au lieu d'une boîte de dialogue par personne.
- **Les canaux de destination sont désignés par leur chemin complet** : deux canaux portant le même nom sous des parents différents ne se confondent plus. Le déplacement d'un utilisateur seul en profite également.

### Corrections
- **Les annonces du mixeur de canal ne sont plus coupées.** Les changements de volume, de panoramique et de coupure du son étaient annoncés avec une priorité incorrecte depuis la version 1.7.0, si bien que VoiceOver pouvait parler par-dessus.
- Les annonces du mixeur et la fenêtre de déplacement s'expriment correctement lorsqu'un canal ne compte qu'une seule personne.

### Remerciements
La quasi-totalité de cette version a été conçue et réalisée par **Rocco Fiorentino** : diffusion des applications et de VoiceOver, synchronisation de la voix, fiabilisation de la reconnexion, mots de passe de canaux et déplacements groupés. Merci à lui, comme toujours, ainsi qu'à toutes celles et ceux qui continuent d'envoyer leurs retours.

### Téléchargement
[ttaccessible-1.10.0-45.zip](https://github.com/math65/ttaccessible/releases/download/v1.10.0/ttaccessible-1.10.0-45.zip)

## v1.9.0 (build 44) — 24 juillet 2026

Cette version remet complètement à plat le push-to-talk : n'importe quelle touche peut servir à parler, elle fonctionne même quand vous êtes occupé dans une autre application, et un nouveau mode permet de combiner la coupure du micro avec le push-to-talk. Vous pouvez aussi choisir la langue de l'application, sans dépendre de celle de votre Mac.

### En bref
- **Le push-to-talk a été refait.** N'importe quelle touche convient : une touche seule, ou une combinaison de touches de modification.
- **Votre touche pour parler et le raccourci de coupure du micro fonctionnent depuis n'importe quelle application**, et plus seulement quand tt-Accessible est au premier plan.
- **Choisissez la langue de l'application** — français ou anglais — sans suivre celle de votre Mac.

### Push-to-talk
- **N'importe quelle touche peut servir à parler** : une touche seule, ou une combinaison de touches de modification comme Commande-Contrôle (appuyez dessus, puis relâchez). Tout tient en un bouton : activez-le, puis appuyez sur la touche voulue.
- **Le champ de saisie de la touche est enfin accessible.** C'est un vrai bouton, annoncé par VoiceOver, et l'enregistrement d'une touche ne se laisse plus perturber par les touches Contrôle-Option de VoiceOver lui-même.
- **Nouveau mode de microphone : « Les deux ».** ⌘⇧A coupe et réactive le micro, comme avant. En plus de ça, maintenir votre touche de push-to-talk vous permet de parler même micro coupé, et la relâcher vous remet en silence. À choisir dans Préférences › Audio.
- **Un son facultatif au début et à la fin de la transmission**, pour entendre que votre touche a bien été prise en compte.
- **Les raccourcis peuvent fonctionner pendant que vous êtes dans une autre application.** À activer séparément pour le push-to-talk et pour ⌘⇧A. macOS demande l'autorisation « Surveillance des saisies » la première fois.
- Bon à savoir : la touche continue d'arriver jusqu'à l'application où vous travaillez — tt-Accessible la voit passer, mais ne peut pas la garder pour lui. Préférez donc une combinaison de touches de modification seules, comme Commande-Contrôle, ou une touche de fonction entre F13 et F19 : ni l'une ni l'autre n'écrit quoi que ce soit. Évitez les lettres seules.
- **⌘⇧A ne se déclenche plus lorsque le Finder est au premier plan.**
- La touche de push-to-talk que vous utilisiez déjà est reprise automatiquement.

### Langue
- **Préférences › Général propose désormais un réglage Langue** : langue du système, anglais ou français. Redémarrez l'application pour l'appliquer partout.
- **Au tout premier lancement, l'application vous demande la langue que vous souhaitez.**

### Remerciements
Le push-to-talk a été conçu et développé par **Rocco Fiorentino**. Le réglage de langue nous vient de **Gruia Chiscop**. Merci à eux deux — et à toutes les personnes qui continuent d'envoyer leurs retours.

### Téléchargement
[ttaccessible-1.9.0-44.zip](https://github.com/math65/ttaccessible/releases/download/v1.9.0/ttaccessible-1.9.0-44.zip)

## v1.8.0 (build 43) — 22 juillet 2026

Cette version permet de diffuser un périphérique audio en direct dans un canal, rétablit la prise en charge de macOS 12 (Monterey) et corrige le son qui disparaissait dans les canaux « enregistrement interdit » — avec, en prime, des améliorations de la table de mixage et de l'enregistrement.

### En bref
- **Diffusez un périphérique audio en direct dans votre canal.** Choisissez n'importe quelle entrée — une interface audio, un périphérique virtuel, du loopback — et diffusez-la dans le canal comme un flux média, en parallèle de votre voix. Avec **⌘⌥A**.
- **macOS 12 Monterey est de nouveau pris en charge.** L'application fonctionne à partir de macOS 12.
- **Le son ne disparaît plus dans les canaux « enregistrement interdit ».**

### Diffusion d'un périphérique en direct
- **⌘⌥A** diffuse le périphérique d'entrée choisi dans le canal courant, sous forme de flux média, en parallèle de votre voix.
- Le démarrage est rapide et ne fige plus le canal, avec une faible latence — le flux utilise Opus avec de très petites trames, ce qui rend l'analyse côté serveur quasi instantanée.
- Si le périphérique devient silencieux, du silence est injecté automatiquement pour que le flux ne se coupe jamais.

### Audio
- **Les canaux « enregistrement interdit » rediffusent le son.** Dans un canal marqué « enregistrement interdit », vous n'entendiez plus les autres — alors que tout fonctionnait pour les personnes sur les clients Qt ou iPhone. C'est corrigé : vous entendez de nouveau tout le monde. L'enregistrement, lui, reste bloqué dans ces canaux, exactement comme le serveur le prévoit.

### Table de mixage
- **Position stéréo indépendante pour la voix et les médias de chaque personne.** Vous pouvez placer séparément, dans l'espace stéréo, la voix d'une personne et son flux média.

### Enregistrement
- **⌘R enregistre un fichier unique ; ⌘⇧R enregistre un fichier par personne (ou les deux).** Les deux raccourcis choisissent désormais directement le format d'enregistrement.
- À noter si vous utilisiez déjà l'enregistrement : si vous étiez en « fichier unique », le bouton de la barre d'outils enregistre maintenant **à la fois** un fichier unique et un fichier par personne. Utilisez **⌘R** pour n'obtenir qu'un seul fichier.

### Administration
- **Quota disque par canal**, modifiable avec un sélecteur d'unité (Ko / Mo / Go).
- **Propriétés complètes du serveur** — ports TCP/UDP et informations de version — dans la fenêtre des propriétés du serveur.
- **Colonne du pseudo en ligne** dans la liste des comptes utilisateurs.

### Accessibilité et finitions
- VoiceOver plus clair dans la table de mixage : annonces de zone vocalisées et libellés d'état de coupure dans la barre d'outils.
- **Échap ferme les fenêtres auxiliaires.**
- Correctifs plus discrets : plus de son d'interception injustifié pendant la synchronisation de connexion, conversion d'unité du quota disque en direct, et les envois de fichiers ne sont plus refusés à tort par une vérification de quota côté client.

### Téléchargement
[ttaccessible-1.8.0-43.zip](https://github.com/math65/ttaccessible/releases/download/v1.8.0/ttaccessible-1.8.0-43.zip)

## v1.7.0 (build 42) — 8 juillet 2026

Voici la version stable qui met entre toutes les mains ce qui a été mis au point tout au long des bêtas 1.7.0. Si vous veniez de la 1.6.0, voici ce qui a changé.

### En bref
- **Une toute nouvelle table de mixage par personne.** Pour chaque personne présente dans votre canal, vous réglez son volume de voix, son volume des médias, sa position gauche/droite, sa coupure et son solo — le tout au clavier et avec VoiceOver.
- **Connexion avec un compte BearWare.** Un identifiant gratuit bearware.dk suffit désormais pour vous connecter aux serveurs compatibles, sans créer un compte différent sur chacun.
- **Un moteur audio reconstruit, plus rapide et plus stable.** La connexion est de nouveau quasi instantanée, changer de casque ou d'enceintes ne fige plus le son, et les canaux chargés restent fluides.

### La table de mixage
- Chaque personne du canal a sa propre tranche : **volume de la voix, volume des médias, position stéréo, coupure et solo**.
- Tout se pilote au clavier lorsque vous êtes positionné sur une personne : Haut/Bas pour le volume de la voix, Commande+Haut/Bas pour son volume des médias, Gauche/Droite pour la déplacer dans l'espace stéréo, et V, P, M, S pour entendre ou réinitialiser le volume, la position, la coupure et le solo.
- **Nouveau : appuyez sur Commande+5 pour aller directement à la table de mixage** — elle rejoint les raccourcis de zones Commande+1 à Commande+4 en tant que cinquième zone. (Merci à Matthew Whitaker pour l'idée.)
- Les réglages de chaque personne sont mémorisés et reviennent la prochaine fois qu'elle se connecte.

### Audio
- **Changer de périphérique de sortie ne fige plus le son.** Basculez de casque ou d'enceintes en cours de connexion, le son suit tout simplement.
- **La connexion est de nouveau rapide.** Sur les Mac équipés de beaucoup de matériel audio, l'ouverture d'une connexion pouvait s'immobiliser une dizaine de secondes le temps d'inspecter chaque appareil — cette analyse a disparu, et le correctif est maintenant intégré à chaque version.
- **Les canaux chargés et en haute qualité restent fluides.** Les canaux qui utilisent de gros paquets audio pouvaient hacher pour tout le monde ; la lecture a été revue pour tenir la charge.
- **Votre micro et votre sortie choisis sont retenus de façon fiable**, même après un débranchement, un rebranchement ou un redémarrage, au lieu de retomber discrètement sur le mauvais appareil.
- **Réduction de bruit indépendante.** Un nouveau réglage Traitement du microphone (Préférences › Audio) vous laisse choisir entre Aucun, Réduction de bruit, ou Annulation d'écho avec réduction de bruit — et le changement s'applique en direct, même pendant que vous parlez.
- **Vous entendez désormais vos propres médias diffusés** lorsque vous jouez un fichier audio ou vidéo dans un canal.
- **Les volumes par personne sont maintenant conservés par serveur** : un volume réglé sur un serveur ne déborde plus sur un autre. Un nouveau réglage vous laisse décider s'ils sont retenus en permanence, seulement le temps de la session, ou pas du tout.

### Accessibilité
- L'application s'appelle désormais **tt-Accessible**, pour que VoiceOver et les synthèses vocales la prononcent correctement.
- **Appuyez sur VoiceOver+Espace pour rejoindre** le serveur ou le canal sélectionné.
- **Les curseurs et le bouton du microphone annoncent maintenant leur valeur** au fur et à mesure que vous les modifiez — gain, volume de sortie et les différents curseurs des Préférences.
- Les Préférences se lisent plus proprement avec VoiceOver : plus d'étiquettes en double, chaque section est un vrai titre, les zones de défilement sont nommées, et Échap ferme la fenêtre.

### Corrections
- **La connexion web BearWare aboutit de façon fiable**, y compris sur les serveurs qui répondent de manière un peu inhabituelle.
- **Un pseudo laissé vide** revient maintenant à votre pseudo par défaut au lieu d'empêcher la connexion.
- L'application **démarre plus vite**.

### Remerciements
Un grand merci à **Rocco Fiorentino**, qui a conçu et réalisé la refonte audio et la table de mixage, les améliorations d'accessibilité et VoiceOver, ainsi que la connexion plus rapide et plus stable de cette version. Merci à **Matthew Whitaker** pour la suggestion du Commande+5 — et à toutes les personnes qui ont testé les bêtas et fait remonter leurs retours.

### Installation

tt-Accessible installe cette mise à jour pour vous automatiquement. Pour l'installer à la main :

1. Téléchargez `ttaccessible-1.7.0-42.zip` ci-dessous.
2. Décompressez-le et glissez `ttaccessible.app` dans votre dossier `/Applications`, en remplaçant la version précédente.
3. Double-cliquez — aucun avertissement Gatekeeper grâce à la notarisation.

### Téléchargement
[ttaccessible-1.7.0-42.zip](https://github.com/math65/ttaccessible/releases/download/v1.7.0/ttaccessible-1.7.0-42.zip)
