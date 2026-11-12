# 🚨 RUNBOOK D'ASTREINTE 24/7 & GESTION DES INCIDENTS CRITIQUES (P1 / P2)

> **Référentiel Opérationnel N3 • SLA Garantie de Temps de Rétablissement (GTR 4h) • Amine BERRADA**

---

## 🎯 1. Classification & Définition des Gravités d'Incidents

| Niveau | Désignation | Critères & Impact Métier | GTR Contractuelle | Canal d'Astreinte |
| :---: | :--- | :--- | :---: | :--- |
| **P1** | **Bloquant** | Arrêt total de la production, cyberattaque, rupture Datacenter, indisponibilité ERP / SQL ou messagerie globale. | **Prise en charge < 15 min**<br>**Résolution < 4 heures** | Téléphone Ligne Rouge + Alerte SMS + Teams VIP |
| **P2** | **Majeur** | Dégradation significative des performances sans arrêt total (ex: cluster N+1 en perte de redondance, saturation disque > 90%, perte d'un contrôleur de domaine secondaire). | **Prise en charge < 30 min**<br>**Résolution < 8 heures** | Teams Astreinte + Ticketing prioritaire |
| **P3** | **Mineur** | Dysfonctionnement isolé sans impact sur le cœur de métier (poste utilisateur unique, imprimante locale). | Prise en charge < 4 heures | File d'attente standard N1/N2 |

---

## ⚡ 2. Arbre de Décision Flash P1 (Les 15 Premières Minutes)

```
                            [ RÉCEPTION ALERTE P1 ]
                                       │
                    ┌──────────────────┴──────────────────┐
                    ▼                                     ▼
          [ CYBERATTAQUE AVÉRÉE ]                 [ PANNE MATÉRIELLE / SYSTÈME ]
          (Ransomware, Chiffrement,               (Écran Bleu BSOD, Crash Hôte,
           Alerte EDR SentinelOne)                 Perte Datastore, Réseau Down)
                    │                                     │
                    ▼                                     ▼
         Couper immédiatement les               Exécuter la boîte noire d'urgence :
         flux réseau de la machine :            Invoke-P1EmergencyTriage.ps1
         Invoke-RansomwareShield.ps1                      │
                    │                                     ▼
                    ▼                          Identifier le composant en panne
         Préserver les snapshots VSS            (Minidump, Event ID 41, I/O SAN)
         et notifier le RSSI / SOC                        │
                                                          ▼
                                               Bascule planifiée ou PRA :
                                               Invoke-VeeamFailoverPlan.ps1
```

---

## 🛠️ 3. Procédures d'Intervention Rapide par Scénario

### Scénario A : Écran Bleu (BSOD) en Boucle sur Serveur Critique
1. **Extraction de la boîte noire :**
   ```powershell
   powershell.exe -ExecutionPolicy Bypass -File .\Invoke-P1EmergencyTriage.ps1
   ```
2. **Analyse du Minidump :** Le rapport Flash localise automatiquement le pilote coupable (ex: `ntoskrnl.exe`, pilote SAN ou agent antivirus corrompu).
3. **Démarrage en mode sans échec / WinPE :** Désactivation du pilote ou service via registre hors-ligne si nécessaire.
4. **Envoi du rapport Flash :** Exportation du ZIP incident pour le COTECH.

### Scénario B : Suspicion d'Attaque par Ransomware
1. **Activation du KillSwitch d'isolement :**
   ```powershell
   powershell.exe -ExecutionPolicy Bypass -File .\Invoke-RansomwareShield.ps1
   ```
   *Effet : Blocage de toutes les interfaces réseau, coupure des partages SMB et protection des VSS.*
2. **Dump mémoire et connexions :** Analyse des fichiers `netstat.txt` et `processes.txt` générés dans `C:\ESN-Toolkit\Forensics`.
3. **Contrôle d'intégrité des sauvegardes :** Vérification de l'immutabilité WORM des dépôts Veeam.

### Scénario C : Saturation Critique du Disque Système C: (< 2 Go libres)
1. **Remédiation immédiate sans risque :**
   ```powershell
   powershell.exe -ExecutionPolicy Bypass -File .\Invoke-IncidentAnalysis.ps1 -Fix TempFiles
   ```
2. **Purge des composants Windows Update corrompus :**
   ```powershell
   Dism.exe /online /Cleanup-Image /StartComponentCleanup /ResetBase
   ```
3. **Analyse prédictive de croissance :**
   ```powershell
   powershell.exe -ExecutionPolicy Bypass -File .\Invoke-PredictiveHealthAnalysis.ps1
   ```

---

## 📢 4. Modèle de Communication de Crise (Client & Direction)

### Message Initial d'Accusé de Réception P1 (< 15 min) :
```text
Objet : [INCIDENT MAJEUR P1] Prise en charge en cours - [Nom du Client]

Bonjour,

Un incident de criticité P1 (Bloquant) a été détecté sur l'environnement [Nom de l'infrastructure] à [Heure].
La cellule d'astreinte N3 a pris en charge le dossier.

• Symptôme constaté : [Ex: Indisponibilité du cluster de production / Arrêt du serveur SQL]
• Actions en cours : Diagnostic boîte noire et analyse des métriques de continuité.
• Prochain point de situation : Dans 30 minutes.

Référent d'astreinte : Amine BERRADA (Ingénieur Système N3)
```

### Message de Résolution & Clôture :
```text
Objet : [RÉSOLU] Clôture Incident P1 - [Nom du Client]

Bonjour,

L'incident P1 impactant [Nom du service] est désormais entièrement résolu à [Heure].
Les tests de bon fonctionnement applicatif et d'intégrité des données ont été validés avec succès.

• Cause racine : [Ex: Défaillance d'alimentation redondante ayant provoqué un basculement SAN]
• Action corrective : [Ex: Basculement contrôlé sur le nœud de secours et validation des flux]
• Durée d'interruption : [Ex: 24 minutes (Conforme SLA contractuel)]

Un rapport d'incident post-mortem détaillé (RCA) vous sera transmis sous 24h pour le prochain COTECH.

Cordialement,
Amine BERRADA
```

---

## 📋 5. Checklist Post-Mortem pour le COPIL / COTECH
- [ ] Extraction des journaux d'événements bruts (`.evtx`).
- [ ] Génération du rapport de clôture avec métriques MTTR (`Invoke-COPILReportGenerator.ps1`).
- [ ] Vérification du statut de la sauvegarde suivante (validation de la chaîne de restauration).
- [ ] Identification de la cause racine et mise à jour de la documentation d'architecture.
