## v1.13.0-beta.3 (build 59) — 02/10/2026

Cette bêta s'occupe des canaux où l'on parle chacun son tour, et de l'administration des serveurs. Dans ces canaux, vous ne pouviez parler qu'une fois : vous pouvez maintenant reprendre la parole à chaque tour, et l'app vous dit où vous en êtes dans la file d'attente.

### Parler chacun son tour
Sur certains serveurs, des canaux ne laissent entendre qu'une personne à la fois. Vous ouvrez votre micro, le serveur vous place dans une file d'attente et vous donne la parole quand votre tour arrive.

- **Vous pouvez parler plus d'une fois dans ces canaux.** Jusqu'ici, votre premier tour passait, puis tout ce que vous disiez ensuite se perdait, sans le moindre avertissement. C'était vrai dans tous les modes du micro, push-to-talk compris.
- **L'app vous prévient quand c'est votre tour.** Quand la parole vous revient, un son retentit et vous entendez « C'est à vous de parler ». À la fin de votre tour, un autre son, puis « Votre tour de parole est terminé ». Pendant l'attente, l'app vous donne votre place : « Vous êtes en position 3 dans la file d'attente ». L'app TeamTalk officielle joue les sons, mais ne vous dit pas votre place.
- Vous pouvez désactiver ces annonces dans Préférences > Annonces, avec « Tour de parole en file d'attente ».

### Créer et modifier un canal
- **La fenêtre du canal propose tout ce que propose l'app officielle.** En plus de ce qui existait déjà, vous pouvez désormais régler :
  - un canal « salle de classe », où seules les personnes autorisées peuvent parler ;
  - un canal où seuls les opérateurs entendent ce qui se dit ;
  - un canal masqué ;
  - un mot de passe opérateur, qui rend opérateur toute personne qui entre avec ;
  - le délai avant que la personne suivante de la file obtienne la parole ;
  - une durée maximale pour la voix et pour les médias.
- **Une chose que l'app ne sait pas encore faire** : donner ou retirer la parole dans une salle de classe. La case à cocher le précise, et vous pouvez gérer cette liste depuis un autre client.
- **Modifier un canal ne change plus son codec.** Un canal en Speex, ou sans codec du tout, passait en Opus dès que vous l'enregistriez. Changer le sujet d'un canal occupé échouait aussi, parce que le serveur refuse tout changement de codec tant qu'il y a du monde dedans.

### Administration du serveur
- **Modifier un compte n'efface plus ce que le formulaire n'affiche pas.** Enregistrer un compte effaçait ses autres réglages, dont les canaux où il devient opérateur automatiquement. Et si l'enregistrement échouait, le compte pouvait disparaître complètement, alors que l'app l'annonçait comme mis à jour.
- **Les erreurs s'affichent.** Quand le serveur refuse de créer, de modifier ou de supprimer un compte, vous savez maintenant pourquoi. « Compte mis à jour » et « Compte supprimé » ne sont plus annoncés que si l'opération a vraiment réussi.
- **Un compte qui ne s'est jamais connecté affiche « Jamais ».** Il affichait une date de 1970, que VoiceOver lisait comme une vraie date.

### Diffusion
- **Le son d'un périphérique ou d'une app que vous diffusez est encodé en meilleure qualité sur votre Mac avant de partir.** Cela ne consomme pas plus de bande passante. Merci à Rocco Fiorentino.

### À savoir
- Nous n'avons pas encore essayé un tour qui se termine pendant que vous diffusez depuis un périphérique. Si quelque chose sonne mal à ce moment-là, dites-le-nous.

### Téléchargement
[ttaccessible-1.13.0-beta.3-59.zip](https://github.com/math65/ttaccessible/releases/download/v1.13.0-beta.3/ttaccessible-1.13.0-beta.3-59.zip)
