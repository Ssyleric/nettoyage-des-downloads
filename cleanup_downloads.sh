#!/usr/bin/env bash
# Nettoyage des downloads incoming :
# - /downloads/incoming/medias
# - /downloads/incoming/music
# Rétention : fichiers de plus de 168h supprimés
# Notification Discord avec log joint.
# Le log ne contient que le dernier run.

set -euo pipefail

# ------------ CONFIG ------------
WEBHOOK_URL="https://discord.com/api/webhooks/1234567890987654321/khsbdfghiebdghasblibfkshdbgklasjdbgkvjdsbvkjdsbskbjv"

DIRS=(
  "/downloads/incoming/medias"
  "/downloads/incoming/music"
)

# Âge minimum avant suppression (en heures)
MIN_AGE_HOURS=168

LOG_FILE="/var/log/cleanup_downloads.log"
# --------------------------------

timestamp() {
  date +"%Y-%m-%d %H:%M:%S"
}

ensure_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "[$(timestamp)] jq introuvable, installation..." >> "$LOG_FILE"
    apt update -y >> "$LOG_FILE" 2>&1
    apt install -y jq >> "$LOG_FILE" 2>&1
  fi
}

send_discord() {
  local message="$1"
  local logfile="$2"

  # Respect limite Discord (2000 caractères pour content)
  local max_len=1900
  local msg_len=${#message}
  if [ "$msg_len" -gt "$max_len" ]; then
    message="${message:0:$max_len}…(truncated)"
  fi

  # Payload JSON avec jq -Rs
  local json_payload
  json_payload=$(printf '%s' "$message" | jq -Rs '{content: .}')

  curl -sS -X POST \
    -F "payload_json=$json_payload" \
    -F "file=@${logfile};type=text/plain" \
    "$WEBHOOK_URL" >/dev/null 2>&1 || {
      echo "[$(timestamp)] ERREUR : envoi Discord échoué" >> "$LOG_FILE"
    }
}

main() {
  mkdir -p "$(dirname "$LOG_FILE")"

  # On nettoie le log : ne conserver que le run courant
  : > "$LOG_FILE"

  ensure_jq

  echo "[$(timestamp)] --- Début nettoyage downloads incoming ---" >> "$LOG_FILE"
  echo "[$(timestamp)] Rétention : ${MIN_AGE_HOURS}h" >> "$LOG_FILE"

  local -a sizes_before=()
  local -a sizes_after=()
  local -a deleted_counts=()

  local min_age_minutes=$(( MIN_AGE_HOURS * 60 ))

  for DIR in "${DIRS[@]}"; do
    echo "[$(timestamp)] Traitement du dossier : $DIR" >> "$LOG_FILE"

    if [ ! -d "$DIR" ]; then
      echo "[$(timestamp)]  -> SKIP : dossier introuvable" >> "$LOG_FILE"
      sizes_before+=("N/A")
      sizes_after+=("N/A")
      deleted_counts+=("0")
      continue
    fi

    # Taille avant
    local size_before
    size_before=$(du -sh "$DIR" 2>/dev/null | awk '{print $1}')
    sizes_before+=("$size_before")
    echo "[$(timestamp)]  -> Taille avant : $size_before" >> "$LOG_FILE"

    # Liste des fichiers à supprimer
    # On EXCLUT les fichiers spéciaux NFS (.nfs*)
    mapfile -t FILES_TO_DELETE < <(
      find "$DIR" -type f -mmin +"$min_age_minutes" ! -name '.nfs*' -print 2>/dev/null || true
    )

    local deleted_count=0
    if [ "${#FILES_TO_DELETE[@]}" -gt 0 ]; then
      echo "[$(timestamp)]  -> Fichiers supprimés :" >> "$LOG_FILE"
      for f in "${FILES_TO_DELETE[@]}"; do
        echo "[$(timestamp)]     $f" >> "$LOG_FILE"
        if rm -f -- "$f" 2>>"$LOG_FILE"; then
          deleted_count=$((deleted_count + 1))
        else
          echo "[$(timestamp)]        -> ERREUR : impossible de supprimer ($f), on continue." >> "$LOG_FILE"
        fi
      done
    else
      echo "[$(timestamp)]  -> Aucun fichier à supprimer (> ${MIN_AGE_HOURS}h)" >> "$LOG_FILE"
    fi
    deleted_counts+=("$deleted_count")

    # Suppression des dossiers vides
    echo "[$(timestamp)]  -> Suppression des dossiers vides :" >> "$LOG_FILE"
    find "$DIR" -mindepth 1 -type d -empty -print -delete >> "$LOG_FILE" 2>&1 || true

    # Taille après
    local size_after
    size_after=$(du -sh "$DIR" 2>/dev/null | awk '{print $1}')
    sizes_after+=("$size_after")
    echo "[$(timestamp)]  -> Taille après : $size_after" >> "$LOG_FILE"
  done

  echo "[$(timestamp)] --- Fin nettoyage downloads incoming ---" >> "$LOG_FILE"
  echo >> "$LOG_FILE"

  # Construction du message Discord (multi-ligne propre)
  local msg="📂 Cleanup downloads (docker-ptr)

Date : $(timestamp)
Rétention : ${MIN_AGE_HOURS}h (7 jours)

Résumé par répertoire :"

  local i=0
  local n=${#DIRS[@]}
  while [ "$i" -lt "$n" ]; do
    msg+=$'\n'"${DIRS[$i]} :"
    msg+=$'\n'"  • avant     : ${sizes_before[$i]}"
    msg+=$'\n'"  • après     : ${sizes_after[$i]}"
    msg+=$'\n'"  • supprimés : ${deleted_counts[$i]}"
    i=$((i + 1))
  done

  msg+=$'\n\n'"Log complet en pièce jointe."

  send_discord "$msg" "$LOG_FILE"
}

main "$@"
