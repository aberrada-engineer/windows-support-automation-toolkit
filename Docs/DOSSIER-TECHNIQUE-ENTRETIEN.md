# 💼 DOSSIER TECHNIQUE D'INGÉNIERIE & PRÉSENTATION D'ENTRETIEN

<p align="center">
  <img src="../Assets/photo_amine_officielle.jpg" width="130" style="border-radius: 50%; border: 3px solid #2C5282;" alt="Amine Berrada - Administrateur Systèmes & Réseaux Confirmé">
</p>

> **Candidat : Amine BERRADA**  
> *Administrateur Systèmes et Réseaux Confirmé • Référent Technique N3*  
> Spécialiste MCO, Cloud Hybride, Virtualisation & Cybersécurité  
> Genève · Paris · Lille • [LinkedIn](https://www.linkedin.com/in/amine-berrada-infra/) • [GitHub](https://github.com/aberrada-engineer)

---

## 🎯 1. Philosophie d'Ingénierie & Vision Opérationnelle

> *"Un bon administrateur résout les pannes. Un excellent administrateur conçoit des architectures qui s'auto-réparent et élimine les tâches répétitives pour se concentrer sur la valeur ajoutée et la résilience."*

Ce repository **n'est pas une simple collection de scripts** : c'est la concrétisation en code de plus de **5 ans d'expérience sur plus de 200 infrastructures multi-clients**, en environnement ESN exigeant et pour des comptes prestigieux (marques de luxe et horlogerie genevoise telles que **Porsche, TAG Heuer, Hublot**).

### Les 4 Piliers de ma Démarche Technique :
1. **Zéro Dépendance Externe :** Tout le code développé ici est **100% natif Windows (PowerShell 5.1+ / 7+)**. Il fonctionne immédiatement sur n'importe quel poste ou serveur en production, sans nécessiter l'installation de modules tiers ou de droits Internet.
2. **Industrialisation & Idempotence :** Chaque script peut être exécuté plusieurs fois sans risque d'effet de bord (mode `-WhatIf`, `-Simulation` ou `-ReportOnly`).
3. **Traçabilité & Livrables C-Level :** Chaque action produit un livrable exécutif (HTML interactif dark mode, logs horodatés, archives ZIP d'incidents) prêt pour les comités de pilotage (**COPIL / COTECH**).
4. **Sécurité par Défaut (Zero-Trust) :** Respect des recommandations **ANSSI**, chiffrement **BitLocker XTS-256**, **Windows LAPS**, isolation **VBS/Credential Guard** et dépôts immuables **Veeam WORM**.

---

## 🏗️ 2. Soutenance des 6 Projets Majeurs Réalisés

```
┌───────────────────────────────────────────────────────────────────────────┐
│                      CARTOGRAPHIE DES PROJETS CLÉS                        │
├───────────────────────────────┬───────────────────────────────────────────┤
│ PROJET 1 : AD Migration       │ Migration inter-domaines, SID History, ACL│
│ PROJET 2 : EDR SentinelOne    │ Déploiement massif +200 hôtes, tokens     │
│ PROJET 3 : Réseau Aruba CX    │ Commutation d'entreprise, LACP, VLANs     │
│ PROJET 4 : Windows LAPS       │ Remédiation post-audit anti Pass-the-Hash │
│ PROJET 5 : Bascule Datacenter │ Orchestration PRA Veeam Failover Plan     │
│ PROJET 6 : Master MDT/WDS     │ Industrialisation 200+ postes (Texdecor)  │
│ PROJET 7 : WAN MPLS & PRA     │ Recette QoS CoS/DSCP, réplication WAN     │
└───────────────────────────────┴───────────────────────────────────────────┘
```

### Projet 1 : Migration Inter-Domaines Active Directory (En Autonomie)
- **Défi :** Fusionner deux domaines Active Directory historiques suite à un rachat d'entreprise, sans interruption des utilisateurs ni perte d'accès aux partages de fichiers.
- **Solution Technique Implémentée :**
  - Établissement d'une relation d'approbation bidirectionnelle transitive entre forêts.
  - Extraction et réplication des comptes avec préservation du **SID History** (`sIDHistory`) pour maintenir les accès aux ACL NTFS du domaine source.
  - Script de sauvegarde et translation des permissions NTFS via `icacls` (`/save` et `/restore`).
  - Bascule des postes de travail via script de translation de profil local (préservation du bureau, registre et certificats).
- **Preuve dans le Repo :** `Projects/AD-Migration/Invoke-ADDomainMigration.ps1`

### Projet 2 : Déploiement Automatisé d'EDR sur +200 Hôtes (En Autonomie)
- **Défi :** Remplacement d'une solution antivirus obsolète et hétérogène (McAfee, Symantec) par SentinelOne sur 200+ serveurs et postes distants.
- **Solution Technique Implémentée :**
  - Script d'audit pré-déploiement validant la connectivité cloud HTTPS 443 et l'espace disque.
  - Désinstallation propre et silencieuse des legacy agents avec nettoyage des pilotes de filtre kernel.
  - Déploiement industrialisé par GPO ordinateur avec injection dynamique du `Site Token` client.
  - Vérification de l'état de démarrage des services et génération de la matrice de couverture 100%.
- **Preuve dans le Repo :** `Projects/EDR-Deployment/Invoke-EDRMassRollout.ps1`

### Projet 3 : Refonte de Commutation Réseau ArubaOS-CX (~20 Switches)
- **Défi :** Remplacement d'une infrastructure réseau vieillissante non managée par une architecture de commutation d'entreprise sécurisée et supervisée.
- **Solution Technique Implémentée :**
  - Segmentation par VLANs étanches (VLAN 10 Data, VLAN 20 VoIP QoS CoS 5, VLAN 99 Management isolé, VLAN 200 Invités).
  - Agrégation de liens haute disponibilité (**LACP Trunk**) vers le cœur de réseau.
  - Sécurité des ports d'accès : **Port-Security**, **BPDU Guard** (anti-boucle), **DHCP Snooping** (anti-serveur rogue).
  - Intégration complète dans la supervision **PRTG Network Monitor** via SNMPv3 chiffré.
- **Preuve dans le Repo :** `Projects/Network-Aruba/New-ArubaSwitchConfig.ps1`

### Projet 4 : Déploiement Windows LAPS & Durcissement Post-Audit
- **Défi :** Suite à un audit de sécurité ayant révélé la présence d'un mot de passe administrateur local identique sur l'ensemble du parc (vulnérabilité critique aux mouvements latéraux *Pass-the-Hash*).
- **Solution Technique Implémentée :**
  - Extension du schéma Active Directory (`Update-AdmPwdADSchema`).
  - Déploiement de la stratégie GPO LAPS : génération automatique de mots de passe de 16 caractères complexes, renouvelés tous les 30 jours et stockés sous attribut chiffré dans l'AD.
  - Délégation stricte des permissions de lecture aux seuls administrateurs N3 habilités (`Set-AdmPwdReadPasswordPermission`).
- **Preuve dans le Repo :** `Projects/Windows-LAPS/Deploy-WindowsLAPS.ps1`

### Projet 5 : Bascule de Datacenter & Orchestration Veeam PRA (En Équipe)
- **Défi :** Migrer l'intégralité d'un hébergement critique vers un nouveau Datacenter sans dépasser la fenêtre de coupure de 4 heures convenue avec les clients.
- **Solution Technique Implémentée :**
  - Pré-synchronisation des machines virtuelles via réplication inter-sites Veeam Backup & Replication.
  - Orchestration de **Planned Failover** : synchronisation du delta final, arrêt propre des VMs sources, démarrage sur le cluster cible et re-IPing dynamique des cartes réseaux.
  - Résultat : **RTO réel mesuré à 38 minutes** (largement sous le SLA contractuel de 4h).
- **Preuve dans le Repo :** `Projects/Datacenter-Migration/Invoke-VeeamFailoverPlan.ps1`

### Projet 6 : Masterisation Industrielle MDT/WDS 200+ Postes (Texdecor Group)
- **Défi :** Migration industrielle de 200 postes Windows 7 vers Windows 10 en tant qu'unique technicien sur site pour 250 collaborateurs.
- **Solution Technique Implémentée :**
  - Mise en place d'un serveur WDS avec **Microsoft Deployment Toolkit (MDT 8456)**.
  - Organisation des pilotes selon la méthode **Total Control** par constructeur et modèle (Dell Latitude/OptiPlex, HP, Lenovo).
  - Configuration `CustomSettings.ini` Zero-Touch : renommage automatique `CLI-%SERIAL%`, jonction de domaine AD, désactivation télémétrie et chiffrement BitLocker automatique.
- **Preuve dans le Repo :** `Projects/MDT-Deployment/Invoke-MDTIndustrialization.ps1`

---

## 💬 3. Guide de Réponses aux Questions Techniques d'Entretien

### Q1 : "Comment gérez-vous une panne critique P1 en pleine nuit lors d'une astreinte ?"
> **Ma réponse :**  
> *"La priorité absolue en astreinte P1 est la maîtrise du temps de réponse (GTI < 15 min) et la stabilisation sans panique. Dès l'alerte, j'exécute la boîte noire `Invoke-P1EmergencyTriage.ps1` pour capturer l'état mémoire, les crash dumps BSOD et les 50 derniers événements système.  
> Si c'est une défaillance matérielle ou de stockage, j'ordonne la bascule sur le nœud ou site de secours via les plans de failover Veeam pré-validés.  
> Si c'est une alerte de sécurité ou ransomware, j'isole immédiatement l'hôte du réseau avec le KillSwitch `Invoke-RansomwareShield.ps1` pour bloquer la propagation latérale tout en préservant les preuves pour le SOC.  
> Enfin, je communique immédiatement avec le client selon un modèle standardisé pour lui assurer que l'incident est sous contrôle."*

### Q2 : "Quelle est votre stratégie de sauvegarde face aux risques de Ransomware ?"
> **Ma réponse :**  
> *"J'applique rigoureusement la règle 3-2-1-1-0 préconisée par Veeam : 3 copies des données, sur 2 supports différents, dont 1 externalisée sur un second site, et 1 copie immuable (WORM - Write Once, Read Many sur Linux durci avec rétention verrouillée) ou offline (air-gapped).  
> Le zéro signifie zéro erreur : des tests réguliers de restauration automatique (SureBackup / `Invoke-DRTest.ps1`) sont indispensables car une sauvegarde non testée n'est pas une sauvegarde valide."*

### Q3 : "Comment assurez-vous l'hygiène et la sécurité d'un annuaire Active Directory ?"
> **Ma réponse :**  
> *"Un annuaire AD doit être audité de façon permanente : contrôle des membres du groupe Domain Admins (qui ne doivent être utilisés que pour des tâches d'administration et jamais pour ouvrir une session sur un poste), détection des comptes inactifs (> 90 jours pour les utilisateurs, > 180 jours pour les ordinateurs), éradication des comptes avec 'PasswordNeverExpires', et protection du compte KRBTGT avec réinitialisation bi-annuelle du mot de passe. C'est exactement ce que monitore automatiquement mon script `Invoke-ADHygieneCheck.ps1`."*

### Q4 : "Comment préparez-vous un Comité de Pilotage (COPIL) ou Technique (COTECH) ?"
> **Ma réponse :**  
> *"Je structure la restitution autour d'indicateurs factuels : taux de respect du SLA (cible 99.9%), MTTR moyen, répartition des tickets par typologie, tendances de saturation de capacité de stockage pour anticiper les investissements matériels, et état d'avancement des remédiations post-audit. Mon outil `Invoke-COPILReportGenerator.ps1` produit directement ces livrables exécutifs pour la direction."*

---

## 🗺️ 4. Matrice de Correspondance Compétences & Code Source

| Compétence Clé du CV | Outil / Script Développé dans le Repo |
| :--- | :--- |
| **Active Directory & Hygiène** | `Invoke-ADHygieneCheck.ps1` & `Projects/AD-Migration/` |
| **Virtualisation (VMware / Nutanix)** | `Invoke-HypervisorAudit.ps1` & `Invoke-InfrastructureSizing.ps1` |
| **Sauvegarde & PRA / PCA (Veeam)** | `Invoke-DRTest.ps1`, `Invoke-DRPGenerator.ps1`, `Projects/Datacenter-Migration/` |
| **Réseaux & Pare-feux (FortiGate / Aruba)** | `Invoke-NetworkApplianceAudit.ps1`, `Projects/Network-Aruba/`, `Projects/WAN-MPLS-Refonte/` |
| **Cybersécurité Opérationnelle (EDR / LAPS)** | `Invoke-SecurityHardening.ps1`, `Invoke-ZeroTrustAudit.ps1`, `Projects/EDR-Deployment/` |
| **Messagerie Exchange & SMTP** | `Invoke-ExchangeHealthCheck.ps1` |
| **Services Cœur (DHCP / DNS / PKI)** | `Invoke-CoreServicesAudit.ps1` |
| **Astreinte 24/7 & Incident P1** | `Invoke-P1EmergencyTriage.ps1`, `Invoke-RansomwareShield.ps1`, `Docs/RUNBOOK-ONCALL-P1-P2.md` |
| **Supervision PRTG & Linux** | `Invoke-PRTGSensorDeployer.ps1`, `Invoke-LinuxHeterogeneousAudit.ps1` |
| **Gouvernance & COPIL / COTECH** | `Invoke-COPILReportGenerator.ps1` |
