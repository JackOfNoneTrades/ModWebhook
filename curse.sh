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

MC_VERSIONS_JSON=$(echo "$MC_VERSIONS" | tr -d ' ' | awk -F, '{for(i=1;i<=NF;i++){printf "\"%s\"%s",$i,(i<NF?",":"")}}')
MC_VERSIONS_JSON="[$MC_VERSIONS_JSON]"

# --- Fetch Mods from CurseForge ---
RESPONSE=$(curl -s \
  -H "Accept: application/json" \
  -H "x-api-key: $CURSE_TOKEN" \
  -G "$CURSE_API" \
  --data-urlencode "classId=6" \
  --data-urlencode "gameId=432" \
  --data-urlencode "gameVersions=$MC_VERSIONS_JSON" \
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

  # --- Extract Minecraft version ---
  MC_VERSION=$(echo "$mod" | jq -r '
    .latestFiles[0].gameVersions
    | map(select(
        test("(?i)fabric|forge|quilt|neoforge|rift|flint|loader|modloader|client|server") | not
      ))
    | .[0] // "Various Minecraft Versions"
  ')

  MODLOADER=$(echo "$mod" | jq -r '
    .latestFiles[0].gameVersions
    | map(select(
        test("(?i)fabric|forge|quilt|neoforge|rift|flint|risugami")
      ))
    | .[0] // ""
  ')

  if [ -n "$MODLOADER" ]; then
    FOOTER="$MC_VERSION • $MODLOADER"
  else
    FOOTER="$MC_VERSION"
  fi

  # --- Check for MCreator category ---
  IS_MCREATOR=$(echo "$mod" | jq -r '.categories | map(.name) | index("MCreator")')

  # Build Embed JSON
  EMBED=$(jq -n \
    --arg title "$NAME" \
    --arg description "$DESCRIPTION" \
    --arg url "$URL" \
    --arg timestamp "$CLEAN_DATE" \
    --arg icon_url "$ICON_URL" \
    --arg footer "$FOOTER" \
    --argjson is_mcreator "$IS_MCREATOR" \
    '{
      "embeds": [
        {
          "title": $title,
          "description": $description,
          "url": $url,
          "timestamp": $timestamp,
          "color": 15844367,
          "thumbnail": { "url": $icon_url },
          "footer": { "text": $footer, "icon_url": "https://raw.githubusercontent.com/JackOfNoneTrades/ModWebhook/refs/heads/master/icons/curse.png" },
          "fields": (if $is_mcreator != null then [
            { "name": "Warning", "value": "⚠️ This mod was made using **MCreator**" }
          ] else [] end)
        }
      ]
    }'
  )

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
