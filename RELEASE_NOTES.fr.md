## v1.13.0-beta.2 (build 58) — 29/09/2026

Une petite bêta consacrée à la connexion aux serveurs. L'app envoie beaucoup moins de commandes quand vous vous connectez, et elle garde une trace de ce qui se passe quand un serveur ne répond plus.

### Connexion
- **La connexion envoie beaucoup moins de commandes au serveur.** L'app en envoyait deux pour chaque personne présente, quels que soient vos réglages : 34 sur un serveur de 17 personnes. Elle n'envoie plus que ce qui diffère des réglages du serveur, c'est-à-dire le plus souvent rien du tout, comme l'app TeamTalk officielle.
- **Changer un abonnement par défaut dans les préférences ne change plus que celui-là.** Si vous désactivez par exemple les messages privés par défaut, les personnes déjà présentes perdent les messages privés, et rien d'autre. Ce que vous avez réglé à la main pour quelqu'un reste tel quel.
- **La vidéo des webcams n'est plus coupée pour tout le monde à la connexion.** L'app la laisse telle que le serveur la règle, comme le fait l'app officielle. Elle n'affiche toujours pas les webcams.

### Quand un serveur ne répond plus
Certains d'entre vous arrivent à se connecter à un serveur, mais jamais à rejoindre un canal : au bout de quelques secondes s'affiche « Le serveur n'a pas répondu dans le délai attendu », puis la connexion tombe une minute plus tard. Nous n'en connaissons pas encore la cause. Cette bêta note dans le journal audio ce que fait la connexion, pour qu'on voie de quel côté la communication s'arrête.

Si cela vous arrive, **ne quittez pas l'app**. Allez dans Aide > Contacter le développeur, choisissez « Signaler un problème » et cochez « Joindre le journal de diagnostic audio ». Le journal est effacé à chaque lancement de l'app : il faut donc l'envoyer depuis la session où le problème s'est produit.

### À savoir
- Rien ne confirme encore que cette bêta règle le problème ci-dessus. C'est le journal qui nous le dira.

### Téléchargement
[ttaccessible-1.13.0-beta.2-58.zip](https://github.com/math65/ttaccessible/releases/download/v1.13.0-beta.2/ttaccessible-1.13.0-beta.2-58.zip)
