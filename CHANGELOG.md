# Changelog — ESN-Toolkit

Toutes les modifications notables sont documentées ici.
Format : [Version] — Date — Description

---

## [3.9.0] — 2026-11-14 — Portabilité Enterprise, Hygiène SecOps & CI Étendue

### Correctifs & Durcissement
- **Portabilité des chemins (`Core/ESN-Core.psm1`, `Core/ESN-OutputSchema.ps1`)** : Introduction de `Get-ESNToolkitRoot` (variable d'environnement `ESN_TOOLKIT_ROOT`, sinon `%SystemDrive%\ESN-Toolkit`, sinon dossier temporaire) et suppression des chemins `C:\ESN-Toolkit` codés en dur dans les modules, orchestrateurs, console TUI, GUI et playbooks `Projects/`.
- **Sécurité & Réseau (`Projects/Network-Aruba/New-ArubaSwitchConfig.ps1`, `Projects/EDR-Deployment/Invoke-EDRMassRollout.ps1`, `Core/IncidentPatterns.json`)** : Passage à **SNMPv3 (`authPriv` SHA/AES)** par défaut (zéro secret/communauté en clair), lecture du Site Token EDR via `ESN_EDR_SITE_TOKEN`, et suppression des exemples `-AsPlainText` dans la base `IncidentPatterns.json`.
- **Fiabilité Console TUI (`ESN-Console.ps1`)** : Correction des paramètres d'appel du sous-menu `[26]` (`-Simulation`, `-AuditOnly`, etc.) selon les signatures réelles de chaque playbook.
- **Tests Pester & CI (`.github/scripts/Invoke-QualityGate.ps1`, `Tests/`)** : Activation de l'ensemble des 5 suites Pester + règle `PSScriptAnalyzer` étendue (`Error` & `Warning`), ajout de tests unitaires avec `Mock` sur les branches live (`Invoke-NutanixPrismHealthAI.ps1`, `Invoke-ActiveDirectoryThreatHunter.ps1`) et validation SNMPv3.
- **Cohérence Documentaire** : Alignement `v3.9` et `7 Projets Majeurs` (ajout explicite du Projet 7 WAN MPLS / PRA dans `Docs/DOSSIER-TECHNIQUE-ENTRETIEN.md`, `index.html`, `Presentation/index.html`, `WebDashboard/index.html`, `README.md`, `ROADMAP.md`) et masquage du numéro de téléphone personnel dans les supports publics.

## [3.8.0] — 2026-11-12 — Dossier d'Ingénierie, Pitch Deck Interactif, Compendium REX & Live Demo

### Nouveautés & Livrables Recruteurs
- **Dossier Technique d'Entretien (`Docs/DOSSIER-TECHNIQUE-ENTRETIEN.md`)** : Guide complet de soutenance technique des projets, vision d'ingénierie et argumentaire d'architecture (AD FSMO, Veeam immuable 3-2-1, Nutanix/VMware, SecOps ANSSI).
- **Pitch Deck de Présentation Technique (`Presentation/index.html`)** : Présentation interactive moderne en 5 slides dark mode prête à être partagée en visioconférence d'embauche (Teams / Google Meet / Zoom).
- **Le Livre Noir des Incidents (`Docs/INCIDENT-LOGBOOK.md`)** : Compendium de 8 études de cas réels d'incidents critiques P1/P2 résolus en production (snapshots VMware, Ransomware, boucle réseau, USN Rollback AD, Backpressure Exchange).
- **Schémas d'Architecture Système & Réseau (`Docs/ARCHITECTURE-SCHEMAS.md`)** : Diagrammes Mermaid documentant la topologie multi-sites WAN MPLS, les clusters N+1 et les flux de réplication intersites PRA.
- **Simulateur d'Incidents Live Demo (`Invoke-IncidentLabSimulator.ps1`)** : Moteur de simulation contrôlée permettant d'effectuer une démonstration d'auto-remédiation en direct devant un jury technique (scénarios N1, P1 et SecOps).
- **Console v3.8 & GUI v3.8** : Intégration des boutons et options directes pour piloter le simulateur et lancer le pitch deck.

---

## [3.7.0] — 2026-11-12 — Posture Zero-Trust, Intégration ITSM REST & Runbook d'Astreinte 24/7

### Nouveautés Majeures
- **Audit de Posture Zero-Trust (`Invoke-ZeroTrustAudit.ps1`)** : Contrôle de conformité TPM 2.0, SecureBoot, Virtualization-Based Security (VBS), Credential Guard / LSA PPL et enrôlement Microsoft Entra ID avec score sur 100.
- **Connecteur d'Intégration ITSM (`Invoke-ITSMConnector.ps1`)** : Dispatching d'alertes enrichies (Adaptive Cards) vers Microsoft Teams et création automatique de tickets d'incidents via les API REST de GLPI (`/apirest.php/Ticket`) et ServiceNow.
- **Runbook d'Astreinte 24/7 (`Docs/RUNBOOK-ONCALL-P1-P2.md`)** : Manuel de référence pour le traitement des urgences P1/P2 (GTI < 15 min, GTR < 4h), arbre de décision et modèles de communication de crise.
- **Pipeline d'Intégration Continue (`.github/workflows/ci.yml`)** : Workflow GitHub Actions validant la conformité syntaxique (AST Parser) et exécutant la suite de tests Pester.

---

## [3.6.0] — 2026-11-12 — Supervision PRTG, Parcs Linux SSH, WSUS & Dossier PRA / DRP

### Nouveautés Majeures
- **Générateur & Déployeur de Sondes PRTG (`Invoke-PRTGSensorDeployer.ps1`)** : Déploiement automatique de sondes XML/JSON avancées pour superviser les jobs Veeam, la saturation des datastores, les scopes DHCP et l'expiration des certificats SSL/TLS.
- **Audit de Serveurs Linux Distants (`Invoke-LinuxHeterogeneousAudit.ps1`)** : Connexion SSH native sans outil tiers pour auditer la santé des serveurs Ubuntu / Debian (systemd, stockage, durcissement SSH, mises à jour APT, partages Samba/NFS).
- **Audit de Conformité WSUS (`Invoke-WSUSComplianceManager.ps1`)** : Contrôle de la politique GPO du client Windows Update, détection des redémarrages en attente et forçage de détection.
- **Générateur de Dossier Officiel PRA / DRP (`Invoke-DRPGenerator.ps1`)** : Livrable complet conforme ISO 22301 & ANSSI intégrant l'annuaire de crise, la matrice RTO/RPO et le runbook séquentiel de bascule.
- **Suite de Tests Pester Enterprise (`Tests/ESN-EnterpriseModules.Tests.ps1`)** : Validation de l'intégrité syntaxique et structurelle de tous les scripts.

---

## [3.5.0] — 2026-11-12 — Playbooks des 6 Projets Majeurs, Hyperviseurs & COPIL

### Nouveautés Majeures
- **Playbooks Projets (`Projects/`)** : Migration inter-domaines AD, Rollout massif EDR SentinelOne (+200 hôtes), Commutation ArubaOS-CX, Windows LAPS anti Pass-the-Hash, Bascule Datacenter Veeam, Industrialisation MDT/WDS (200 postes Texdecor), Refonte WAN multi-sites MPLS & PRA.
- **Audit Hyperviseurs & Virtualisation (`Invoke-HypervisorAudit.ps1`)** : Santé des clusters VMware vSphere & Nutanix, traque des snapshots obsolètes (> 72h).
- **Audit Exchange & Flux SMTP (`Invoke-ExchangeHealthCheck.ps1`)** : Contrôle du Backpressure, des files d'attente et des protocoles SPF, DKIM et DMARC.
- **Services Cœur de Réseau (`Invoke-CoreServicesAudit.ps1`)** : Saturation DHCP, Scavenging DNS et certificats SSL.
- **Gouvernance COPIL / COTECH (`Invoke-COPILReportGenerator.ps1`)** : Rapport mensuel exécutif avec cadran SLA 99.9% et métriques MTTR.
- **Inventaire GLPI / OCS (`Invoke-GLPIInventoryAgent.ps1`)** : Générateur d'inventaire matériel et logiciel JSON/XML.

## [3.0.0] — 2025-05-15 — Phase Industrialisation & Cohérence Globale

### Objectifs atteints
Phase d'industrialisation sans refonte architecture.
5 patches ciblés ajoutés au repository existant.

### PATCH 1 — ESN-OutputSchema.ps1 (nouveau)
- Schéma JSON unifié pour tous les modules (gravité : OK / WARNING / CRITICAL / INFO)
- Fonction `New-ESNCheck` : objet check standardisé avec id, domain, severity, score_impact, remediation
- Fonction `New-ESNDomainResult` : agrégation checks → score de domaine
- Fonction `Export-ESNResultJson` : export JSON standardisé avec metadata incident
- Fonction `ConvertTo-ESNCheck` : rétro-compatibilité anciens résultats ESN-Core
- Compteurs d'IDs auto par domaine (NET-001, SYS-002, SEC-003...)

### PATCH 2 — IncidentPatterns.json (nouveau)
- Base de connaissances incidents : 20 patterns statiques
- Domaines couverts : Network, System, Security, Storage, Services, AD, Outlook, Migration, VPN, Windows Update
- Format : symptom → keywords → severity → likely_cause → remediation_steps → powershell_fix
- Utilisé par ESN-ReportBuilder pour détection automatique et affichage contextuel
- Zéro IA, zéro NLP — mapping statique par mots-clés

### PATCH 3 — ESN-ReportBuilder.ps1 (nouveau)
- Rapport HTML offline complet (CSS inline uniquement, zéro dépendance externe)
- Score global + jauges SVG par domaine (Réseau / Système / Sécurité / Stockage / Services)
- Résumé exécutif avec verdict coloré
- Machine info (OS, RAM, CPU, uptime, domaine, opérateur)
- Erreurs et recommandations actionnables
- Impacts détaillés sur le score avec traçabilité
- Remédiations exécutées (avant/après)
- Base de connaissances : patterns d'incidents détectés automatiquement
- Sections pliables (HTML/CSS pur, sans JavaScript obligatoire)
- Export JSON intégré au rapport
- Fonction : `Build-ESNReport`

### PATCH 4 — ESN-Migration.psm1 v2 (remplacement complet)
- Score de réussite migration 0–100 (`_MIG-MigrationScore`)
- Manifest JSON v2.0 enrichi : stats par module (fichiers, Mo, delta source/dest)
- Comparaison avant/après robuste sur chaque dossier avec `_MIG-FolderStats`
- Détection automatique d'anomalies (fichiers manquants, dossiers absents, OST/PST introuvables)
- Phase validation post-restauration automatique
- Rapport HTML migration intégré (`_MIG-HtmlReport`)
- `PostMigrationActions` listées dans manifest et rapport
- Rétro-compatible : signatures de fonctions identiques (Invoke-UserStateCapture / Invoke-UserStateRestore)

### PATCH 5 — Invoke-IncidentAnalysis.ps1 v3 (remplacement complet)
- Intégration native des 4 patches précédents
- Chargement conditionnel ESN-OutputSchema et ESN-ReportBuilder (non-bloquant si absent)
- Export JSON standardisé (schema v1.0) avec scores par domaine, checks unifiés, remédiations
- Rapport HTML via Build-ESNReport (ReportBuilder) avec fallback ESN-Core si KO
- IncidentPatterns transmis au ReportBuilder pour détection contextuelle
- Injection scores HealthScore dans session ESN-Core avec traçabilité impacts
- Retour objet enrichi : ScoreNetwork, ScoreSystem, ScoreSecurity, ScoreStorage, ScoreServices, JsonPath

### Métriques v3.0
- 20 fichiers — 7 692 lignes de code
- 20 patterns d'incidents dans la base de connaissances
- 5 domaines de scoring pondérés (total poids = 100%)
- Contraintes respectées : PowerShell 5.1, Windows 10/11, zéro dépendance externe

---

## [2.0.0] — 2025-05-15 — Auto-Remédiation

### Ajouté
- **Module ESN-Remediation** — 8 remédiations : DNS, Winsock, Services, Teams, Outlook, OneDrive, TempFiles, WindowsUpdate
- **ESN-HealthScore.psm1** — scoring pondéré 5 domaines avec jauges SVG
- **Tests Pester** — ESN-Remediation.Tests.ps1 (20+ tests), ESN-HealthScore.Tests.ps1 (50+ tests)
- **Invoke-IncidentAnalysis v2** — intégration Remediation + HealthScore

---

## [1.0.0] — 2025-05-15 — Version initiale

### Ajouté
- Core Framework (ESN-Core.psm1) : logging, rapport HTML, ZIP incident
- Modules : ESN-Network, ESN-Windows, ESN-AD, ESN-M365, ESN-Migration
- Invoke-IncidentAnalysis.ps1, Invoke-Migration.ps1
- Tests Pester v5 (ESN-Toolkit.Tests.ps1)
- CI GitHub Actions (PSScriptAnalyzer + Pester)

---

## Roadmap

### [3.1.0] — Prévu
- [ ] Tests Pester pour ESN-OutputSchema et ESN-ReportBuilder
- [ ] Module ESN-FortiGate (diagnostic VPN, logs SSH)
- [ ] Module ESN-Veeam (statut jobs, alertes backup)
- [ ] Alerte Teams webhook dans ESN-Remediation
- [ ] Remédiation : reset profil Teams v2 (MSIX)

### [4.0.0] — Prévu
- [ ] Dashboard HTML temps réel multi-serveurs
- [ ] Module PRTG integration (API REST)
- [ ] Runbook interactif P1/P2 guidé
- [ ] Support PowerShell 7 (ForEach-Object -Parallel)
