---
name: accessibility
description: Audit d'accessibilité de tt-Accessible — passe le code au crible des exigences VoiceOver du projet (annonces qui perdent leur priorité ou leur traduction, contrôles, tableaux et zones de défilement sans nom, libellés mal formés, clés absentes d'un catalogue, déplacements du curseur VoiceOver), sait dumper l'arbre d'accessibilité de l'app qui tourne, puis guide la revue manuelle des états qu'aucun script ne voit. À utiliser avant de livrer un écran, quand on demande « vérifie l'accessibilité », « est-ce que c'est bon en VoiceOver », « audit a11y », « passe d'accessibilité », après avoir écrit ou modifié un view controller AppKit ou une vue SwiftUI de préférences, et chaque fois qu'un défaut d'accessibilité est signalé à l'oreille — le réflexe doit être de lancer cette skill plutôt que de chercher à la main.
---

# Audit d'accessibilité de tt-Accessible

tt-Accessible existe parce que le client Qt de TeamTalk est inutilisable avec VoiceOver. Ici
l'accessibilité n'est pas une finition : **un écran qui compile mais laisse un contrôle sans
nom, ou une annonce que VoiceOver interrompt, est un écran qui ne marche pas.**

L'app est en **AppKit** (seules les préférences sont en SwiftUI) et se localise par
`L10n.text` / `L10n.format` sur deux `Localizable.strings`. Les règles sont écrites pour ça —
ne pas y chercher les patrons SwiftUI/xcstrings de DSM Access.

Cette skill fait deux choses, et la seconde compte autant que la première :

1. Un script trouve les défauts mécaniques, ceux qui se repèrent dans le texte du code.
2. Une revue guidée couvre ce qu'aucun script ne peut voir : le focus, l'ordre de lecture,
   les états transitoires, ce qui est réellement dit à voix haute.

## 1. Passer le script

Depuis la racine du dépôt :

```sh
python3 .agents/skills/accessibility/scripts/audit.py            # tout le projet
python3 .agents/skills/accessibility/scripts/audit.py --diff     # ce qui est en cours
python3 .agents/skills/accessibility/scripts/audit.py --files App/ttaccessible/AppKit/MoveUsersViewController.swift
python3 .agents/skills/accessibility/scripts/audit.py --only announces,priority
python3 .agents/skills/accessibility/scripts/audit.py --list-rules
```

Sur un travail en cours, `--diff` est le bon réflexe. Le script sort en code 1 s'il reste des
constats. Il ne modifie rien.

Un hook `PostToolUse` le lance déjà tout seul sur chaque fichier écrit dans
`App/ttaccessible/AppKit/`, `App/ttaccessible/SwiftUI/` ou `AppDelegate.swift`, et rend ses
constats dans le contexte. Le lancer à la main reste utile pour un écran entier ou un état des lieux.

### Ce que chaque règle cherche, et pourquoi

- **priority** — une annonce postée sans `.priority`, ou avec l'enum au lieu de son `rawValue`.
  `NSAccessibility.NotificationUserInfoKey.priority` attend un **NSNumber** : passer
  `NSAccessibilityPriorityLevel.high` le ponte en boîte opaque, AppKit ne relit pas le niveau,
  et l'annonce redevient interruptible. Ce bug est resté deux versions dans le Channel Mixer
  (1.7.0 → 1.10.0) sans que rien ne le signale. Toujours `.high.rawValue`.
- **announces** — une annonce avec un littéral. Ça compile, ça part en production, et c'est
  prononcé dans la langue où c'était tapé. Passer par `L10n.text` / `L10n.format`. Le script
  ignore les **clés** passées en paramètre nommé `announcement:` (patron de
  `PushToTalkKeyRecorder.reject`), qui sont correctes.
- **labels** — un `setAccessibilityLabel` / `Help` / `Title` (ou son équivalent SwiftUI) avec
  un littéral. Même raison. Les valeurs non traduisibles — gabarit d'horloge, pourcentage
  interpolé — sont écartées.
- **missing-keys** — une clé `L10n` absente d'`en.lproj` ou de `fr.lproj`. La clé s'affiche
  alors telle quelle à l'écran. Pour en ajouter une, la skill **add-localization** ; le
  français des chaînes livrées est au **vouvoiement**, jamais au tutoiement.
- **label-style** — un libellé qui prend un point final, commence en minuscule, ou nomme le
  type du contrôle. Le trait d'accessibilité dit déjà « bouton » ; le répéter fait entendre
  « Couper le micro bouton, bouton ».
- **hints** — une clé posée en `setAccessibilityHelp` / `.accessibilityHint` dont la valeur ne
  finit pas par un point. Le point final n'est pas de la cosmétique : c'est lui qui donne à
  VoiceOver son intonation de fin de phrase. Un hint s'écrit à la troisième personne et décrit
  le résultat (« Ouvre le salon. »), jamais l'action (« Ouvrir »).
- **tables** — un `NSTableView` ou un `NSOutlineView` sans `setAccessibilityLabel`. Un tableau
  anonyme s'annonce « tableau » et rien d'autre. La recherche est **par vue**, pas par fichier :
  un contrôleur qui nomme sa table principale peut en laisser une seconde muette, et c'est
  exactement ce qui était arrivé à la table des droits du formulaire de compte.
- **regions** — une zone de défilement sans nom **dont le contenu n'en porte pas non plus**.
  AppKit expose bien un `AXScrollArea` entre la fenêtre et son contenu, sans description
  (mesuré, voir §2) : quand rien à l'intérieur ne dit où l'on est, lui donner un
  `accessibilityLabel`, nommant ce qu'elle tient et non le titre de la fenêtre, qui serait lu
  deux fois.

  **Ne jamais masquer une zone de défilement.** `setAccessibilityElement(false)` ne la rend pas
  transparente : ses enfants remontent d'un cran, et parmi eux l'`AXScrollBar` avec ses cinq
  boutons. Essayé le 2026-08-02 sur les quatorze zones du projet — la fenêtre principale s'est
  retrouvée avec trois barres de défilement en vrac dans l'ordre de navigation et une traversée
  qui reboucle en fin de fenêtre. Mathieu l'a entendu en une minute, c'était annulé dans la
  foulée. Le piège est d'autant plus tentant que `PrivateMessagesViewController` le fait déjà
  sur deux zones : **c'est un défaut latent, pas un patron à suivre** — à écouter et
  probablement à retirer.

  Quand le contenu porte déjà son nom — un tableau, un `NSTextView` nommé — la règle ne dit
  rien : nommer ferait entendre le nom deux fois, masquer casse la hiérarchie, et ne rien faire
  marche. Le doublon « zone de défilement » puis « Liste des profils, tableau » est le prix à
  payer, et c'est le moins cher des trois.

  Le fond reste la consigne d'Apple — « Provide alternative labels for all key interface
  elements » (HIG VoiceOver) — mais l'exclusion qu'elle mentionne juste après vise les images
  décoratives, pas un conteneur qui tient une barre de défilement.
- **icon-buttons** — un bouton qui semble ne porter qu'un symbole, ou un
  `NSImage(systemSymbolName:… accessibilityDescription: nil)` dans une vue qui ne masque rien
  à VoiceOver. Le repérage est approximatif : confirmer en lisant le code.
- **heading-role** — le rôle de titre posé par sa constante typée. `AXHeading` se pose par
  `NSAccessibility.Role(rawValue: "AXHeading")` : la constante n'existe qu'à partir de
  macOS 26 et l'app cible macOS 12.
- **focus** — un `post(…, .focusedUIElementChanged)` ailleurs que dans le chemin du mixer.
  Déplacer le curseur VoiceOver arrache l'utilisateur à ce qu'il lisait ; le projet ne le fait
  qu'à un endroit, `focusChannelMixer` (⌘5), et c'est une décision assumée. Un nouveau
  déplacement se justifie ou se retire.
- **untranslated** — un ternaire qui affiche deux littéraux (`? "Oui" : "Non"`). Il compile et
  montre le mot français à un système anglais.

### Interpréter les constats sans les subir

Le script signale, il ne juge pas. À connaître :

- **Au 2026-08-02, le projet sort à zéro constat sur ses 145 fichiers.** C'est donc surtout un
  **détecteur de régression** : un constat neuf vient presque toujours du travail en cours.
- **`focus` et `icon-buttons` demandent une justification, pas forcément un changement.** Une
  icône peut légitimement ne pas être nommée si la vue qui la contient interdit à VoiceOver d'y
  descendre — c'est ce que fait `PreferencesWindowController` avec `accessibilityChildren() -> []`,
  sans quoi une ligne s'annonçait « Enregistrement, image de cercle, Enregistrement ».
- **`label-style` ne signale pas « liste » ni « tableau ».** Les cinq tableaux du projet
  s'appellent « Liste des utilisateurs bannis », « Liste des profils »… : ce sont des groupes
  nominaux naturels, pas un rôle répété. Les signaler noyait dix constats bons (mesuré).
- **Corriger l'écran en cours, signaler le reste.** Une passe massive non demandée contrevient
  à la règle du diff minimal.

## 2. Mesurer ce que VoiceOver voit vraiment

Entre « le code pose un label » et « VoiceOver annonce quelque chose » il y a l'arbre
d'accessibilité, et lui se mesure. `scripts/axdump.swift` l'imprime pour l'app qui tourne —
rôle, sous-rôle, description parlée, titre — sans rien installer :

```sh
swiftc -O .agents/skills/accessibility/scripts/axdump.swift -o /tmp/axdump
open ~/Library/Developer/Xcode/DerivedData/ttaccessible-*/Build/Products/Debug/ttaccessible.app
/tmp/axdump $(pgrep -x ttaccessible) 5
```

Le binaire a besoin de l'accès **Accessibilité** ; il sort en code 2 avec un message clair s'il
ne l'a pas. C'est ce dump qui a tranché le débat des zones de défilement, là où la lecture du
code et la documentation d'Apple laissaient les deux réponses ouvertes :

```
AXWindow  title="Serveurs TeamTalk"
  AXScrollArea « zone de défilement »            ← annoncée, aucun nom
    AXTable « tableau » desc="Serveurs TeamTalk enregistrés"
```

À utiliser dès qu'une question porte sur ce qui est **exposé** : un conteneur de trop, une
cellule qui s'effondre en un seul élément, un rôle qui ne correspond pas au contrôle. Fermer
l'app ensuite (`osascript -e 'tell application "ttaccessible" to quit'`).

## 3. Ce que le script ne verra jamais

C'est là que se trouvent les vrais défauts d'usage. Pour chaque écran modifié, parcourir
**tous ses états** — initial, connexion en cours, contenu, vide, erreur, opération en cours,
échec — et vérifier :

- **Les états muets.** Une erreur affichée sans être annoncée, une action réussie sans résultat
  dit, un changement d'état du micro qui ne s'entend pas : chacun est un écran incomplet.
  Les annonces passent par `announce(_:)` (`ConnectedServerViewController+Announcements`), qui
  **coalesce** ce qui arrive en 300 ms et joint le tout par « . » — deux annonces coup sur coup
  n'en font qu'une, et une annonce très fréquente noie les autres.
- **Les annonces perdues.** Une annonce émise alors que l'app est en arrière-plan n'est pas
  entendue de la même façon : ce chemin-là passe par la synthèse vocale ou une notification,
  selon `BackgroundMessageAnnouncementMode` et les réglages par type d'événement. Vérifier le
  comportement app au premier plan **et** app en arrière-plan, et se souvenir que chaque
  catégorie d'événement peut être désactivée par l'utilisateur.
- **La navigation au clavier.** Traversée complète à la tabulation, action par défaut et
  annulation présentes, aucun piège au clavier. Dans une sheet, `keyEquivalent = "\r"` ne
  suffit pas pour qu'Entrée valide quand une table a le focus : poser `window.defaultButtonCell`.
- **La cellule qui s'effondre.** Une cellule de tableau personnalisée peut se réduire à un seul
  élément et enterrer ses valeurs. Vérifier que chaque colonne s'entend, et que le rôle posé
  (`.staticText`, `.slider`, `.popUpButton`…) correspond à ce que le contrôle fait vraiment.
- **La couleur et l'icône seules.** Un statut porté par une couleur, une icône ou un état
  désactivé est invisible à l'écoute. Le mot est toujours écrit ; l'icône ne fait que le doubler.
- **Le mixer.** `ChannelMixerView` et son overlay virtuel (`MixerVirtualAccessibility`) exposent
  des éléments qui n'existent pas comme vues : toute modification s'y vérifie à l'oreille, pas
  à la lecture.

## 4. Les pièges déjà payés

Tous constatés en exécutant l'app, pas déduits de la doc. Les revérifier coûte moins cher que
de les redécouvrir :

- **En session modale (`NSAlert.runModal`), AppKit ne délivre jamais l'action d'un
  `NSMenuItem`.** Le menu s'ouvre, se navigue, la coche s'affiche — l'action ne part pas.
  Sortie : une sheet hébergeant un view controller, ou un `NSPopUpButton`. Un sous-menu ouvert
  depuis une sheet `NSAlert` n'est en plus pas navigable en VoiceOver : il est détruit dès
  qu'un `flagsChanged` est en vol, c'est-à-dire dès qu'un utilisateur VoiceOver touche ses
  modificateurs.
- **Le dispatch des key equivalents ne se reproduit pas en headless.** Un test qui ne déclenche
  pas le raccourci ne prouve rien ; ne pas en conclure « pas de bug ».
- **`setAccessibilityValue` ne change pas le rôle** d'un élément : un `NSButton` restera annoncé
  « bouton ». Si un contrôle natif fait déjà ce qu'on veut, le prendre plutôt que le simuler.

## 5. Écouter pour de vrai

Aucun script ne remplace une écoute. Construire en **Release** (le pipeline audio est ~75× plus
lent en Debug), lancer l'app, et manipuler l'écran modifié — piloter l'app soi-même est
bienvenu, Mathieu le demande explicitement. Borner le nombre de tentatives graphiques et rendre
la main dès que la boucle ne converge pas.

**Ne jamais écrire qu'un écran est accessible sans l'avoir fait vérifier à l'oreille.** La
compilation et le script prouvent l'absence de certains défauts, jamais la présence de l'usage.

## 6. Rendre compte

L'audit se termine par une conversation, pas par un fichier. Présenter :

- ce qui a été corrigé dans l'écran en cours ;
- ce que le script signale ailleurs, en distinguant le passif du projet de ce que le travail en
  cours aurait introduit ;
- ce qui reste à écouter, formulé comme une liste de choses à essayer — Mathieu est utilisateur
  avancé de VoiceOver, il entend en trente secondes ce qu'aucun script ne mesure. Lui indiquer
  quoi ouvrir et quoi guetter vaut mieux que lui affirmer que tout va bien.
