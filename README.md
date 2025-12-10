# Nettoyage des downloads (`cleanup_downloads.sh`)

## 🎯 Objectif

Automatiser le **nettoyage hebdomadaire** des dossiers de downloads temporaires sur le conteneur LXC **`docker-ptr`**, avec :

- Suppression des fichiers de plus de **168 heures (7 jours)** dans :
  - `/downloads/incoming/medias`
  - `/downloads/incoming/music`
- Suppression des **dossiers vides** résiduels.
- Génération d’un **log propre** (un seul run à la fois) : `/var/log/cleanup_downloads.log`
- Envoi d’un **rapport détaillé sur Discord** :
  - Résumé par dossier (avant / après / nombre de fichiers supprimés)
  - Log complet joint en **pièce jointe**.

Ce script est prévu pour tourner **1 fois par semaine via cron** sur `docker-ptr`.

---

## 📂 Emplacement et nom du script

- Hôte : conteneur LXC **`docker-ptr`**
- Script :
  ```bash
  /home/scripts/cleanup_downloads.sh
  ```

---

## ⚙️ Dossiers concernés

Le script traite **exactement** ces deux répertoires :

- `/downloads/incoming/medias`
- `/downloads/incoming/music`

Les deux répertoires doivent être **accessibles dans le LXC** (typiquement montés depuis OMV via NFS).

---

## ⏱️ Rétention

- Rétention actuelle : **168 heures** (7 jours)
- Paramètre dans le script :
  ```bash
  MIN_AGE_HOURS=168
  ```

Tous les fichiers plus vieux que cette durée sont candidats à la suppression (hors fichiers `.nfs*`).

---

## 🧩 Pré-requis

Sur le conteneur `docker-ptr` :

1. **Binaire `jq`** (installé automatiquement si absent)
2. **`curl`** (normalement déjà présent)
3. Accès réseau sortant vers Discord (port HTTPS 443)
4. Dossier `/home/scripts` présent (sinon créé manuellement) :
   ```bash
   mkdir -p /home/scripts
   ```

---

## 🧾 Contenu fonctionnel du script

### 1. Variables principales

- **Discord Webhook** (déjà configuré dans le script) :

  ```bash
  WEBHOOK_URL="https://discord.com/api/webhooks/…"
  ```
- **Dossiers à nettoyer** :

  ```bash
  DIRS=(
    "/downloads/incoming/medias"
    "/downloads/incoming/music"
  )
  ```
- **Rétention (168h)** :

  ```bash
  MIN_AGE_HOURS=168
  ```
- **Fichier de log** :

  ```bash
  LOG_FILE="/var/log/cleanup_downloads.log"
  ```

### 2. Comportement détaillé

Pour chaque dossier de `DIRS` :

1. Mesure la **taille avant** avec `du -sh`.
2. Cherche les fichiers **plus vieux que la rétention**, en excluant les `.nfs*` :
   ```bash
   find "$DIR" -type f -mmin +"$min_age_minutes" ! -name '.nfs*' -print
   ```
3. Supprime chaque fichier trouvé et compte le nombre de suppressions.
4. Supprime les **répertoires vides** restants :
   ```bash
   find "$DIR" -mindepth 1 -type d -empty -print -delete
   ```
5. Mesure la **taille après** (`du -sh`).

Les informations sont enregistrées dans le log et résumées dans le message Discord.

---

## 📝 Gestion du log

- Fichier : `/var/log/cleanup_downloads.log`
- À chaque exécution, le log est **réinitialisé** :
  ```bash
  : > "$LOG_FILE"
  ```
- Le fichier joint envoyé à Discord contient **uniquement le dernier run**, avec :
  - Date/heure
  - Dossiers traités
  - Taille avant / après
  - Liste des fichiers supprimés
  - Dossiers vides supprimés
  - Messages d’erreur éventuels (ex. permissions).

---

## 💬 Notification Discord

Le script construit un message multi-ligne du type :

```text
📂 Cleanup downloads (docker-ptr)

Date : 2025-12-10 12:56:32
Rétention : 168h (7 jours)

Résumé par répertoire :
/downloads/incoming/medias :
  • avant     : 262G
  • après     : 262G
  • supprimés : 0
/downloads/incoming/music :
  • avant     : 155G
  • après     : 155G
  • supprimés : 10

Log complet en pièce jointe.
```

Le contenu est envoyé avec `jq -Rs` pour respecter le format JSON de Discord et la limite de **2000 caractères** sur le champ `content`.
Le log est joint comme fichier texte via `curl -F "file=@…"`.

---

## 🔐 Particularités NFS (`.nfs*`)

Les fichiers de type `.nfsXXXXXXXX` sont **propres à NFS** et apparaissent lorsque :

- un fichier est supprimé côté serveur,
- mais encore ouvert par un process côté client (lecteur, client torrent, etc.).

Pour éviter les erreurs répétées et inutiles, le script **ignore** ces fichiers :

```bash
! -name '.nfs*'
```

Ils seront nettoyés automatiquement par NFS une fois qu’aucun process ne les utilise.

---

## 🚀 Installation / Mise à jour

1. Sur `docker-ptr` :

   ```bash
   mkdir -p /home/scripts
   nano /home/scripts/cleanup_downloads.sh
   ```
2. Coller le script complet fourni.
3. Rendre le script exécutable :

   ```bash
   chmod +x /home/scripts/cleanup_downloads.sh
   ```
4. Test manuel :

   ```bash
   /home/scripts/cleanup_downloads.sh
   tail -n 80 /var/log/cleanup_downloads.log
   ```
5. Vérifier que :

   - un message apparaît bien sur Discord,
   - le log (`cleanup_downloads.log`) décrit uniquement le dernier run,
   - les tailles avant/après et le nombre de fichiers supprimés sont cohérents.

---

## ⏲️ Cron : exécution automatique hebdomadaire

Pour lancer le script **une fois par semaine** (dimanche à 04h00) sur `docker-ptr` :

```bash
crontab -e
```

Ajouter la ligne suivante :

```cron
0 4 * * 0 /home/scripts/cleanup_downloads.sh
```

> ⚠️ Le chemin doit rester **absolu** (`/home/scripts/...`) pour être compatible avec cron.

---

## 🔧 Personnalisation future

- **Modifier la rétention** :Changer :

  ```bash
  MIN_AGE_HOURS=168
  ```

  Exemple pour 3 jours :

  ```bash
  MIN_AGE_HOURS=72
  ```
- **Ajouter / retirer des dossiers** :Modifier la liste :

  ```bash
  DIRS=(
    "/downloads/incoming/medias"
    "/downloads/incoming/music"
    # Ajouter ici un autre dossier éventuel
  )
  ```
- **Changer le webhook Discord** :
  Modifier la valeur de :

  ```bash
  WEBHOOK_URL="..."
  ```

---

## ✅ Résumé

Ce script `cleanup_downloads.sh` assure :

- un nettoyage **automatique, sécurisé et tracé** des dossiers de downloads temporaires,
- un log clair, limité au **dernier run**,
- une **visibilité complète** via Discord (résumé + log joint),
- la compatibilité avec NFS grâce à l’exclusion des `.nfs*`.

Il est prêt à être utilisé en production dans le LXC `docker-ptr` avec une exécution hebdomadaire via cron.
