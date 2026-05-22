# Changelog — ESN-Toolkit

Toutes les modifications notables sont documentées ici.
Format : [Version] — Date — Description

---

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
