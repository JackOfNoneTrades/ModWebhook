#!/bin/bash

export $(grep -v '^#' .env | xargs)

# --- Configuration ---
PERSISTENCE_FILE="$LAST_UPDATED_MODRINTH"
MODRINTH_API="https://api.modrinth.com/v2/search"
LIMIT=$MOD_LIMIT

# --- Initial Setup ---
if [ ! -f "$PERSISTENCE_FILE" ]; then
  echo 0 > "$PERSISTENCE_FILE"
fi

LAST_TIMESTAMP=$(cat "$PERSISTENCE_FILE")

# --- Construct Modrinth API Query for Minecraft 1.7.10 ---
QUERY=$(jq -nc \
  --argjson facets '[["versions:1.7.10"], ["project_type:mod"]]' \
  --arg index "newest" \
  --arg limit "$LIMIT" \
  '{facets: $facets, index: $index, limit: ($limit | tonumber)}')

RESPONSE=$(curl -s -G \
        -H "User-Agent: Modrinth new mod watcher/69.0" \
        --data-urlencode "facets=$(echo "$QUERY" | jq -r '.facets | @json')" \
                 --data-urlencode "index=newest" \
                 --data-urlencode "limit=$LIMIT" \
                 "$MODRINTH_API")

# --- Parse and Filter New Mods ---
NEW_MODS=$(echo "$RESPONSE" | jq --argjson last "$LAST_TIMESTAMP" '
  .hits
  | map(select(.date_created | sub("\\.\\d+"; "") | fromdateiso8601 > $last))
  | sort_by(.date_created)
')

# Exit if no new mods
if [ "$(echo "$NEW_MODS" | jq length)" -eq 0 ]; then
  echo "No new mods found."
  exit 0
fi

# --- Post Each New Mod to Discord ---
echo "$NEW_MODS" | jq -c '.[]' | while read -r mod; do
  NAME=$(echo "$mod" | jq -r '.title')
  DESCRIPTION=$(echo "$mod" | jq -r '.description // "No description."')
  URL="https://modrinth.com/mod/$(echo "$mod" | jq -r '.slug')"
  RAW_DATE=$(echo "$mod" | jq -r '.date_created')
  CLEAN_DATE=$(echo "$RAW_DATE" | sed 's/\.[0-9]\+//') # Remove fractional seconds
  TIMESTAMP=$(date --date="$CLEAN_DATE" +%s)
  ICON_URL=$(echo "$mod" | jq -r '.icon_url // ""')

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
          "color": 3066993,
          "thumbnail": {
            "url": $icon_url
          },
	  "author": {
		"text": "Modrinth",
		"icon_url": "https://pt.minecraft.wiki/images/thumb/Socials_Modrinth.png/280px-Socials_Modrinth.png"
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
  done < "$WEBHOOK_LIST"

  echo "$TIMESTAMP" > "$PERSISTENCE_FILE"
done
