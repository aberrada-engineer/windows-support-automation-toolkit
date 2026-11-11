<div align="center">

# 🖥️ ESN-Toolkit

### Workstation & Infrastructure Automation Toolkit

**Plateforme PowerShell enterprise de diagnostic, remédiation automatique,  
scoring santé et migration de postes — conçue pour les environnements ESN multi-clients.**

---

<!-- Remplacer aberrada-engineer par votre handle GitHub -->
![Version](https://img.shields.io/badge/version-3.0.0-blue?style=flat-square)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?style=flat-square&logo=powershell&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Windows%2010%2F11-0078D4?style=flat-square&logo=windows&logoColor=white)
![Lines](https://img.shields.io/badge/Lines%20of%20Code-7%2C749-orange?style=flat-square)
![Modules](https://img.shields.io/badge/Modules-8-purple?style=flat-square)
![Tests](https://img.shields.io/badge/Pester%20Tests-70%2B-brightgreen?style=flat-square)
![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)
[![CI](https://github.com/aberrada-engineer/ESN-Toolkit/actions/workflows/ci.yml/badge.svg)](https://github.com/aberrada-engineer/ESN-Toolkit/actions/workflows/ci.yml)

---

[À propos](#-à-propos) •
[Fonctionnalités](#-fonctionnalités) •
[Architecture](#-architecture) •
[Démarrage rapide](#-démarrage-rapide) •
[Exemples](#-exemples) •
[Scoring santé](#-système-de-scoring-santé) •
[Migration](#-migration-de-postes) •
[Roadmap](#-roadmap)

</div>

---

## 🎯 À propos

ESN-Toolkit est une **plateforme d'automatisation opérationnelle PowerShell** conçue pour les techniciens support, administrateurs systèmes et ingénieurs infrastructure en environnement ESN multi-clients.

En **une seule commande**, le toolkit :

- Analyse complètement un poste (réseau, système, sécurité, stockage, services)
- Calcule un **score de santé pondéré 0–100** par domaine
- Détecte les problèmes et applique des **remédiations automatiques** (8 cas couverts)
- Génère un **rapport HTML professionnel offline** exploitable immédiatement en ticket
- Exporte un **JSON structuré** (schéma unifié OK/WARNING/CRITICAL) pour intégration
- Consulte une **base de connaissances** de 20 patterns d'incidents ESN courants

> **Zéro dépendance externe — PowerShell 5.1 natif Windows 10/11 — exécutable immédiatement.**

---

## ✨ Fonctionnalités

### 🔍 Diagnostic multi-domaines

| Domaine | Ce qui est analysé | Poids score |
|---|---|---|
| **Réseau** | IP/APIPA, passerelle, DNS, latence, pertes paquets, proxy, lecteurs réseau | 20% |
| **Système** | OS, RAM, CPU, uptime, events critiques 24h, crash dumps, Windows Update | 20% |
| **Sécurité** | Defender, firewall, BitLocker, SMBv1, WDigest, UAC, RDP NLA, certificats | 25% |
| **Stockage** | % utilisation par disque, SMART prédictif, fichiers temporaires volumineux | 20% |
| **Services** | Services critiques arrêtés, services auto non démarrés | 15% |
| **Active Directory** | Domaine, DCs joignables, réplication, comptes, admins, KRBTGT | — |
| **Microsoft 365** | Licences SKU, MFA, utilisateurs inactifs, comptes invités | — |

### 🔧 Auto-remédiation — 8 cas couverts

| ID | Remédiation | Risque | Requiert Admin |
|---|---|---|---|
| `DNS` | Flush cache DNS + ipconfig /flushdns | Low | Non |
| `Winsock` | Reset pile TCP/IP (redémarrage requis) | Medium | Oui |
| `Services` | Redémarrage services critiques arrêtés | Low | Oui |
| `Teams` | Nettoyage cache Teams v1 + v2 MSIX | Low | Non |
| `Outlook` | Mode hors-ligne, add-ins crashés, RoamCache | Low | Non |
| `OneDrive` | Relance, suppression .lock, reset sync | Low | Non |
| `TempFiles` | Nettoyage %TEMP%, Windows\Temp, INetCache | Low | Non |
| `WindowsUpdate` | Reset composants WU, DLL, catroot2, SoftwareDistribution | Medium | Oui |

### 📊 Score santé pondéré 0–100

Score global calculé comme moyenne pondérée des 5 domaines techniques avec traçabilité complète de chaque impact.

### 📋 Rapport HTML offline complet

- Score global + jauges SVG par domaine
- Résumé exécutif avec verdict coloré
- Machine info (OS, RAM, CPU, uptime, domaine)
- Impacts détaillés sur le score (traçabilité)
- Recommandations actionnables
- Remédiations exécutées (avant/après)
- Base de connaissances : patterns d'incidents détectés automatiquement
- Sections pliables — CSS inline uniquement, **zéro dépendance externe**

### 🚚 Migration de postes

- Capture complète profil utilisateur
- **Score de réussite migration 0–100**
- Manifest JSON v2.0 avec stats par module
- Comparaison avant/après (fichiers source vs destination)
- Détection automatique d'anomalies
- Rapport HTML migration intégré

### 📚 Base de connaissances incidents

20 patterns statiques — format `symptom → cause → remédiation → commande PowerShell`

Domaines couverts : Network · System · Security · Storage · Services · AD · Outlook · VPN · Windows Update · Migration

---

## 🏗️ Architecture

```
ESN-Toolkit/
│
├── Invoke-IncidentAnalysis.ps1      ← Point d'entrée principal (orchestrateur v3)
├── Invoke-Migration.ps1             ← CLI Migration (capture / restauration)
│
├── Core/
│   ├── ESN-Core.psm1                ← Logging + Session + ZIP incident
│   ├── ESN-OutputSchema.ps1         ← Schéma JSON unifié OK/WARNING/CRITICAL
│   ├── ESN-ReportBuilder.ps1        ← Rapport HTML offline complet
│   └── IncidentPatterns.json        ← Base de connaissances 20 patterns
│
├── Modules/
│   ├── Network/    ESN-Network.psm1       ← Diagnostic réseau complet
│   ├── Windows/    ESN-Windows.psm1       ← Diagnostic système Windows
│   ├── AD/         ESN-AD.psm1            ← Active Directory + actions
│   ├── M365/       ESN-M365.psm1          ← Microsoft 365 via Graph API
│   ├── Remediation/ESN-Remediation.psm1  ← Auto-remédiation 8 cas
│   ├── HealthScore/ESN-HealthScore.psm1  ← Scoring pondéré 5 domaines
│   └── Migration/  ESN-Migration.psm1    ← Migration utilisateur v2
│
├── Tests/
│   ├── ESN-Toolkit.Tests.ps1        ← Tests Core + modules (30+)
│   ├── ESN-Remediation.Tests.ps1    ← Tests remédiation (20+)
│   └── ESN-HealthScore.Tests.ps1    ← Tests scoring (50+)
│
└── .github/workflows/ci.yml         ← CI : PSScriptAnalyzer + Pester
```

<!-- PLACEHOLDER — Diagramme architecture
![Architecture ESN-Toolkit](docs/screenshots/architecture.png)
Générer avec draw.io ou Mermaid et déposer dans docs/screenshots/
-->

---

## 🚀 Démarrage rapide

### Prérequis

| Composant | Version | Notes |
|---|---|---|
| PowerShell | 5.1+ | Inclus nativement Windows 10/11 |
| Windows | 10 (1903+) / 11 | Windows Server 2016+ supporté |
| RSAT (AD) | Optionnel | Active uniquement le module AD |
| Microsoft.Graph | Optionnel | Active uniquement le module M365 |
| Pester | 5.0+ | Tests uniquement |

> **Aucune dépendance externe obligatoire.** Robocopy (natif Windows) requis pour la migration.

### Installation 1-Clic (Recommandé)

Faites un clic droit sur **`Setup.bat`** et sélectionnez **« Exécuter en tant qu'administrateur »** :
- Déploie l'environnement dans `C:\ESN-Toolkit`
- Configure automatiquement les droits d'exécution PowerShell
- Crée les raccourcis sur le Bureau : **Interface Graphique (GUI)** et **Console Interactive**

Ou manuellement en PowerShell :
```powershell
# Cloner le repository
git clone https://github.com/aberrada-engineer/windows-support-automation-toolkit.git C:\ESN-Toolkit
cd C:\ESN-Toolkit

# Exécuter l'installeur
.\Install-ESNToolkit.ps1
```

### Modes d'utilisation

1. **🖥️ Interface Graphique (GUI)** : Double-cliquez sur **`ESN-Launcher.bat`** pour piloter les audits, auto-réparations et exports sans taper une seule commande.
2. **⚡ Console Interactive (TUI)** : Double-cliquez sur **`ESN-Console.bat`** pour un menu interactif numéroté (idéal en session RDP ou serveur).
3. **💻 En Ligne de Commande (CLI)** : Exécutez directement les scripts avec paramètres.

### Première utilisation

```powershell
# Diagnostic complet du poste local — rapport HTML ouvert à la fin
.\Invoke-IncidentAnalysis.ps1 -OpenReport

# Diagnostic + auto-fix + ZIP incident
.\Invoke-IncidentAnalysis.ps1 -AutoFix -ExportZip -OpenReport

# Diagnostic d'un poste distant avec ticket
.\Invoke-IncidentAnalysis.ps1 -ComputerName "PC-DUPONT" -IncidentId "INC-20250515" -OpenReport
```

---

## 💡 Exemples

### Analyse d'incident N1/N2

```powershell
# Analyse réseau + système uniquement (appel rapide en support)
.\Invoke-IncidentAnalysis.ps1 -Modules Network,Windows

# Diagnostic réseau avec auto-correction DNS
.\Invoke-IncidentAnalysis.ps1 -Modules Network -Fix DNS -Force

# Analyse complète en simulation (aucune modification système)
.\Invoke-IncidentAnalysis.ps1 -AutoFix -Simulation -OpenReport

# Audit AD seul
.\Invoke-IncidentAnalysis.ps1 -Modules AD

# Audit M365 avec rapport
.\Invoke-IncidentAnalysis.ps1 -Modules M365 -OpenReport
```

**Objet retourné (pipeline-friendly) :**

```powershell
$r = .\Invoke-IncidentAnalysis.ps1 -Modules Network,Windows,AD

$r.HealthScore        # 82  — score global pondéré
$r.ScoreNetwork       # 95  — score réseau
$r.ScoreSecurity      # 70  — score sécurité
$r.DiagErrors         # 2   — erreurs détectées
$r.RemediationsFixed  # 3   — remédiations appliquées
$r.RebootRequired     # False
$r.ReportPath         # C:\ESN-Toolkit\Reports\..._rapport.html
$r.JsonPath           # C:\ESN-Toolkit\Reports\....json
$r.ZipPath            # C:\ESN-Toolkit\ZipIncidents\....zip
```

### Troubleshooting — cas fréquents en ESN

```powershell
# Poste sans internet — diagnostic + corrections réseau
.\Invoke-IncidentAnalysis.ps1 -Modules Network -Fix DNS,Winsock -Force

# PC lent — analyse + nettoyage fichiers temporaires
.\Invoke-IncidentAnalysis.ps1 -Modules Windows -Fix TempFiles -AutoFix

# Outlook ne s'ouvre plus / mode hors-ligne bloqué
.\Invoke-IncidentAnalysis.ps1 -Fix Outlook -AutoFix -Force

# Teams lent ou qui plante
.\Invoke-IncidentAnalysis.ps1 -Fix Teams -AutoFix -Force

# Windows Update bloqué
.\Invoke-IncidentAnalysis.ps1 -Fix WindowsUpdate -AutoFix -Force

# Collecte logs pour ticket (zéro modification)
.\Invoke-IncidentAnalysis.ps1 -Modules Network,Windows -ExportZip

# OneDrive ne se synchronise plus
.\Invoke-IncidentAnalysis.ps1 -Fix OneDrive -AutoFix -Force
```

### Auto-remédiation ciblée

```powershell
Import-Module .\Modules\Remediation\ESN-Remediation.psm1

# Voir tout le catalogue disponible
Get-RemediationCatalog

# Tester si un problème est présent (sans rien modifier)
Test-RemediationNeeded -Id "DNS"
Test-RemediationNeeded -Id "TempFiles"

# Détecter tous les problèmes sans corriger
Invoke-Remediation

# Appliquer automatiquement tout ce qui est détecté
Invoke-Remediation -AutoFix -Force

# Cibler des remédiations précises
Invoke-Remediation -Fix DNS,Teams,TempFiles -AutoFix -Force

# Poste distant
Invoke-Remediation -ComputerName "PC-DUPONT" -AutoFix -Force

# Simulation complète (aucune modification)
Invoke-Remediation -AutoFix -Simulation
```

### Actions Active Directory

```powershell
Import-Module .\Modules\AD\ESN-AD.psm1
Import-Module .\Core\ESN-Core.psm1
Initialize-ESNSession -ScriptName "AD-Fix" -IncidentId "INC-AD-001"

# Audit complet du domaine (comptes, DCs, réplication, GPO)
Invoke-ADAudit -InactiveDays 90

# Déverrouiller un compte
Invoke-ADUserReset -Username "jdupont" -UnlockOnly

# Reset mot de passe + déverrouillage (MDP temporaire généré)
Invoke-ADUserReset -Username "jdupont"

# Créer un utilisateur avec convention de nommage ESN
New-ADUserESN -FirstName "Marie" -LastName "Dupont" `
              -Department "Finance" -Title "Comptable" -Manager "jmartin"
```

### Rapport HTML — structure de sortie

<!-- PLACEHOLDER — Screenshot rapport HTML
![Rapport HTML ESN-Toolkit](docs/screenshots/rapport-html.png)
Capturer le rapport dans C:\ESN-Toolkit\Reports\ et déposer dans docs/screenshots/
-->

```
┌─────────────────────────────────────────────────────────────┐
│  Score Global : 82/100 — Bon                                │
│  ████████████████░░░░                                       │
│                                                             │
│  [Réseau 95] [Système 80] [Sécurité 70] [Stock. 88] [Svc 100] │
│                                                             │
│  Machine : PC-DUPONT | Windows 11 Pro | RAM 8 Go | i7-12700 │
│                                                             │
│  ▶ Recommandations actionnables    [3 actions]   [pliable]  │
│  ▶ Impacts détaillés sur le score  [traçabilité] [pliable]  │
│  ▶ Base de connaissances incidents [2 patterns]  [pliable]  │
│  ▶ Remédiations exécutées          [3 corrigées] [pliable]  │
│  ▶ Détail de tous les checks       [47 résultats][pliable]  │
│  {} Export JSON                    [payload inline]         │
└─────────────────────────────────────────────────────────────┘
```

---

## 📊 Système de scoring santé

### Grille de pondération

```
Score Global = Réseau×20% + Système×20% + Sécurité×25% + Stockage×20% + Services×15%
```

| Domaine | Poids | Principaux critères évalués |
|---|---|---|
| **Réseau** | 20% | IP valide, passerelle joignable, DNS résolu, latence, internet |
| **Système** | 20% | RAM, CPU, uptime, events critiques 24h, crash dumps |
| **Sécurité** | 25% | Defender actif, firewall, BitLocker, SMBv1 off, WDigest off, UAC |
| **Stockage** | 20% | % disque C: (pondéré), SMART prédictif, fichiers temp |
| **Services** | 15% | Services critiques en cours d'exécution |

### Niveaux de score et labels

| Score | Label | Signification |
|---|---|---|
| 90–100 | **Excellent** | Machine saine, aucune action requise |
| 80–89 | **Bon** | État correct, quelques optimisations possibles |
| 60–79 | **Dégradé** | Problèmes non bloquants, action recommandée |
| 40–59 | **Mauvais** | Problèmes impactant les performances |
| 0–39 | **Critique** | Intervention immédiate requise |

### Grille scoring sécurité (exemple détaillé)

| Check | Points | Pénalité si KO |
|---|---|---|
| Windows Defender actif | 20 pts | −20 pts |
| Firewall domaine actif | 15 pts | −15 pts |
| SMBv1 désactivé | 10 pts | −10 pts (CRITIQUE) |
| WDigest désactivé | 10 pts | −10 pts (CRITIQUE) |
| UAC actif | 5 pts | −5 pts |
| BitLocker actif | 10 pts | −6 pts si inactif |
| Firewall public actif | 10 pts | −10 pts |
| RDP NLA requis | 5 pts | −3 pts si absent |

### Traçabilité des impacts

```
Domaine      │ Problème                     │ Impact score
─────────────┼──────────────────────────────┼─────────────
Sécurité     │ SMBv1 ACTIVÉ                 │ −10 pts
Sécurité     │ Firewall public désactivé    │ −10 pts
Système      │ RAM à 92%                    │ −25 pts
Services     │ WinDefend arrêté (critique)  │ −25 pts
Réseau       │ Latence 250ms                │ − 8 pts
```

### Comparaison avant/après remédiation

```powershell
$avant = Invoke-HealthScore -PassThru
Invoke-Remediation -AutoFix -Force
$apres = Invoke-HealthScore -PassThru
Compare-HealthScore -Before $avant -After $apres
```

```
  Global      Avant:  58  Après:  81  ▲ +23
  Network     Avant:  95  Après:  95  = 0
  Security    Avant:  25  Après:  75  ▲ +50
  System      Avant:  70  Après:  80  ▲ +10
  Storage     Avant:  85  Après:  85  = 0
  Services    Avant:  60  Après:  80  ▲ +20
```

---

## 🚚 Migration de postes

### Ce qui est migré

| Module | Contenu | Score impact |
|---|---|---|
| **Données** | Bureau, Documents, Téléchargements, Images, Musique, Vidéos | 30 pts |
| **Outlook** | PST, signatures Outlook, registre Office | 20 pts |
| **Navigateurs** | Chrome, Edge, Firefox (favoris, extensions, préférences) | 10 pts |
| **Imprimantes** | Documentation CSV + script `Reinstall-Printers.ps1` | 10 pts |
| **Lecteurs réseau** | Documentation CSV + script `Remap-Drives.ps1` | 10 pts |
| **Intégrité** | Comparaison fichiers source vs destination | 15 pts |
| **Manifest** | JSON v2.0 validé avec stats complètes | 5 pts |

### Exemples de commandes migration

```powershell
# ÉTAPE 1 — Capturer l'ancien poste (tout inclus)
.\Invoke-Migration.ps1 -Action Capture `
    -SourceComputer "PC-ANCIEN" `
    -Username "jdupont" `
    -All

# ÉTAPE 2 — Restaurer sur le nouveau poste
.\Invoke-Migration.ps1 -Action Restore `
    -BackupDir "C:\ESN-Toolkit\Migrations\jdupont_PC-ANCIEN_2025-05-15_1430" `
    -TargetComputer "PC-NOUVEAU" `
    -Username "jdupont"

# Capture sélective (Outlook + données uniquement)
.\Invoke-Migration.ps1 -Action Capture `
    -SourceComputer "PC-ANCIEN" `
    -Username "jdupont" `
    -IncludeOutlook

# Simulation capture (audit sans copie réelle)
.\Invoke-Migration.ps1 -Action Capture `
    -SourceComputer "PC-ANCIEN" `
    -Username "jdupont" `
    -All -Simulation

# Menu interactif si -BackupDir non précisé
.\Invoke-Migration.ps1 -Action Restore -TargetComputer "PC-NOUVEAU"
```

### Manifest JSON v2.0 généré

```json
{
  "SchemaVersion": "2.0",
  "Username": "jdupont",
  "SourceComputer": "PC-ANCIEN",
  "TargetComputer": "PC-NOUVEAU",
  "SizeMB": 4820,
  "ValidationScore": 87,
  "AnomalyCount": 1,
  "Anomalies": ["Chrome : profil introuvable"],
  "CaptureStats": {
    "Data": { "Desktop": { "SourceFiles": 142, "CopiedFiles": 142, "MissingFiles": 0 } },
    "Outlook": { "PST": 1, "Signatures": true }
  }
}
```

<!-- PLACEHOLDER — Screenshot rapport migration
![Rapport Migration ESN-Toolkit](docs/screenshots/migration-report.png)
-->

---

## 🌍 Environnements supportés

| Composant | Version minimale | Notes |
|---|---|---|
| PowerShell | 5.1 | Inclus Windows 10/11 — PS7 recommandé |
| Windows Client | 10 (1903+) | Windows 11 pleinement supporté |
| Windows Server | 2016+ | 2019 / 2022 recommandé |
| RSAT (module AD) | Optionnel | `Add-WindowsCapability -Online -Name Rsat.ActiveDirectory*` |
| Microsoft.Graph | Optionnel | `Install-Module Microsoft.Graph -Scope CurrentUser` |
| Pester | 5.0+ | Tests uniquement — `Install-Module Pester -Scope CurrentUser` |
| Robocopy | Natif Windows | Requis pour la migration de postes |

---

## 🧪 Tests

```powershell
# Installer Pester
Install-Module Pester -Force -Scope CurrentUser

# Lancer tous les tests
Invoke-Pester .\Tests\ -Output Detailed

# Par module
Invoke-Pester .\Tests\ESN-Toolkit.Tests.ps1     -Tag "Core"        -Output Detailed
Invoke-Pester .\Tests\ESN-Toolkit.Tests.ps1     -Tag "Network"     -Output Detailed
Invoke-Pester .\Tests\ESN-Remediation.Tests.ps1 -Tag "Simulation"  -Output Detailed
Invoke-Pester .\Tests\ESN-HealthScore.Tests.ps1  -Tag "Scoring"     -Output Detailed
Invoke-Pester .\Tests\ESN-HealthScore.Tests.ps1  -Tag "Integration" -Output Detailed
```

| Fichier | Tests | Domaines couverts |
|---|---|---|
| `ESN-Toolkit.Tests.ps1` | 30+ | Core, Session, Network, Windows, AD, Migration |
| `ESN-Remediation.Tests.ps1` | 20+ | Catalogue, détection, simulation, fix réel, rapport |
| `ESN-HealthScore.Tests.ps1` | 50+ | Calcul score, pondération, recommandations, comparaison |

---

## 📐 Conventions

### Nommage des fichiers

```
[CATEG]-[ACTION]-[SUJET].ps1

Exemples :
  NET-Diag-ReseauComplet.ps1
  AD-Reset-UserPassword.ps1
  SEC-Audit-PrivilegesAD.ps1
  MIG-Backup-UserProfile.ps1
```

### Niveaux de gravité unifiés (ESN-OutputSchema)

| Niveau | Impact score défaut | Signification |
|---|---|---|
| `OK` | 0 pt | Aucun problème |
| `INFO` | 0 pt | Information contextuelle |
| `WARNING` | −5 pts | Dégradation non bloquante |
| `CRITICAL` | −15 pts | Blocage ou risque élevé |

### Header standard de script

```powershell
<#
.SYNOPSIS    Résumé en une ligne
.DESCRIPTION Description détaillée
.NOTES
    Auteur  : Amine Berrada
    Version : 1.0.0
    Niveau  : N1 | N2 | N3
    Tags    : réseau, DNS, IP, utilisateur
    Durée   : ~5 min
    Urgence : Faible | Moyen | Critique
#>
```

---

## 🗺️ Roadmap

### v3.1.0 — Prochaine version

- [ ] Tests Pester pour `ESN-OutputSchema` et `ESN-ReportBuilder`
- [ ] Module `ESN-FortiGate` — diagnostic VPN SSH, analyse logs
- [ ] Module `ESN-Veeam` — statut jobs backup, alertes PRA/PCA
- [ ] Alerte Teams webhook intégrée dans `ESN-Remediation`
- [ ] Remédiation : reset profil Teams v2 (MSIX)
- [ ] Remédiation : réparation OneDrive Known Folder Move

### v4.0.0 — Vision long terme

- [ ] Dashboard HTML temps réel multi-serveurs
- [ ] Module PRTG (API REST) — intégration supervision
- [ ] Runbook interactif guidé P1/P2
- [ ] Support PowerShell 7 natif (`ForEach-Object -Parallel`)
- [ ] Export webhook vers GLPI / ServiceNow
- [ ] Module `ESN-Linux` complet (Bash + remontée PS)

---

## 🤝 Contribution

### Standards de contribution

1. **Fork** le repository — créer une branche depuis `main`
2. **Nommer la branche** : `feat/nom-fonctionnalite` ou `fix/nom-bug`
3. **Respecter** le header standard de script (voir Conventions)
4. **Ajouter des tests Pester** pour toute nouvelle fonction
5. **Vérifier** localement avant PR :

```powershell
Install-Module PSScriptAnalyzer -Scope CurrentUser
Invoke-ScriptAnalyzer -Path .\MonScript.ps1 -Severity Error,Warning
Invoke-Pester .\Tests\ -Output Minimal
```

6. **Ouvrir une Pull Request** avec description claire

### Ce que nous acceptons

- ✅ Nouveaux modules (respectant l'architecture existante)
- ✅ Nouveaux patterns dans `IncidentPatterns.json`
- ✅ Nouvelles remédiations dans `ESN-Remediation.psm1`
- ✅ Amélioration des tests Pester
- ✅ Documentation et corrections de bugs

### Ce que nous n'acceptons pas

- ❌ Dépendances externes non natives Windows
- ❌ Refonte de l'architecture existante
- ❌ Suppression de la rétro-compatibilité PowerShell 5.1
- ❌ Scripts sans tests associés

---

## 👤 Auteur

**Amine Berrada** — Ingénieur Systèmes & Réseaux | ESN Multi-clients

Stack : Windows Server · Active Directory · Azure / Entra ID · VMware · Nutanix  
Veeam · FortiGate · SentinelOne (EDR) · PRTG · PowerShell Automation  
MCO · Incidents P1/P2 · Migrations · Déploiements MDT/WDS

<!-- Décommenter après création du profil LinkedIn
[![LinkedIn](https://img.shields.io/badge/LinkedIn-AmineBerrrada-0077B5?style=flat-square&logo=linkedin)](https://www.linkedin.com/in/amine-berrada-infra/)
-->

---

## 📜 Licence

MIT License — Utilisation libre en environnement professionnel.

---

<div align="center">

**ESN-Toolkit v3.0.0** — 20 fichiers · 7 749 lignes · 8 modules · 70+ tests

*Construit pour les techniciens et ingénieurs qui résolvent de vrais problèmes.*

</div>
>>>>>>> ec870e7 (feat: ESN-Toolkit v3.0.0)
