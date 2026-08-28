# SPLASH — Interface hors-jeu (code source Swift)

Export du code SwiftUI de tout ce qui n'est **pas** le rendu 3D du match :
menus, missions, boutique, profil, armes, sélection d'arène, lobby, résultats.

- **44 fichiers Swift**
- `SPLASH-UI-BUNDLE.txt` = tous les fichiers concaténés dans un seul document
  (pratique pour lire d'un bloc ou coller dans une IA)
- `SPLASH-UI-SWIFT.zip` = la même chose en archive, structure de dossiers conservée

Framework : **SwiftUI** (déclaratif, proche en esprit de UI Toolkit d'Unity).
Chaque écran est une `struct` conforme à `View` avec un `body` qui décrit l'arbre visuel.

---

## 1. Point d'entrée & navigation

| Fichier | Rôle |
|---|---|
| `ContentView.swift` | Racine de l'app. Aiguille entre écran de chargement, hub et match. |
| `Views/Hub/HubView.swift` | Conteneur principal des menus + barre d'onglets du bas. |
| `Views/Hub/SplashHomeView.swift` | Écran d'accueil principal (le plus gros écran, 27 Ko). |
| `Views/Hub/HomeTabView.swift` | Onglet Accueil. |

## 2. Écrans de jeu (avant le match)

| Fichier | Rôle |
|---|---|
| `Views/Hub/PlayScreen.swift` | Choix du mode de jeu. |
| `Views/Hub/ArenaSelectScreen.swift` | Sélection de la map/arène. |
| `Views/Hub/LobbyView.swift` | Salon d'attente avant match. |
| `Views/Hub/LocalMatchView.swift` | Match local (multijoueur en local). |
| `Views/Hub/PlayerConnectScreen.swift` | Connexion des joueurs en local. |
| `Views/Hub/OddsView.swift` | Affichage des cotes / probabilités. |

## 3. Armes & équipement

| Fichier | Rôle |
|---|---|
| `Models/WeaponType.swift` | **Définition de toutes les armes** (stats, cadence, dégâts, portée). |
| `Views/Hub/EquipmentScreen.swift` | Écran d'équipement : choix arme principale + secondaires. |
| `Views/LockerRoomView.swift` | Vestiaire : aperçu du personnage équipé. |
| `Models/FighterStats.swift` | Statistiques d'un combattant. |
| `Views/Hub/RadarChartView.swift` | Graphique radar des stats d'arme (composant réutilisable). |

## 4. Progression : missions, rang, saison

| Fichier | Rôle |
|---|---|
| `Views/Hub/MissionsScreen.swift` | **Écran des missions / défis.** |
| `Views/Hub/RankScreen.swift` | Écran de rang et de classement. |
| `Views/Hub/SeasonPassView.swift` | Passe de saison, paliers de récompenses. |
| `Views/Hub/ChestRevealView.swift` | Animation d'ouverture de coffre. |
| `Models/MetaModels.swift` | Modèles de méta-progression (missions, récompenses, monnaies). |
| `Services/MetaStore.swift` | **Logique + sauvegarde** de la progression (missions, XP, coffres). |

## 5. Boutique & profil

| Fichier | Rôle |
|---|---|
| `Views/Hub/ShopScreen.swift` | Boutique. |
| `Views/Hub/ShopTabView.swift` | Onglet boutique. |
| `Views/Hub/ProfileScreen.swift` | Profil joueur détaillé. |
| `Views/Hub/ProfileTabView.swift` | Onglet profil. |
| `Services/ProfileStore.swift` | Sauvegarde du profil (pseudo, avatar, stats). |
| `Models/AvatarIconCatalog.swift` | Catalogue des icônes d'avatar. |

## 6. Réglages & annexes

| Fichier | Rôle |
|---|---|
| `Views/Hub/SettingsScreen.swift` | Paramètres (audio, graphismes, commandes, compte). |
| `Views/Hub/GlossaryView.swift` | Glossaire / aide. |
| `Views/Hub/LegalDocuments.swift` | Mentions légales, CGU. |
| `Views/Hub/PerfReportView.swift` | Rapport de performance (outil de debug). |
| `Services/QualitySettings.swift` | Presets de qualité graphique. |

## 7. Style & habillage (⭐ à lire en premier pour reproduire le look)

| Fichier | Rôle |
|---|---|
| `Views/Hub/MenuStyleKit.swift` | **Design system : couleurs, polices, boutons, cartes, ombres.** C'est le fichier clé pour reproduire l'identité visuelle. |
| `Views/MenuBackground.swift` | Fond animé des menus. |
| `Views/LaunchLoadingView.swift` | Écran de lancement de l'app. |
| `Views/LoadingView.swift` | Écran de chargement entre menus et match. |

## 8. Après le match

| Fichier | Rôle |
|---|---|
| `Views/ResultsView.swift` | Écran de fin de partie : scores, XP gagné, récompenses. |

## 9. Modèles de données partagés

| Fichier | Rôle |
|---|---|
| `Models/GameConfig.swift` | Configuration globale (map active, réglages de partie). |
| `Models/ArenaMap.swift` | Liste et définition des arènes. |
| `Models/MatchMode.swift` | Modes de jeu. |
| `Models/Team.swift` | Équipes et couleurs. |
| `Models/BotDifficulty.swift` | Niveaux de difficulté des bots. |
| `Models/LocalMatchModels.swift` | Modèles du multijoueur local. |
| `Services/LocalMatchService.swift` | Service réseau du match local. |

---

## Notes pour un portage Unity

- **SwiftUI ≈ UI Toolkit** dans l'esprit : arbre déclaratif, style séparé, layout automatique.
  Le mapping le plus direct : une `struct View` → un `VisualElement` custom ou un prefab uGUI.
- `MenuStyleKit.swift` contient toutes les constantes de design (couleurs, rayons de coin,
  tailles de police, espacements). C'est ce qu'il faut traduire en premier — en Unity,
  ça devient un `ScriptableObject` de thème ou une feuille `.uss`.
- Les `Store` (`MetaStore`, `ProfileStore`) sont des singletons observables qui gèrent état
  + persistance disque. Équivalent Unity : un `ScriptableObject` runtime ou un service
  singleton avec sérialisation JSON.
- `@Observable` / `@State` → le rafraîchissement de l'UI est automatique quand la donnée change.
  En Unity il faudra câbler ça à la main (events / `UnityEvent` / binding UI Toolkit).
- Ces écrans sont **hors rendu 3D**, donc côté Unity ils peuvent être faits en uGUI ou
  UI Toolkit sans contrainte de perf, contrairement au HUD in-game.
