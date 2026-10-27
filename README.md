# SchoolSpaceApp

Application iOS native (SwiftUI, iOS 26+) pour accéder à son espace personnel d'établissement scolaire.

## Architecture

- **Mode sombre uniquement** (`.preferredColorScheme(.dark)`)
- **Liquid Glass** natif iOS 26 (`.glassEffect`, `GlassEffectContainer`)
- **Couleur d'accent** : Vert (#00CC00) définie dans Assets.xcassets
- **Zéro serveur** : Tout se passe en local sur l'iPhone
- **Sécurité** : Session stockée dans Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`)

## Structure du projet

```
Sources/
├── SchoolSpaceApp.swift          # Point d'entrée
├── Info.plist                    # Configuration app (permissions, etc.)
├── Models/
│   └── SchoolModels.swift        # Modèles : School, UserSession, DecodedQRCode, Erreurs
├── Services/
│   ├── KeychainService.swift     # Stockage sécurisé session
│   ├── NetworkService.swift      # API géolocalisation, validation URL
│   ├── QRCodeService.swift       # Scanner + déchiffrement QR code (AES-GCM + PBKDF2)
│   └── SessionManager.swift      # Gestion session, WKWebView login, reconnexion auto
├── Components/
│   └── GlassComponents.swift     # Composants Liquid Glass réutilisables (InfoCard, etc.)
└── Views/
    ├── ContentView.swift         # Router principal
    ├── ConnectionChoiceView.swift  # Écran 1 : 3 méthodes de connexion
    ├── QRCodeScannerView.swift   # Scanner QR + saisie PIN 4 chiffres
    ├── LocationPickerView.swift  # Liste établissements proches (géoloc)
    └── URLEntryView.swift        # Saisie manuelle URL + validation
```

## Fonctionnalités implémentées

### Écran 1 : Choix de connexion
- Titre : "Comment souhaitez-vous vous connecter à votre espace personnel ?"
- 3 boutons Liquid Glass :
  1. **QR Code** → Scanner AVFoundation + cadre de visée → Saisie PIN 4 chiffres → Déchiffrement AES-GCM
  2. **Géolocalisation** → Permission "pendant l'utilisation" → API data.education.gouv.fr (geosearch) → Liste triée par distance
  3. **URL manuelle** → Champ validation HTTPS + index-education.net → Test joignabilité (HEAD)

### Connexion (commune aux 3 chemins)
- WKWebView intégré sur `mobile.eleve.html`
- Barre de progression, navigation minimale
- Détection automatique connexion via script injecté (MutationObserver + polling)
- Extraction cookies de session + nom utilisateur
- Sauvegarde Keychain (token seulement, **jamais le mot de passe**)

### Reconnexion automatique
- Au lancement : lecture Keychain → validation expiration → session restaurée
- Si expirée : message clair + retour écran 1

### Déconnexion
- Bouton "Se déconnecter" → suppression Keychain + cache local

### Écran 2 : Après connexion
- "Bonjour, Prénom Nom" (récupéré depuis la session)
- Infos établissement + bouton déconnexion

### Composant réutilisable : InfoCard
- Structure conforme à la référence visuelle fournie
- Icône ronde + label (tronqué) → Titre gras → Sous-titre discret → Valeur grande + suffixe
- Style Liquid Glass, thème sombre, accent vert

## Conformité légale

- **Aucune mention de "Pronote"** dans l'interface, noms de fichiers, types, messages d'erreur, Info.plist
- Termes utilisés : "espace personnel", "établissement", "compte", "espace"
- Package/bundle ID : `com.example.schoolspace`
- Nom affiché : "Espace Personnel"

## Points à tester / vérifier (non vérifiés)

| Point | Description | Statut |
|-------|-------------|--------|
| **Format exact QR code** | Structure JSON `{jeton, login, url}` chiffré AES-GCM avec PIN 4 chiffres. Clé dérivée via HKDF-SHA256 (salt fixe). Nonce 12 octets + tag 16 octets. | ⚠️ À tester avec vrai QR code |
| **Déchiffrement PIN** | Algorithme exact (AES-256-GCM, PBKDF2/HKDF, itérations, encodage Base64). Peut varier selon version. | ⚠️ À tester |
| **API géolocalisation Index Éducation** | `NetworkService` utilise `data.education.gouv.fr` (officiel Ministère). L'URL `https://<UAI>.index-education.net/pronote/` est construite depuis le UAI. Le backend Index Éducation peut avoir une API dédiée (`pronote.geo`) non documentée publiquement. | ⚠️ À tester avec vraies coordonnées |
| **Détection connexion WKWebView** | Script `loginDetectionScript` utilise sélecteurs génériques (`.user-name`, `.welcome-message`, cookies `sessionid`/`PHPSESSID`/`JSESSIONID`). Le DOM réel de `mobile.eleve.html` peut différer. | ⚠️ À tester sur vraie page |
| **Extraction nom utilisateur** | Depuis `.user-name`, `[data-user-name]`, `.welcome-message`. À adapter selon DOM réel. | ⚠️ À tester |
| **Extraction establishmentId** | Depuis `[data-establishment-id]`, `.establishment-name`. Fallback "unknown". | ⚠️ À tester |
| **Cookies de session** | Noms possibles : `sessionid`, `PHPSESSID`, `JSESSIONID`, ou cookie complet. Durée expiration supposée 30 jours. | ⚠️ À tester |
| **Renouvellement session** | Non implémenté (TODO). Actuellement redemande login si expiré. | 🔄 À implémenter si besoin |

## Build & Run

1. Ouvrir `SchoolSpaceApp.xcodeproj` dans Xcode 16+ (iOS 26 SDK)
2. Sélectionner un simulateur iOS 26+ ou device physique
3. Build & Run (⌘R)

## Dépendances

- Aucune dépendance externe (SwiftUI, Foundation, Security, WebKit, CryptoKit, CoreLocation, AVFoundation uniquement)

## Notes importantes

- L'app **ne fonctionne que sur iOS 26+** (Liquid Glass, `GlassEffectContainer`)
- Tester sur **device physique** pour : caméra (QR), géolocalisation, Keychain
- Le simulateur ne supporte pas la caméra ni la géolocalisation réelle