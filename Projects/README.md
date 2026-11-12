# 💼 PLAYBOOKS D'INGÉNIERIE : LES 6 PROJETS CLÉS DÉPLOYÉS EN CODE EXÉCUTABLE

> **Répertoire des Projets d'Infrastructure Réalisés par Amine BERRADA**  
> *Ces dossiers contiennent les scripts et playbooks d'automatisation reproduisant fidèlement les architectures d'entreprise déployées lors de mes missions.*

---

## 📂 Architecture du Dossier `Projects/`

```
Projects/
│
├── AD-Migration/          # Migration Inter-Domaines Active Directory
│   └── Invoke-ADDomainMigration.ps1   # Extraction, SID History mapping, ACLs NTFS & migration postes
│
├── EDR-Deployment/        # Déploiement Massif d'EDR (+200 Postes)
│   └── Invoke-EDRMassRollout.ps1      # Désinstallation legacy AV, token cloud & validation service
│
├── Network-Aruba/         # Commutation d'Entreprise ArubaOS-CX
│   └── New-ArubaSwitchConfig.ps1      # Configurations durcies (VLANs, LACP Uplinks, BPDU Guard, PRTG)
│
├── Windows-LAPS/          # Durcissement Post-Audit Windows LAPS
│   └── Deploy-WindowsLAPS.ps1         # Extension schéma AD, GPO 30j rotation, remédiation Pass-the-Hash
│
├── Datacenter-Migration/  # Bascule Datacenter & Orchestration PRA
│   └── Invoke-VeeamFailoverPlan.ps1   # Planned Failover Veeam, synchronisation delta, re-IPing
│
├── MDT-Deployment/        # Industrialisation Déploiement OS (200+ Postes)
│   └── Invoke-MDTIndustrialization.ps1# CustomSettings.ini Zero-Touch, Total Control drivers (Texdecor)
│
└── WAN-MPLS-Refonte/      # Refonte WAN Multi-Sites & Continuité PRA
    └── Invoke-WANMigrationPlan.ps1    # Recette opérateur MPLS/SD-WAN, test MTU DF-Bit & port Veeam PRA
```

---

## 🛠️ Description & Guide d'Exécution des Playbooks

### 1. 🔄 Migration Inter-Domaines Active Directory
- **Script :** `Projects/AD-Migration/Invoke-ADDomainMigration.ps1`
- **Cas d'usage :** Consolidation ou fusion de domaines AD sans perte de droits d'accès.
- **Exemple d'exécution :**
  ```powershell
  .\Projects\AD-Migration\Invoke-ADDomainMigration.ps1 -SourceDomain "oldcorp.lan" -TargetDomain "newcorp.lan" -ReportOnly
  ```

### 2. 🛡️ Déploiement Automatisé d'EDR (+200 Hôtes)
- **Script :** `Projects/EDR-Deployment/Invoke-EDRMassRollout.ps1`
- **Cas d'usage :** Remplacement d'antivirus legacy par SentinelOne ou Defender for Endpoint.
- **Exemple d'exécution :**
  ```powershell
  .\Projects\EDR-Deployment\Invoke-EDRMassRollout.ps1 -SiteToken "eyJhbGciOi..." -ReportOnly
  ```

### 3. 🔌 Configuration Durcie Commutateurs Aruba CX
- **Script :** `Projects/Network-Aruba/New-ArubaSwitchConfig.ps1`
- **Cas d'usage :** Génération de fichiers de configuration conformes pour switches d'accès.
- **Exemple d'exécution :**
  ```powershell
  .\Projects\Network-Aruba\New-ArubaSwitchConfig.ps1 -SwitchHostname "SW-ACC-ETAGE1" -VlanData 10 -VlanVoice 20
  ```

### 4. 🔐 Déploiement & Audit Windows LAPS
- **Script :** `Projects/Windows-LAPS/Deploy-WindowsLAPS.ps1`
- **Cas d'usage :** Éradication des attaques latérales par rebond (*Pass-the-Hash*).
- **Exemple d'exécution :**
  ```powershell
  .\Projects\Windows-LAPS\Deploy-WindowsLAPS.ps1 -ReportOnly
  ```

### 5. 🏢 Bascule Datacenter Veeam PRA
- **Script :** `Projects/Datacenter-Migration/Invoke-VeeamFailoverPlan.ps1`
- **Cas d'usage :** Orchestration de failover planifié de Datacenter avec RTO mesuré sous 4h.
- **Exemple d'exécution :**
  ```powershell
  .\Projects\Datacenter-Migration\Invoke-VeeamFailoverPlan.ps1 -DryRun
  ```

### 6. 🖥️ Industrialisation Master MDT / WDS (200+ Postes)
- **Script :** `Projects/MDT-Deployment/Invoke-MDTIndustrialization.ps1`
- **Cas d'usage :** Déploiement de masse Windows 10/11 sans bloatware (expérience Texdecor).
- **Exemple d'exécution :**
  ```powershell
  .\Projects\MDT-Deployment\Invoke-MDTIndustrialization.ps1 -ReportOnly
  ```

### 7. 🌐 Refonte WAN Multi-Sites & Recette PRA
- **Script :** `Projects/WAN-MPLS-Refonte/Invoke-WANMigrationPlan.ps1`
- **Cas d'usage :** Contrôle des métriques de bascule opérateur et bande passante de réplication intersites.
- **Exemple d'exécution :**
  ```powershell
  .\Projects\WAN-MPLS-Refonte\Invoke-WANMigrationPlan.ps1 -ReportOnly
  ```
