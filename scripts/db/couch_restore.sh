#!/bin/bash

cd ~/Desktop/Master/couchdb_backup

for file in *_backup.json; do
  db=$(basename "$file" _backup.json)

  echo "Processing $db..."

  curl -s -u admin:Welcom3! -X DELETE "http://localhost:5984/$db" > /dev/null
  curl -s -u admin:Welcom3! -X PUT "http://localhost:5984/$db"

  count=$(jq '.rows | length' "$file")

  if [ "$count" -eq 0 ]; then
    echo "Skipping $db (no docs)"
    continue
  fi

  jq '{docs: [.rows[].doc], new_edits: false}' "$file" | \
  curl -s -u admin:Welcom3! \
       -H "Content-Type: application/json" \
       -X POST "http://localhost:5984/$db/_bulk_docs" \
       -d @-

  echo "Restored $db ($count docs)"
done