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
