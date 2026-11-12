# 🗺️ FEUILLE DE ROUTE STRATÉGIQUE (ROADMAP) — ESN-TOOLKIT & AIOPS PLATFORM

> **Vision :** Transformer l'administration de systèmes et réseaux en une plateforme d'opérations autonomes (AIOps), résiliente, modulaire et 100% native Windows, capable d'éliminer les interventions manuelles répétitives et d'orchestrer la haute disponibilité des infrastructures critiques.

---

## 📌 Jalons Réalisés (Versions Précédentes)

### ✅ v1.0.0 — Socle Diagnostic N1/N2
- Diagnostic multi-domaines (Réseau, Système, Stockage, Sécurité, Services).
- Calcul du score de santé pondéré 0-100.
- Rapport HTML offline autonome avec graphes SVG.

### ✅ v2.0.0 — Auto-Remédiation & Support M365
- Moteur d'auto-réparation sur 8 scénarios d'incidents fréquents (Spooler, DNS, Winsock, Teams, Outlook, OneDrive, Temp, Windows Update).
- Mode simulation sans altération système.
- Module de packaging et export ZIP d'incident pour ticketing (Jira, GLPI, ServiceNow).

### ✅ v3.0.0 — Architecture Modulaire & Interface Graphique
- Refonte en architecture modulaire PowerShell (`Modules/`).
- Interface graphique officielle Windows Forms (`ESN-GUI.ps1`).
- Console interactive TUI avec menus rapides (`ESN-Console.ps1`).
- Assistant de migration complète de poste utilisateur (`Invoke-FullStationMigration.ps1`).

### ✅ v3.5.0 — Enterprise, SecOps ANSSI & 6 Projets Référents (Version Actuelle)
- **AIOps & Astreinte 24/7 :** Gardien d'auto-guérison en tâche de fond (`Invoke-SelfHealingService.ps1`), Triage d'urgence P1 (`Invoke-P1EmergencyTriage.ps1`), KillSwitch Ransomware (`Invoke-RansomwareShield.ps1`), Analyse Prédictive de saturation disque et usure SSD (`Invoke-PredictiveHealthAnalysis.ps1`).
- **Gouvernance & MCO :** Générateur de rapport exécutif mensuel COPIL / COTECH (`Invoke-COPILReportGenerator.ps1`), Simulation PRA/PCA avec certificat SLA (`Invoke-DRTest.ps1`), Sizing de cluster N+1 et stockage Veeam (`Invoke-InfrastructureSizing.ps1`).
- **Playbooks des 6 Projets Référents :** Migration AD inter-domaines avec SID History, Déploiement EDR SentinelOne sur +200 postes, Déploiement de ~20 switches Aruba CX, Windows LAPS anti Pass-the-Hash, Bascule Datacenter Veeam, Déploiement industriel MDT/WDS 200+ postes Texdecor, Refonte WAN multi-sites MPLS & PRA.
- **Audit Cœur de Réseau & Hyperviseurs :** VMware vSphere & Nutanix, Exchange Hybride & flux SMTP, DHCP Scopes, DNS Scavenging, PKI SSL, Agent GLPI / OCS Inventory.

---

## 🚀 Prochaines Évolutions (v4.0.0 — Q1/Q2 2027)

### 1. 🤖 Intelligence Opérationnelle & AIOps Avancé
- [ ] **Détection d'anomalies par Machine Learning local :** Intégration d'un algorithme de détection de dérive comportementale (CPU/RAM/I-O) basé sur l'écart-type mobile sans dépendance cloud.
- [ ] **Remédiation adaptative contextuelle :** Ajustement dynamique des seuils d'alerte selon les plages horaires d'ouverture des entreprises clientes (8h-19h vs Nuit/Weekend).
- [ ] **Auto-remédiation de profils corrompus :** Réparation automatisée de la ruche `NTUSER.DAT` corrompue et recréation propre de profil avec conservation des données.

### 2. 🌐 Supervision & Intégration Écosystème IT
- [ ] **Sondes PRTG Personnalisées (Advanced Custom Sensors) :** Déploiement automatique de sondes PowerShell retournant du JSON/XML natif pour PRTG Network Monitor (supervision des jobs Veeam, scopes DHCP, snapshots VMware).
- [ ] **Webhooks Bidirectionnels :** Envoi d'alertes enrichies avec boutons d'action (Interactive Adaptive Cards) vers Microsoft Teams, Slack et Discord.
- [ ] **Connecteur REST API GLPI / ServiceNow :** Création, enrichissement et clôture automatique des tickets d'incidents directement depuis le toolkit.

### 3. 🛡️ Cybersécurité & Conformité NIS 2 / ISO 27001
- [ ] **Audit de conformité directive européenne NIS 2 :** Matrice d'évaluation automatique des 10 exigences minimales de sécurité des systèmes d'information critiques.
- [ ] **Zero-Trust Network Access (ZTNA) Readiness :** Contrôle de posture pour l'accès conditionnel Entra ID (conformité TPM 2.0, SecureBoot, EDR actif, patch level).
- [ ] **Détecteur d'anomalies de privilèges AD :** Traque en temps réel des élévations de privilèges suspectes dans les groupes *Domain Admins*, *Schema Admins* et *Account Operators*.

---

## 🔮 Vision Long Terme (v5.0.0 — Q3/Q4 2027)

### 1. 🖥️ Orchestration Multi-Hôtes & Flotte Distante
- [ ] **Exécution distribuée via PowerShell Remoting (WinRM / OpenSSH) :** Capacité de piloter l'auto-réparation ou le durcissement sur 500+ machines en simultané avec régulation de bande passante.
- [ ] **Sidecar Agent pour postes nomades :** Micro-service léger garantissant la conformité de sécurité même hors VPN d'entreprise.

### 2. 🐧 Gestion Hybride Windows & Linux
- [ ] **Module d'audit et remédiation Linux unifié :** Prise en charge transparente des serveurs Linux Debian / Ubuntu (services systemd, sécurité SSH, paquets APT, partages Samba/NFS).

---

## 📊 Matrice d'Avancement des Modules

| Module / Capacité | Statut | Cible Version | Responsable |
| :--- | :---: | :---: | :--- |
| Diagnostics & Auto-Fix N1/N2 | **Livré** | v1.0 / v2.0 | Amine BERRADA |
| Migration de Postes A à Z | **Livré** | v3.0 | Amine BERRADA |
| Interface Graphique & Console TUI | **Livré** | v3.0 | Amine BERRADA |
| Gardien Self-Healing & Astreinte 24/7 | **Livré** | v3.5 | Amine BERRADA |
| Durcissement ANSSI & Sécurité | **Livré** | v3.5 | Amine BERRADA |
| 6 Projets Majeurs (AD, EDR, Aruba, LAPS, Veeam, MDT, WAN) | **Livré** | v3.5 | Amine BERRADA |
| Hyperviseurs (VMware / Nutanix) & Exchange | **Livré** | v3.5 | Amine BERRADA |
| Gouvernance COPIL / COTECH (SLA 99.9%) | **Livré** | v3.5 | Amine BERRADA |
| Sondes PRTG Avancées | *En cours* | v3.6 | Amine BERRADA |
| Audit de Parc Hétérogène Linux (SSH) | *En cours* | v3.6 | Amine BERRADA |
| Générateur de Plan de Reprise d'Activité (DRP) | *En cours* | v3.6 | Amine BERRADA |
| Connecteur REST API GLPI / ServiceNow | *Prévu* | v4.0 | Amine BERRADA |
