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

# --- User-defined Minecraft versions ---
# Example in .env: MC_VERSION="1.7.10,1.8,1.12.2"
MC_VERSION_JSON=$(echo "$MC_VERSIONS" | tr -d ' ' | awk -F, '{for(i=1;i<=NF;i++){printf "\"%s\"%s",$i,(i<NF?",":"")}}')
MC_VERSION_JSON="[$MC_VERSION_JSON]"

# --- Construct Modrinth API facets dynamically ---
FACETS=$(jq -n --argjson versions "$MC_VERSION_JSON" '[[$versions[] | "versions:\(.)"], ["project_type:mod"]]' | jq -c .)

RESPONSE=$(curl -s -G \
        -H "User-Agent: Modrinth new mod watcher/69.0" \
        --data-urlencode "facets=$FACETS" \
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

  # --- Build Footer: Minecraft version + first modloader (entirely in jq) ---
  FOOTER=$(echo "$mod" | jq -r '
    .versions[0] as $mc_version
    |
    (.categories | map(select(test("fabric|forge|quilt|neo|rift|flint|loader|risugami|client|server"; "i"))) | .[0]) as $loader
    |
    if $loader then "\($mc_version) • \($loader)" else $mc_version end
    | if . == null or . == "" then "Various Minecraft Versions" else . end
  ')

  # --- Build Embed JSON ---
  EMBED=$(jq -n \
    --arg title "$NAME" \
    --arg description "$DESCRIPTION" \
    --arg url "$URL" \
    --arg timestamp "$CLEAN_DATE" \
    --arg icon_url "$ICON_URL" \
    --arg footer "$FOOTER" \
    '{
      "embeds": [
        {
          "title": $title,
          "description": $description,
          "url": $url,
          "timestamp": $timestamp,
          "color": 3066993,
          "thumbnail": { "url": $icon_url },
          "footer": {
            "text": $footer,
            "icon_url": "https://raw.githubusercontent.com/JackOfNoneTrades/ModWebhook/refs/heads/master/icons/modrinth.png"
          }
        }
      ]
    }'
  )

  # --- Send to each webhook URL from the file ---
  while read -r WEBHOOK_URL; do
    if [[ -n "$WEBHOOK_URL" ]]; then
      curl -s -H "Content-Type: application/json" \
           -X POST \
           -d "$EMBED" \
           "$WEBHOOK_URL"
    fi
  done < "$WEBHOOK_LIST"

  # Update persistence file
  echo "$TIMESTAMP" > "$PERSISTENCE_FILE"
done
