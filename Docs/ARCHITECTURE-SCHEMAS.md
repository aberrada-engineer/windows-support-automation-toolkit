# 📐 SCHÉMAS D'ARCHITECTURE SYSTÈMES, RÉSEAUX & CONTINUITÉ D'ACTIVITÉ

> **Dossier d'Architecture Technique (DAT) • Conçu par Amine BERRADA**  
> *Ces schémas documentent les infrastructures réelles conçues, migrées et opérées au cours de mes missions.*

---

## 1. Architecture Multi-Sites WAN (MPLS / SD-WAN) & PRA Intersites

Ce schéma illustre la topologie réseau opérée avec opérateur télécom, bascule automatique de secours et réplication de continuité d'activité (PRA) :

```mermaid
graph TD
    subgraph Site_Principal ["Datacenter Principal (Production)"]
        DC1["Cluster Nutanix / VMware (Production)"]
        VBR1["Veeam Backup Server + WAN Accelerator"]
        FW1["Pare-feu FortiGate Cluster HA"]
    end

    subgraph Operateur_WAN ["Réseau WAN Multi-Sites"]
        MPLS["Lien Opérateur MPLS Prioritaire (QoS CoS 5 VoIP)"]
        IPSEC["Tunnel Secours IPsec FttH Redondant"]
    end

    subgraph Site_Secours ["Datacenter Secours (PRA)"]
        FW2["Pare-feu FortiGate PRA"]
        VBR2["Veeam Backup Repository Immuable WORM"]
        DC2["Cluster de Secours (Host Standby)"]
    end

    DC1 --> VBR1
    VBR1 --> FW1
    FW1 -- "Trafic Nominal" --> MPLS
    FW1 -- "Bascule Failover (BGP/IP SLA)" --> IPSEC
    MPLS --> FW2
    IPSEC --> FW2
    FW2 --> VBR2
    VBR2 --> DC2
```

---

## 2. Architecture de Sauvegarde Résiliente Veeam 3-2-1-1-0 (Anti-Ransomware)

Mise en œuvre chez les grands comptes pour garantir la survie des données face aux menaces avancées :

```mermaid
flowchart LR
    VMs["Machines Virtuelles Production (Hyper-V / VMware / Nutanix)"] -->|Sauvegarde Quotidienne| Repo_Local["Dépôt Primaire Rapide (Baie SAN / SSD)"]
    Repo_Local -->|Copie de Sauvegarde (Backup Copy)| Repo_Linux["Dépôt Immuable WORM (Linux Durci XFS - 30 Jours Verrouillé)"]
    Repo_Local -->|Réplication WAN Accélérée| Cloud_DR["Datacenter Secondaire / Cloud Hybride Air-Gapped"]
    Repo_Linux -->|Vérification Automatique| SureBackup["SureBackup : Démarrage en bac à sable & test d'intégrité (Zéro Erreur)"]
```

---

## 3. Flux de Migration Inter-Domaines Active Directory (Avec SID History)

Processus de bascule sans rupture de service réalisé en autonomie :

```mermaid
sequenceDiagram
    autonumber
    actor Admin as Amine Berrada (Ingénieur Système)
    participant SourceAD as Domaine Source (Historique)
    participant TargetAD as Domaine Cible (Nouveau)
    participant FileServer as Serveur de Fichiers (ACL NTFS)
    participant Workstation as Poste Utilisateur

    Admin->>TargetAD: Établissement Relation d'Approbation Transitive
    Admin->>SourceAD: Extraction Utilisateurs & Groupes de Sécurité
    Admin->>TargetAD: Création des comptes avec injection du SID History (sIDHistory)
    Admin->>FileServer: Sauvegarde des ACLs NTFS (icacls /save)
    Admin->>Workstation: Exécution script de translation de profil local
    Workstation->>TargetAD: Jonction au nouveau domaine
    Note over Workstation,FileServer: L'utilisateur accède immédiatement à ses partages grâce au SID History !
```

---

## 4. Architecture de Commutation d'Entreprise Sécurisée (ArubaOS-CX)

Topologie des 20 switches déployés avec segmentation et protection anti-boucle :

```mermaid
graph TD
    Core1["Cœur de Réseau Switch 1 (Aruba CX)"] --- Core2["Cœur de Réseau Switch 2 (Aruba CX)"]
    
    subgraph Distribution_Etages ["Switches d'Accès Étages (20 Unités)"]
        SW_Etage1["Switch Étage 1 (Aruba CX)"]
        SW_Etage2["Switch Étage 2 (Aruba CX)"]
        SW_Etage3["Switch Étage 3 (Aruba CX)"]
    end

    Core1 ===|"LACP Trunk (802.3ad)"| SW_Etage1
    Core2 ===|"LACP Trunk (802.3ad)"| SW_Etage1
    Core1 ===|"LACP Trunk"| SW_Etage2
    Core2 ===|"LACP Trunk"| SW_Etage2
    Core1 ===|"LACP Trunk"| SW_Etage3
    Core2 ===|"LACP Trunk"| SW_Etage3

    subgraph Securite_Ports ["Sécurisation des Ports d'Accès"]
        VLAN10["VLAN 10 : Données Postes"]
        VLAN20["VLAN 20 : Téléphonie VoIP (QoS CoS 5)"]
        VLAN99["VLAN 99 : Management Isolé (ACL Restrictive)"]
        Prot["BPDU Guard + DHCP Snooping + Port-Security"]
    end

    SW_Etage1 --> Securite_Ports
```

---

## 5. Plateforme AIOps ESN-Toolkit : Cycle d'Auto-Guérison

```mermaid
stateDiagram-v2
    [*] --> Surveillance: Watchdog Planifié (15 min)
    Surveillance --> Analyse_Metriques: Vérification Services, Disque C:, DNS, Defender
    
    state Decision_Arbre <<choice>>
    Analyse_Metriques --> Decision_Arbre
    
    Decision_Arbre --> Nominal: Tous les indicateurs sont au vert
    Nominal --> [*]: Enregistrement télémétrie OK
    
    Decision_Arbre --> Incident_Detecte: Service arrêté ou C: > 85%
    Incident_Detecte --> Auto_Remediation: Relance service / Purge cache / Reset pile
    Auto_Remediation --> Validation: Nouveau contrôle après correction
    
    Validation --> Notification: Envoi alerte Teams / Webhook avec Root Cause Analysis
    Notification --> [*]: Ticket résolu sans appel support
```
