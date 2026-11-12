# 📓 LE LIVRE NOIR DES INCIDENTS : ANALYSES DE CAUSE RACINE & POST-MORTEMS

> **Compendium Réel d'Incidents Critiques (P1 / P2) Résolus en Environnement de Production**  
> *Auteur : Amine BERRADA (Référent Technique N3 & Ingénieur Système)*

Ce document compile **8 retours d'expérience (REX)** d'incidents majeurs résolus sur plus de 200 infrastructures infogérées (ESN AEXIN Genève, BY THE WAY et TEXDECOR GROUP). Chaque cas illustre la méthode d'investigation, la cause racine, l'action immédiate sous astreinte et la remédiation pérenne.

---

## 📑 Sommaire des Incidents

1. [Incident P1 : Cascade de Snapshots VMware & Saturation de Datastore LUN](#incident-1)
2. [Incident P1 : Tentative d'Intrusion Ransomware & Déclenchement KillSwitch](#incident-2)
3. [Incident P2 : Boucle Réseau & Tempête de Broadcast sur Commutateurs](#incident-3)
4. [Incident P2 : Rupture de Réplication Active Directory & USN Rollback](#incident-4)
5. [Incident P2 : Backpressure Exchange & Blocage des Files d'Attente de Messagerie](#incident-5)
6. [Incident P3 : Épuisement d'Étendue DHCP Bloquant 80 Collaborateurs](#incident-6)
7. [Incident P2 : Conflit d'Attributs & Désynchronisation Azure AD Connect](#incident-7)
8. [Incident P1 : Rupture WAN MPLS Intersites & Bascule Secours IPsec](#incident-8)

---

### <a id="incident-1"></a>Incident 1 : Cascade de Snapshots VMware & Saturation de Datastore LUN
- **Criticité :** **P1 (Bloquant)** — Menace d'arrêt de 18 machines virtuelles critiques de production.
- **Contexte :** Cluster VMware vSphere 7.0 sous baie SAN SAN/iSCSI chez un grand compte horloger.
- **Symptôme Initial :** Alerte vCenter `Datastore usage alarm > 98%`. Plusieurs VMs se sont mises en pause automatique (*VM stunned*) faute d'espace disque pour les deltas VMDK.
- **Investigation & Cause Racine :**
  - Un job de sauvegarde Veeam s'était interrompu anormalement 5 jours auparavant, laissant le disque virtuel verrouillé par l'hôte ESXi.
  - Le snapshot n'avait pas été consolidé et continuait à grossir de 40 Go par jour.
- **Action d'Urgence sous Astreinte :**
  1. Identification de la VM consommatrice via `Invoke-HypervisorAudit.ps1` (Snapshots > 72h).
  2. Agrandissement d'urgence temporaire du LUN de 200 Go sur la baie SAN pour débloquer les I/O.
  3. Relance des VMs figées sans perte de données transactionnelles.
  4. Lancement de la consolidation des disques VMDK en heures creuses.
- **Remédiation Pérenne :**
  - Déploiement d'une sonde personnalisée PRTG (`Invoke-PRTGSensorDeployer.ps1`) alertant dès qu'un snapshot dépasse 24 heures d'existence.

---

### <a id="incident-2"></a>Incident 2 : Tentative d'Intrusion Ransomware & Déclenchement KillSwitch
- **Criticité :** **P1 (Bloquant / Cybersécurité)**.
- **Contexte :** Serveur de fichiers d'un groupe industriel avec 2 To de données partagées.
- **Symptôme Initial :** Alerte SOC / SentinelOne signalant un comportement suspect de chiffrement massif et création de fichiers avec extensions inconnues (`.locked`).
- **Investigation & Cause Racine :**
  - Compromission d'un compte utilisateur via phishing, utilisation des partages SMB pour chiffrer les données à distance depuis le poste infecté.
- **Action d'Urgence sous Astreinte :**
  1. Exécution immédiate du KillSwitch `Invoke-RansomwareShield.ps1` : coupure des interfaces réseau du serveur et arrêt immédiat du service `Server` (partages SMB).
  2. Gel et vérification des clichés instantanés VSS locaux.
  3. Identification du poste source par corrélation des événements de sécurité Event ID 5140 (Accès aux partages).
  4. Révocation immédiate du compte AD et désactivation du port switch du poste compromis.
- **Restauration & Remédiation :**
  - Restauration des fichiers modifiés depuis le dépôt de sauvegarde immuable **Veeam WORM** (aucun rançonnage payé, RPO < 30 min).
  - Déploiement de **Windows LAPS** sur l'ensemble du parc pour empêcher tout rebond latéral.

---

### <a id="incident-3"></a>Incident 3 : Boucle Réseau & Tempête de Broadcast sur Commutateurs
- **Criticité :** **P2 (Majeur)** — Dégradation sévère du réseau local (latence > 800 ms, paquets perdus à 60%).
- **Contexte :** Étage de bureaux avec ~20 commutateurs Aruba et câblage utilisateur en libre accès.
- **Symptôme Initial :** Les voyants d'activité des commutateurs clignotent frénétiquement en continu. Téléphonie IP hachée et déconnexions RDP en chaîne.
- **Investigation & Cause Racine :**
  - Un utilisateur a branché par inadvertance les deux extrémités d'un câble Ethernet RJ45 sur deux prises murales distinctes reliées au même switch.
  - La fonction BPDU Guard était absente sur ce port d'accès, entraînant une boucle infinie de trames broadcast (*Broadcast Storm*).
- **Action d'Urgence :**
  1. Identification du port en boucle via les compteurs d'erreurs et utilisation CPU du switch (`show interface brief` / `show mac-address`).
  2. Désactivation administrative immédiate du port (`shutdown`).
  3. Stabilisation instantanée du réseau en moins de 10 minutes.
- **Remédiation Pérenne :**
  - Injection globale de la configuration durcie `Projects/Network-Aruba/New-ArubaSwitchConfig.ps1` activant **STP BPDU Guard** et **Root Guard** sur tous les ports terminaux (edge ports). Tout branchement en boucle désactive désormais automatiquement le port incriminé en 1 seconde sans impacter le reste du réseau.

---

### <a id="incident-4"></a>Incident 4 : Rupture de Réplication Active Directory & USN Rollback
- **Criticité :** **P2 (Majeur)**.
- **Contexte :** Deux contrôleurs de domaine (DC1 et DC2) sous Windows Server 2019.
- **Symptôme Initial :** Les modifications d'utilisateurs et mots de passe créés sur DC1 ne sont pas répercutées sur DC2. Journaux d'événements : Event ID 2042 (*It has been too long since this machine replicated*).
- **Investigation & Cause Racine :**
  - Un snapshot matériel d'un DC virtualisé avait été restauré par erreur plusieurs semaines après son arrêt, provoquant une désynchronisation des compteurs de numéros de séquence de mise à jour (**USN Rollback**).
- **Action & Remédiation :**
  1. Exécution de `Invoke-ADHygieneCheck.ps1` et `repadmin /showrepl` pour cartographier les erreurs.
  2. Démotion forcée propre du contrôleur de domaine désynchronisé.
  3. Nettoyage des métadonnées dans l'annuaire via `ntdsutil` (suppression des objets serveur orphelins).
  4. Réinstallation du rôle AD DS et re-promotion propre du DC depuis le partenaire de réplication sain.

---

### <a id="incident-5"></a>Incident 5 : Backpressure Exchange & Blocage des Files d'Attente
- **Criticité :** **P2 (Majeur)** — Émission et réception d'emails bloquées pour l'ensemble des collaborateurs.
- **Contexte :** Serveur Microsoft Exchange 2019 On-Premise en environnement hybride.
- **Symptôme Initial :** Les messages restent bloqués dans les files d'attente de transport (`Get-Queue`). Event ID 15004 : *The resource pressure is high (Disk/Database)*.
- **Investigation & Cause Racine :**
  - Phénomène de **Backpressure** de transport Exchange : le volume disque hébergeant la base de données de file d'attente (`Queue Database`) est descendu sous le seuil de sécurité critique de 10% d'espace libre, entraînant l'arrêt défensif de la réception SMTP.
- **Action d'Urgence :**
  1. Diagnostic via `Invoke-ExchangeHealthCheck.ps1` confirmant la saturation de la partition des logs de transaction.
  2. Purge des journaux de transaction via sauvegarde complète Exchange (validation du commit des logs).
  3. Déplacement de la base de queue vers un volume dédié plus capacitif.
  4. Redémarrage du service `MSExchangeTransport` : vidage immédiat des files en attente.

---

### <a id="incident-6"></a>Incident 6 : Épuisement d'Étendue DHCP Bloquant 80 Collaborateurs
- **Criticité :** **P3 / Dégradation Forte** — 80 collaborateurs obtiennent des adresses IP APIPA (169.254.x.x) au démarrage du lundi matin.
- **Contexte :** Siège social avec augmentation temporaire des effectifs (prestataires et stagiaires).
- **Symptôme Initial :** Pas d'accès réseau local ni Internet.
- **Investigation & Cause Racine :**
  - L'étendue DHCP `/24` (254 adresses) était saturée à 100%. Le bail par défaut (8 jours) conservait les réservations de smartphones et ordinateurs portables de passage.
- **Action & Remédiation :**
  1. Détection via `Invoke-CoreServicesAudit.ps1` : alerte scope à 100%.
  2. Réduction du bail DHCP à **8 heures** pour les postes et Wi-Fi dynamique.
  3. Purge des baux inactifs expirés.
  4. Agrandissement de l'étendue avec passage en sous-réseau `/23` (510 adresses disponibles).

---

### <a id="incident-7"></a>Incident 7 : Conflits d'Attributs & Désynchronisation Azure AD Connect
- **Criticité :** **P2 (Majeur)**.
- **Contexte :** Environnement Cloud Hybride avec synchronisation Microsoft Entra ID.
- **Symptôme Initial :** Les nouveaux collaborateurs créés dans l'Active Directory local n'apparaissent pas dans Microsoft 365.
- **Investigation & Cause Racine :**
  - Conflit d'attribut `ProxyAddresses` : deux comptes distincts partageaient par erreur le même alias SMTP dans l'annuaire on-premise, bloquant la synchronisation d'exportation de l'outil Azure AD Connect.
- **Action & Remédiation :**
  1. Audit via `Invoke-CloudHybridAudit.ps1` extrayant le rapport d'erreurs de synchronisation.
  2. Correction de l'attribut SMTP en doublon dans les propriétés de l'objet utilisateur.
  3. Déclenchement d'un cycle de synchronisation delta forcé :
     ```powershell
     Start-ADSyncSyncCycle -PolicyType Delta
     ```
  4. Intégration validée et boîtes aux lettres activées sans délai.

---

### <a id="incident-8"></a>Incident 8 : Rupture WAN MPLS Intersites & Bascule Secours IPsec
- **Criticité :** **P1 (Bloquant)**.
- **Contexte :** Deux sites distants reliés par lien opérateur MPLS prioritaire et lien de secours FttH IPsec.
- **Symptôme Initial :** Coupure de fibre sur la voie publique chez l'opérateur principal. Perte de communication avec le site secondaire.
- **Investigation & Cause Racine :**
  - La route par défaut vers le secours n'avait pas basculé automatiquement car le mécanisme de détection de lien (*IP SLA Track*) était désactivé suite à une maintenance opérateur antérieure.
- **Action d'Urgence :**
  1. Audit des passerelles via `Projects/WAN-MPLS-Refonte/Invoke-WANMigrationPlan.ps1`.
  2. Forçage de la métrique de routage vers la passerelle de secours IPsec FortiGate.
  3. Rétablissement des flux de production en moins de 15 minutes.
  4. Réactivation de la sonde de détection de perte de lien automatique (*Dead Peer Detection DPD* & *Link Health Monitor*).
