# Refonte du système de peinture : géométrie → texture

**Projet :** `EliyanJ/rork-recr-er-splatoon-3d` — dossier `ios-ink-arena-3d`
**Objectif :** supprimer définitivement les saccades pendant le tir en remplaçant la peinture générée en géométrie par une peinture écrite dans une texture.
**Cible :** iOS 18+, RealityKit, iPhone 12 minimum.

---

## 1. Pourquoi ce changement

### Le problème actuel

Aujourd'hui, `PaintGrid.rebuildChunk(_:team:)` reconstruit un maillage 3D à chaque fois que de la peinture apparaît :

- chaque tuile peinte = ~13 sommets et 12 triangles ajoutés à un maillage fusionné ;
- chaque reconstruction appelle `MeshResource.generate(from:)`, qui est **synchrone** et alloue des tampons GPU ;
- cet appel se produit **sur le thread principal**, jusqu'à 10 fois par flush, 30 flushes par seconde.

Conséquence : le thread qui affiche les images est bloqué pendant qu'il fabrique de la géométrie. D'où les saccades pendant le tir.

### Le défaut de fond

Le coût de ce système **augmente avec la couverture de la carte**. Plus le match avance, plus les chunks contiennent de tuiles, plus chaque reconstruction est lourde. Une partie commence fluide et finit en diaporama. Aucun réglage de qualité ne corrige ça — c'est structurel.

### Le principe de la solution

La peinture n'est pas un objet 3D. C'est une **image plaquée sur le sol**.

On garde une image vue de dessus de toute l'arène. Peindre = écrire des pixels dans cette image. Le coût est constant : écrire une tache coûte la même chose au début et à la fin du match, que la carte soit couverte à 2 % ou à 98 %.

Aucune géométrie n'est jamais recréée. Le sol reste un objet unique, immuable, dessiné en un seul appel.

**C'est l'approche du vrai Splatoon.**

### Ordre de grandeur

| | Système actuel | Système texture |
|---|---|---|
| Coût d'un tir | reconstruction d'un maillage (milliers de sommets) | écriture de ~1 000 pixels |
| Évolution en cours de partie | dégradation continue | constant |
| Objets 3D pour la peinture | jusqu'à ~110 maillages fusionnés | 1 plan + 1 quad par surface surélevée |
| Thread principal | bloqué à chaque reconstruction | quasi rien |

Gain attendu : deux à trois ordres de grandeur sur le coût CPU de la peinture.

---

## 2. Ce qui NE change pas

C'est le point le plus important pour ne rien casser.

**Toute la logique de jeu reste identique.** La grille d'appartenance (`owners`), les compteurs de couverture (`orangeCount`, `purpleCount`), les tuiles bloquées (`blockedTiles`), la fonction `paint(atX:z:radius:team:)`, la fonction `team(atX:z:)` utilisée par les bots et les déplacements, la synchronisation réseau — **on n'y touche pas**.

On sépare proprement deux choses qui étaient mélangées :

- **la grille logique** = qui possède quelle case → gameplay, couverture, IA, réseau. *Inchangée.*
- **la texture** = à quoi ça ressemble → purement visuel. *C'est ça qu'on remplace.*

Les onze sites d'appel de `paint(atX:...)` dans le projet (projectiles, grenades, kills, bases de départ, réseau) continuent de fonctionner sans modification.

---

## 3. Architecture cible

### 3.1 Le tampon de peinture

Une zone mémoire CPU en `RGBA8` (4 octets par pixel) couvrant l'arène vue de dessus.

**Résolution :** 8 pixels par mètre de jeu.

```
largeurTexture = min(1024, prochainePuissanceDe2(GameConfig.arenaWidth * 8))
hauteurTexture = min(1024, prochainePuissanceDe2(GameConfig.arenaDepth * 8))
```

Pour une arène de 60 × 60 m → 512 × 512 pixels → environ 1 Mo de RAM. Négligeable.

**Correspondance monde → pixel :**

```
px = (x + arenaWidth  / 2) / arenaWidth  * largeurTexture
py = (z + arenaDepth  / 2) / arenaDepth  * hauteurTexture
```

Un pixel entièrement transparent (alpha = 0) = sol non peint. Un pixel opaque = peint, avec la couleur de l'équipe.

### 3.2 Les tampons de tache (« stamps »)

Pour garder un rendu organique type Splatoon, on ne peint pas des disques nets. On pré-génère **6 masques de tache** au démarrage, une seule fois.

Chaque masque est un tableau `[UInt8]` carré (par exemple 48 × 48) contenant l'opacité de la tache : contour irrégulier en étoile, bords légèrement adoucis.

Réutiliser la logique existante de `generateSplashGeometry` (générateur `SplitMix64`, rayon qui ondule, pics occasionnels vers l'extérieur) — mais en produisant un masque d'opacité au lieu de sommets.

Ces masques sont générés une fois et ne changent jamais.

### 3.3 L'écriture d'une tache

Quand `paint(atX:z:radius:team:)` est appelée :

1. La logique existante met à jour `owners` et les compteurs. **Inchangée.**
2. En plus, on écrit dans le tampon :
   - choisir un masque parmi les 6 (de façon déterministe, à partir des coordonnées) ;
   - le mettre à l'échelle du rayon demandé ;
   - pour chaque pixel du masque dont l'opacité dépasse un seuil, écrire la couleur de l'équipe dans le tampon ;
   - **ne rien écrire** sur les pixels correspondant à une tuile bloquée (eau, rampes) ;
   - étendre le rectangle « sale » (`dirtyRect`) pour englober la zone touchée.

Coût : quelques milliers d'écritures d'octets. De l'ordre de la dizaine de microsecondes.

### 3.4 L'envoi vers le GPU

Une fois par image, si `dirtyRect` n'est pas vide :

1. envoyer **uniquement le rectangle sale** vers la texture GPU ;
2. remettre `dirtyRect` à vide.

**Voie recommandée :** `TextureResource.DrawableQueue`, disponible depuis iOS 15 et conçue exactement pour ce cas (mise à jour continue d'une texture RealityKit sans réallocation). On récupère un drawable, on écrit la région modifiée dans sa `MTLTexture` via `replaceRegion`, on présente.

**Voie de repli** si la DrawableQueue pose problème : `TextureResource.replace(withImage:)` avec la texture complète, appelée au maximum 20 fois par seconde. Moins propre, mais toujours largement plus rapide que le système actuel.

> **À faire vérifier par l'IA au moment de l'implémentation :** la disponibilité exacte et la signature de ces API pour la cible de déploiement du projet. Ne pas supposer — vérifier dans la documentation.

### 3.5 L'affichage

**Le sol plat :** un seul `ModelEntity`, créé une fois au lancement du match.

- maillage : un plan simple aux dimensions de l'arène ;
- position : légèrement au-dessus du sol (environ +0,02 sur Y) pour éviter le z-fighting ;
- matériau : `UnlitMaterial`, texture de couleur = la texture de peinture, `blending = .transparent(opacity: 1)` pour que les pixels transparents laissent voir le sol ;
- filtrage : `.linear` (le léger flou adoucit les bords, ce qui rend justement mieux qu'un bord net) ;
- `faceCulling = .back`.

**Les surfaces surélevées** (dessus de caisses, plateformes) : un quad plat par surface, créé une fois au chargement de la carte, à partir des `SurfaceClip` déjà déclarés dans `paintSurface(atX:z:)`.

Le point clé : ces quads échantillonnent **la même texture**, avec des UV calculés depuis leur emprise au sol en coordonnées monde. Comme la texture est une carte vue de dessus, un quad placé au-dessus d'une caisse récupère automatiquement la peinture de sa zone. Aucun traitement particulier.

Nombre total d'objets pour toute la peinture : **1 + (nombre de surfaces surélevées)**, typiquement moins de 40, fixe pour toute la partie.

### 3.6 Réinitialisation

En fin de match / au lancement du suivant : remplir le tampon de zéros, envoyer la texture complète une fois, réinitialiser les compteurs. Aucune destruction/recréation d'objet 3D.

---

## 4. Ce qui est supprimé

Dans `PaintGrid.swift`, ces éléments n'ont plus de raison d'être :

- `SplashGeometry` et `generateSplashGeometry` (remplacés par les masques d'opacité)
- `TileInstance` et `makeInstance`
- `rebuildChunk(_:team:)`
- `flushPaintBatches(maxRebuilds:)`
- `forEachCell(inChunk:_:)`
- `chunkEntities`, `dirtySlots`, `dirtyQueue`, `chunkIndex(forTile:)`, `markDirty(chunk:team:)`
- `activePaintEntities`, `setSimplifiedSplash`

Dans `QualitySettings.swift`, ces réglages deviennent inutiles :

- `paintRebuildInterval`
- `paintChunkSize`
- `maxChunkRebuildsPerFlush`
- `simplifiedSplash`

Dans `GameController+Simulation.swift` : le bloc `paintFlushAccum` / `flushPaintBatches` disparaît, remplacé par un simple envoi de la région sale.

**⚠️ Ne rien supprimer d'autre.** Le pool de VFX, le LOD des personnages, le cap de projectiles, l'auto-downgrade de qualité sont corrects et règlent de vrais problèmes. Ils restent.

---

## 5. Plan d'exécution par étapes

À faire **dans l'ordre**, en testant à chaque étape. Ne pas tout lancer d'un coup.

### Étape 1 — Le tampon et son écriture
Créer la classe qui gère le tampon RGBA, les masques de tache, la conversion monde → pixel et l'écriture d'une tache. Brancher l'écriture dans `paint(atX:z:radius:team:)`, **en gardant l'ancien système actif en parallèle**.

*Test :* le jeu tourne exactement comme avant, rien ne change visuellement.

### Étape 2 — L'affichage sur le sol plat
Créer le plan unique avec la texture, l'ajouter à la scène, brancher l'envoi de la région sale. Désactiver le rendu des chunks (mettre leurs entités en `isEnabled = false`, sans supprimer le code encore).

*Test :* la peinture doit s'afficher sur le sol. **C'est ici qu'on saura si les saccades disparaissent.**

### Étape 3 — Les surfaces surélevées
Générer les quads à partir des `SurfaceClip` existants.

*Test :* la peinture apparaît sur les caisses et plateformes.

### Étape 4 — Le nettoyage
Une fois les étapes 1 à 3 validées en jeu, supprimer le code mort listé en section 4, ainsi que les réglages de qualité devenus inutiles.

*Test :* le jeu compile et tourne à l'identique, en plus léger.

---

## 6. Pièges connus

| Piège | Traitement |
|---|---|
| Z-fighting entre le sol et le plan de peinture | Décalage vertical d'au moins 0,02 ; désactiver l'écriture de profondeur sur le matériau transparent si le moteur le permet |
| Peinture visible à travers un mur | Les quads surélevés ne couvrent que leur propre emprise — vérifier le calcul des UV |
| Bords de tache trop nets ou pixellisés | Augmenter la résolution à 12 ou 16 pixels/mètre, ou adoucir le bord des masques |
| Écriture concurrente sur le tampon | Toute l'écriture reste sur le même thread que `paint()`. Ne pas paralléliser cette partie |
| Mémoire | Plafonner la texture à 1024 × 1024. Au-delà, réduire les pixels/mètre |

---

## 7. Réponses aux questions pratiques

**Faut-il fournir des textures / images ?**
Non. Les masques de tache sont générés en code au lancement, comme les formes actuelles. Aucun asset externe n'est nécessaire.

*Optionnel, plus tard :* fournir 3 ou 4 PNG de taches d'encre en niveaux de gris (fond noir, tache blanche, 64 × 64, transparence dans le canal alpha) permettrait un rendu plus travaillé. Mais ce n'est pas nécessaire pour que ça fonctionne, et ça ne change rien aux performances.

**Faut-il d'abord appliquer le correctif ciblé sur `rebuildChunk` ?**
Non, et c'est cohérent : cette refonte **supprime** `rebuildChunk`. Le correctif porterait sur du code destiné à disparaître. Aller directement à la refonte ne gaspille aucun travail.

**Est-ce que ça règle aussi les saccades en déplacement ?**
Celles-là ont déjà nettement diminué en bridant les reconstructions — même cause. La refonte les supprime à la source au lieu de les brider.

**Est-ce que ça touche au réseau ?**
Non. Les opérations de peinture réseau passent déjà par `paint(atX:...)`, qui garde la même signature et le même comportement.

---

## 8. Consigne à donner à l'IA

> Applique **uniquement l'étape 1** décrite dans le document `refonte-peinture-texture.md` que je te fournis. Ne touche à aucun autre fichier que `PaintGrid.swift` et le nouveau fichier que tu créeras pour le tampon de peinture. Ne supprime rien de l'ancien système à cette étape : les deux doivent coexister. Quand tu as fini, dis-moi précisément quels fichiers tu as modifiés et ce que je dois voir en jeu pour valider.

Puis, une fois validé, la même consigne pour l'étape 2, et ainsi de suite.

**Une étape à la fois. Un test après chaque étape.**
