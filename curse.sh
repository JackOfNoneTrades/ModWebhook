#!/bin/bash

export $(grep -v '^#' .env | xargs)

# --- Configuration ---
WEBHOOKS_FILE="$WEBHOOK_LIST"
PERSISTENCE_FILE="$LAST_UPDATED_CURSE"
CURSE_API="https://api.curseforge.com/v1/mods/search"
LIMIT=$MOD_LIMIT

# --- Initial Setup ---
if [ ! -f "$PERSISTENCE_FILE" ]; then
  echo 0 > "$PERSISTENCE_FILE"
fi

LAST_TIMESTAMP=$(cat "$PERSISTENCE_FILE")

# --- Fetch Mods from CurseForge ---
RESPONSE=$(curl -s \
  -H "Accept: application/json" \
  -H "x-api-key: $CURSE_TOKEN" \
  -G "$CURSE_API" \
  --data-urlencode "gameId=432" \
  --data-urlencode "gameVersion=1.7.10" \
  --data-urlencode "sortField=11" \
  --data-urlencode "sortOrder=desc" \
  --data-urlencode "pageSize=$LIMIT"
)

# --- Parse and Filter New Mods by Creation Date ---
NEW_MODS=$(echo "$RESPONSE" | jq --argjson last "$LAST_TIMESTAMP" '
  .data
  | map(select(.dateCreated != null))
  | map(select(.dateCreated | sub("\\.\\d+"; "") | fromdateiso8601 > $last))
  | sort_by(.dateCreated)
')

# Exit if no new mods
if [ "$(echo "$NEW_MODS" | jq length)" -eq 0 ]; then
  echo "No new CurseForge mods found."
  exit 0
fi

# --- Post Each New Mod to Discord ---
echo "$NEW_MODS" | jq -c '.[]' | while read -r mod; do
  NAME=$(echo "$mod" | jq -r '.name')
  DESCRIPTION=$(echo "$mod" | jq -r '.summary // "No description."')
  SLUG=$(echo "$mod" | jq -r '.slug')
  URL="https://www.curseforge.com/minecraft/mc-mods/$SLUG"
  RAW_DATE=$(echo "$mod" | jq -r '.dateCreated')
  CLEAN_DATE=$(echo "$RAW_DATE" | sed 's/\.[0-9]\+//') # Remove fractional seconds
  TIMESTAMP=$(date --date="$CLEAN_DATE" +%s)
  ICON_URL=$(echo "$mod" | jq -r '.logo.thumbnailUrl // ""')

  # Build Embed JSON
  EMBED=$(jq -n \
    --arg title "$NAME" \
    --arg description "$DESCRIPTION" \
    --arg url "$URL" \
    --arg timestamp "$CLEAN_DATE" \
    --arg icon_url "$ICON_URL" \
    '{
      "embeds": [
        {
          "title": $title,
          "description": $description,
          "url": $url,
          "timestamp": $timestamp,
          "color": 15844367,
          "thumbnail": {
            "url": $icon_url
          }
        }
      ]
    }')

  # Send to each webhook URL from the file
  while read -r WEBHOOK_URL; do
    if [[ -n "$WEBHOOK_URL" ]]; then
      curl -s -H "Content-Type: application/json" \
           -X POST \
           -d "$EMBED" \
           "$WEBHOOK_URL"
    fi
  done < "$WEBHOOKS_FILE"

  echo "$TIMESTAMP" > "$PERSISTENCE_FILE"
done
