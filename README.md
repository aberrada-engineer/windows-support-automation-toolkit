<div align="center">

# 🖥️ ESN-Toolkit & AIOps Platform v3.6

### Autonomous Workstation, Infrastructure & Cloud Operations Platform

**Plateforme PowerShell enterprise d'auto-réparation (Self-Healing), astreinte 24/7 P1/P2, gouvernance COPIL,  
virtualisation (VMware / Nutanix), SecOps ANSSI, supervision PRTG, Linux et automatisation de 6 projets majeurs d'ingénierie.**

---

![Version](https://img.shields.io/badge/version-3.6.0-blue?style=flat-square)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B%20%7C%207%2B-5391FE?style=flat-square&logo=powershell&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Windows%2010%2F11%20%7C%20Server%202016--2022-0078D4?style=flat-square&logo=windows&logoColor=white)
![AIOps](https://img.shields.io/badge/AIOps-Self--Healing%20%26%20Predictive-brightgreen?style=flat-square)
![Security](https://img.shields.io/badge/Compliance-ANSSI%20%2F%20CIS%20Benchmark-red?style=flat-square)
![Code Size](https://img.shields.io/badge/Lines%20of%20Code-13%2C180%2B-purple?style=flat-square)
![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)
[![GitHub](https://img.shields.io/badge/GitHub-aberrada--engineer-181717?style=flat-square&logo=github)](https://github.com/aberrada-engineer/windows-support-automation-toolkit)
[![LinkedIn](https://img.shields.io/badge/LinkedIn-Amine%20BERRADA-0077B5?style=flat-square&logo=linkedin)](https://www.linkedin.com/in/amine-berrada-infra/)

---

[À propos](#-à-propos) •
[Architecture Modulaire](#-architecture-modulaire) •
[6 Projets Majeurs Déployés](#-6-projets-majeurs-déployés-en-production) •
[AIOps & Astreinte 24/7](#-aiops-astreinte-247--résilience) •
[Infrastructure, Linux & Supervision](#-infrastructure-hyperviseurs--cloud-hybride) •
[Interfaces GUI & Console](#-interfaces-graphique--console-interactive) •
[Roadmap](#-feuille-de-route-roadmap) •
[Auteur & Référent](#-auteur--référent-technique)

</div>

---

## 🎯 À propos

**ESN-Toolkit v3.6** est une plateforme d'ingénierie et d'automatisation des opérations informatiques (**AIOps**) conçue pour couvrir l'intégralité du spectre opérationnel d'une DSI ou d'une ESN :
du **support poste de travail (N1/N2)**, à **l'administration système et maintien en conditions opérationnelles (N2/N3)**, jusqu'au **pilotage de projets d'infrastructure critiques (N3 / Architecte)**.

Conçue sur le retour d'expérience de plus de **200 infrastructures multi-clients infogérées** et d'environnements critiques (notamment grands comptes horlogers et luxe genevois tels que *Porsche, TAG Heuer, Hublot*), cette boîte à outils garantit une autonomie opérationnelle maximale.

> ⚡ **100 % Natif Windows (PowerShell 5.1+ & 7+)** — **Zéro dépendance externe** requise — Exécutable immédiatement sur n'importe quel serveur ou poste de travail.

---

## 🏗️ Architecture Modulaire

La plateforme compte **plus de 13 180 lignes de code PowerShell & Batch**, structurées en 4 couches opérationnelles :

```
ESN-Toolkit/
│
├── 🚀 SETUP & INTERFACES UTILISATEUR
│   ├── Setup.bat                          # Installateur 1-clic autonome avec élévation de privilèges
│   ├── Install-ESNToolkit.ps1             # Déploiement silencieux vers C:\ESN-Toolkit, config execution policy & raccourcis
│   ├── Install-EnterpriseSilent.bat       # Script de déploiement de masse pour GPO / Intune Win32 App / SCCM
│   ├── ESN-GUI.ps1 & ESN-Launcher.bat     # Interface Graphique Windows Forms (6 onglets métiers, RichTextBox logs)
│   ├── ESN-Console.ps1 & ESN-Console.bat  # Console Interactive TUI avec 33 options d'administration directe
│   └── WebDashboard/ & Invoke-CentralDashboard.ps1 # Dashboard Web offline Datadog-style avec jauges SVG
│
├── 🤖 AIOPS, AUTO-GUÉRISON & ASTREINTE 24/7
│   ├── Invoke-SelfHealingService.ps1      # Gardien tâche de fond (15 min) : auto-repair services, purge disque, DNS
│   ├── Invoke-P1EmergencyTriage.ps1       # Boîte noire d'urgence P1/P2 : BSOD minidumps, crash events, Flash report
│   ├── Invoke-RansomwareShield.ps1        # KillSwitch d'isolement d'urgence, gel VSS et capture mémoire/forensics
│   ├── Invoke-PredictiveHealthAnalysis.ps1# Calcul prédictif d'épuisement de stockage C: et indicateur d'usure SSD
│   └── Invoke-DRTest.ps1                  # Simulation PRA/PCA mesurant RTO/RPO avec certificat SLA officiel
│
├── 🛠️ SUPPORT UTILISATEUR, FLOTTE & MIGRATION
│   ├── Invoke-ZeroTouchProvisioning.ps1   # Provisioning de poste neuf (renommage CLI-%SERIAL%, Winget, TPM BitLocker)
│   ├── Invoke-FullStationMigration.ps1    # Migration A à Z (Données, PST, Profils Wi-Fi avec clés, Mappages, Imprimantes)
│   ├── Invoke-FleetDiscovery.ps1          # Scan réseau multi-threadé /24 (Windows, Linux, Switchs, Imprimantes)
│   ├── Invoke-GLPIInventoryAgent.ps1      # Agent d'inventaire complet matériel/logiciel exportable en JSON/XML pour GLPI
│   └── Invoke-WSUSComplianceManager.ps1   # Audit conformité WSUS, détection hotfixes manquants et resynchronisation
│
├── 🏢 GOUVERNANCE, AUDIT INFRASTRUCTURE, LINUX & SUPERVISION
│   ├── Invoke-COPILReportGenerator.ps1    # Générateur de Rapport Mensuel Exécutif COPIL / COTECH (SLA 99.9%, MTTR)
│   ├── Invoke-DRPGenerator.ps1            # Générateur de Dossier Officiel de Plan de Reprise d'Activité (PRA / DRP)
│   ├── Invoke-PRTGSensorDeployer.ps1      # Déployeur de sondes PRTG Network Monitor avancées (XML/JSON Veeam/Disque/DHCP)
│   ├── Invoke-LinuxHeterogeneousAudit.ps1 # Audit à distance de serveurs Linux (Ubuntu/Debian) via SSH natif Windows
│   ├── Invoke-HypervisorAudit.ps1         # Audit VMware vSphere & Nutanix (Snapshots > 72h, saturation datastores)
│   ├── Invoke-ExchangeHealthCheck.ps1     # Audit Exchange Hybride/On-Premise, files d'attente et contrôle SPF/DKIM/DMARC
│   ├── Invoke-CoreServicesAudit.ps1       # Audit DHCP (saturation scopes), Scavenging DNS et certificats SSL expirant
│   ├── Invoke-CloudHybridAudit.ps1        # Audit Entra ID Connect, Intune MDM et Defender for Endpoint (Sense)
│   ├── Invoke-NetworkApplianceAudit.ps1   # Audit pare-feux FortiGate / Stormshield, tunnels VPN IPsec & sauvegardes conf
│   ├── Invoke-ADHygieneCheck.ps1          # Audit sécurité Active Directory (Comptes inactifs, Domain Admins, PasswordNeverExpires)
│   └── Invoke-InfrastructureSizing.ps1    # Dimensionnement cluster N+1, calcul rétention Veeam 3-2-1 et chiffrage COPIL
│
└── 💼 PROJETS MAJEURS D'INGÉNIERIE (DOSSIER RÉFÉRENT TECHNIQUE)
    ├── Projects/AD-Migration/             # Migration inter-domaines AD (SID History, ACLs NTFS, migration postes)
    ├── Projects/EDR-Deployment/           # Déploiement automatisé d'EDR SentinelOne sur +200 postes avec désinstallation legacy
    ├── Projects/Network-Aruba/            # Générateur de configuration ArubaOS-CX (VLANs, LACP uplinks, BPDU Guard, PRTG)
    ├── Projects/Windows-LAPS/             # Déploiement Windows LAPS, rotation 30j et remédiation Pass-the-Hash
    ├── Projects/Datacenter-Migration/     # Plan de bascule Datacenter et orchestration de failover planifié Veeam
    ├── Projects/MDT-Deployment/           # Industrialisation MDT/WDS (~200 Postes Texdecor, CustomSettings, Total Control drivers)
    └── Projects/WAN-MPLS-Refonte/         # Recette refonte WAN MPLS/SD-WAN et validation des flux de réplication intersites PRA
```

---

## 💼 6 Projets Majeurs Déployés en Production

Ces scripts reproduisent fidèlement les architectures et projets d'envergure menés par **Amine BERRADA** :

### 1. 🔄 Migration Inter-Domaines Active Directory
- **Dossier :** `Projects/AD-Migration/Invoke-ADDomainMigration.ps1`
- **Contexte :** Fusion et consolidation d'infrastructures d'entreprises sans interruption de service.
- **Capacités :**
  - Cartographie et extraction des utilisateurs, groupes de sécurité et ordinateurs du domaine source.
  - Préparation du mapping **SID History** pour préserver les accès aux ressources legacy.
  - Sauvegarde et réplication des listes de contrôle d'accès NTFS (**icacls**) sur les serveurs de fichiers.
  - Script de réassignation de profil local utilisateur pour le poste de travail migrated.

### 2. 🛡️ Déploiement Automatisé d'EDR / Antivirus (+200 Hôtes)
- **Dossier :** `Projects/EDR-Deployment/Invoke-EDRMassRollout.ps1`
- **Contexte :** Remplacement d'antivirus obsolètes par un EDR nouvelle génération (SentinelOne / Defender for Endpoint).
- **Capacités :**
  - Détection et désinstallation silencieuse des anciens antivirus tiers (McAfee, Kaspersky, Symantec, Trend Micro).
  - Validation des prérequis de communication réseau (Cloud Management Console HTTPS 443).
  - Installation silencieuse de l'agent EDR avec injection du **Site Token** d'enregistrement client.
  - Vérification de l'état de démarrage des services et génération de la matrice de conformité du parc.

### 3. 🔌 Déploiement & Configuration de Switchs Aruba (~20 Commutateurs)
- **Dossier :** `Projects/Network-Aruba/New-ArubaSwitchConfig.ps1`
- **Contexte :** Renouvellement et durcissement de l'infrastructure de commutation réseau d'entreprise.
- **Capacités :**
  - Génération automatisée des configurations **ArubaOS-CX** prêtes à être injectées par CLI ou TFTP.
  - Définition des VLANs (Data, Voice avec QoS CoS 5, Management isolé, Guest, DMZ).
  - Agrégation de liens haute disponibilité (**LACP Trunk** uplinks vers le cœur de réseau).
  - Durcissement de sécurité : **Port-Security**, **BPDU-Guard**, **DHCP Snooping**, isolation du Management.
  - Déclaration de l'agent SNMPv3 pour intégration immédiate dans la supervision **PRTG**.

### 4. 🔐 Déploiement Windows LAPS & Durcissement Post-Audit
- **Dossier :** `Projects/Windows-LAPS/Deploy-WindowsLAPS.ps1`
- **Contexte :** Remédiation post-audit de sécurité pour éradiquer les attaques par rebond (**Pass-the-Hash**).
- **Capacités :**
  - Extension du schéma Active Directory pour les attributs LAPS (`ms-Mcs-AdmPwd`).
  - Déploiement de la stratégie GPO / Registre : mot de passe administrateur local unique de 16 caractères complexes.
  - Rotation automatique tous les 30 jours et délégation stricte des droits de lecture aux seuls administrateurs habilités.
  - Audit d'expiration des mots de passe sur l'ensemble des machines de l'annuaire.

### 5. 🏢 Bascule Planifiée de Datacenter & Orchestration Veeam PRA
- **Dossier :** `Projects/Datacenter-Migration/Invoke-VeeamFailoverPlan.ps1`
- **Contexte :** Déménagement d'infrastructures d'hébergement critiques vers un nouveau Datacenter.
- **Capacités :**
  - Synchronisation finale des points de restauration par réplication inter-sites Veeam Backup & Replication.
  - Arrêt propre et ordonné des machines virtuelles sources sur le cluster d'origine.
  - Basculement automatisé (**Planned Failover**) des VMs critiques (Contrôleurs de domaine, SQL, ERP, File Servers).
  - Re-IPing automatique des interfaces réseaux et validation de la connectivité post-bascule.

### 6. 🖥️ Industrialisation MDT / WDS (~200 Postes Déployés)
- **Dossier :** `Projects/MDT-Deployment/Invoke-MDTIndustrialization.ps1`
- **Contexte :** Migration industrielle de ~200 postes (Windows 7 vers 10/11) pour Texdecor Group.
- **Capacités :**
  - Structuration de l'arborescence des pilotes par constructeur (**Total Control** : Dell, HP, Lenovo).
  - Génération des fichiers `CustomSettings.ini` et `Bootstrap.ini` pour un déploiement Zero-Touch.
  - Nommage automatisé selon le numéro de série constructeur (`CLI-%SERIAL%`).
  - Injection des scripts post-installation : purge bloatware, chiffrement BitLocker XTS-256 et intégration LAPS.

### 7. 🌐 Refonte WAN Multi-Sites (MPLS / SD-WAN) & PRA Intersites
- **Dossier :** `Projects/WAN-MPLS-Refonte/Invoke-WANMigrationPlan.ps1`
- **Contexte :** Migration WAN inter-sites, bascule opérateur et sécurisation de la bande passante de réplication Veeam.
- **Capacités :**
  - Audit **MTU Path Discovery** (contrôle du bit DF Don't Fragment pour éliminer le black-holing ICMP).
  - Mesure de la latence moyenne, gigue et taux de perte de paquets vers les sites distants (SLA opérateur).
  - Validation de la connectivité sur le port de réplication Veeam WAN Accelerator (Port 6162).
  - Édition d'un **Procès-Verbal de Recette Opérateur** en HTML.

---

## 🤖 AIOps, Astreinte 24/7 & Résilience

| Module | Fonctionnement | Valeur Métier |
|---|---|---|
| **Invoke-SelfHealingService.ps1** | Exécuté toutes les 15 min via le Planificateur de tâches. Vérifie les services critiques (Spooler, Windows Update, DNS, Defender), purge le disque C: dès 85% d'occupation et réinitialise le DNS si Internet tombe. | **Résout 80% des tickets N1 sans intervention humaine.** |
| **Invoke-P1EmergencyTriage.ps1** | Boîte noire d'urgence pour astreinte P1/P2. Extrait les derniers Minidumps BSOD (`C:\Windows\Minidump`), les 50 derniers événements d'erreurs, l'état SMART et produit un rapport d'incident Flash en moins de 30 secondes. | **Respect strict de la GTR / GTI lors d'incidents critiques P1.** |
| **Invoke-RansomwareShield.ps1** | KillSwitch d'isolement d'urgence. Coupe immédiatement toutes les interfaces réseau, bloque les ports SMB/RDP, protège les clichés instantanés VSS et exporte la liste des processus suspects et connexions actives (`netstat`). | **Endiguement immédiat d'une attaque par ransomware.** |
| **Invoke-PredictiveHealthAnalysis.ps1** | Régression linéaire mathématique sur l'historique d'écriture disque pour prédire le jour exact de saturation du disque C:, analyse l'usure SSD (TBW) et génère une analyse de cause racine (RCA) pré-rédigée pour le ticket. | **Prévention proactive des pannes avant impact utilisateur.** |
| **Invoke-DRTest.ps1** | Simulation d'interruption totale de production. Calcule le RPO réel et le RTO estimé, audite l'immutabilité WORM des sauvegardes Veeam et délivre un Certificat officiel de PRA/PCA pour les audits de certification. | **Garantie de continuité d'activité pour les comités de direction.** |

---

## 🏢 Infrastructure, Hyperviseurs & Cloud Hybride

### 🖥️ Clusters de Virtualisation (VMware vSphere & Nutanix)
- **Script :** `Invoke-HypervisorAudit.ps1`
- Analyse de la santé des hôtes ESXi et des nœuds Nutanix AOS/AHV.
- Détection des **snapshots obsolètes (> 72h)** responsables de dégradation majeure des I/O de stockage.
- Alerte sur la surallocation de CPU/vRAM et le seuil de saturation des Datastores VMFS/NFS.

### ✉️ Messagerie Exchange Hybride & Flux SMTP
- **Script :** `Invoke-ExchangeHealthCheck.ps1`
- Contrôle de l'état des services de transport et des files d'attente (**Mail Queues**).
- Détection du phénomène de **Backpressure** (saturation ressource disque/mémoire bloquant l'émission des emails).
- Validation de la délivrabilité et de la sécurité des domaines : contrôle des enregistrements **MX, SPF, DKIM et DMARC**.

### 🌐 Services Cœur de Réseau (Core Services)
- **Script :** `Invoke-CoreServicesAudit.ps1`
- Audit des étendues DHCP : alerte immédiate en cas de saturation de scope (> 85% d'adresses allouées).
- Détection des enregistrements DNS fantômes et validation du scavenging automatique.
- Inventaire des certificats SSL/TLS machine et alerte sur les certificats expirant à moins de 30 jours.

### 📑 Gouvernance COPIL / COTECH Mensuel
- **Script :** `Invoke-COPILReportGenerator.ps1`
- Conçu spécifiquement pour les réunions de gouvernance d'infogérance haut de gamme.
- Calcul en temps réel du taux de disponibilité globale (objectif contractuel **SLA 99.9%**).
- Répartition des tickets par sévérité (**P1 Bloquant, P2 Majeur, P3/P4 Demandes**) et calcul du MTTR.
- Production d'un livrable exécutif HTML intégrant les arbitrages de capacité et les recommandations d'architecture.

---

## 🖥️ Interfaces Graphique & Console Interactive

### 1. Interface Graphique (GUI) — `ESN-GUI.ps1`
Accessible via le lanceur `ESN-Launcher.bat` ou l'exécutable déployé sur le bureau :
- **Onglet 1 : Diagnostics & Auto-Fix** (Audit de santé, remédiation automatique, mode simulation, export ZIP incident).
- **Onglet 2 : Support N1/N2 & Caches** (Spooler, DNS, caches M365 Teams/Outlook/OneDrive, Windows Update, agent GLPI).
- **Onglet 3 : Infra, AD & Serveurs** (Active Directory, VMware/Nutanix, Exchange, DHCP/DNS/PKI, Entra ID, Veeam).
- **Onglet 4 : Migration Poste A à Z** (Sauvegarde complète de profil, restauration en 1-clic, rapports).
- **Onglet 5 : AIOps & SecOps** (Gardien Self-Healing, Zero-Touch Provisioning, durcissement ANSSI, Triage P1, KillSwitch).
- **Onglet 6 : Projets Référents & COPIL** (Boutons d'exécution directe pour les 6 projets majeurs et le rapport exécutif SLA 99.9%).

### 2. Console Interactive (TUI) — `ESN-Console.ps1`
Idéale en session PowerShell distante, PowerShell Direct ou RDP à faible débit :
- **29 options numérotées** couvrant toutes les fonctionnalités d'un simple chiffre.
- Sous-menu dédié `[26]` pour exécuter, auditer ou simuler les 6 projets majeurs.

---

## 🚀 Démarrage Rapide

### Option A : Installation en 1 clic (Recommandée)
Exécutez simplement `Setup.bat` en tant qu'administrateur :
```cmd
Setup.bat
```
Le script configure l'environnement, crée le répertoire `C:\ESN-Toolkit`, place les raccourcis sur le bureau et lance l'interface graphique.

### Option B : Déploiement Silencieux en Masse (GPO / Intune / SCCM)
```cmd
Install-EnterpriseSilent.bat
```

### Option C : Lancement direct sans installation
```powershell
# Lancer l'interface graphique
powershell.exe -ExecutionPolicy Bypass -File .\ESN-GUI.ps1

# Lancer la console interactive
powershell.exe -ExecutionPolicy Bypass -File .\ESN-Console.ps1

# Lancer l'analyse et l'auto-réparation en ligne de commande
powershell.exe -ExecutionPolicy Bypass -File .\Invoke-IncidentAnalysis.ps1 -AutoFix -OpenReport
```

---

## 👤 Auteur & Référent Technique

**Amine BERRADA**  
*Administrateur Systèmes et Réseaux Confirmé • Référent Technique N3*  
Spécialiste MCO, Cloud Hybride, Virtualisation & Cybersécurité  
Genève (Suisse) · Paris (Île-de-France) · Lille (Hauts-de-France)

- **Email :** [berradapro@outlook.com](mailto:berradapro@outlook.com)
- **LinkedIn :** [linkedin.com/in/amine-berrada-infra](https://www.linkedin.com/in/amine-berrada-infra/)
- **GitHub :** [github.com/aberrada-engineer](https://github.com/aberrada-engineer)

---

## 📜 Licence

Ce projet est sous licence MIT — Utilisation libre pour les professionnels de l'informatique, les ESN et les DSI.
