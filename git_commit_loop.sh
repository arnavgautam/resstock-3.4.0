#!/bin/bash

# List of strings (e.g., folder names or file prefixes)
# items=("folder1" "folder2" "folder3")

for item in {3101..8000}; do
  echo "Processing: $item"

  # Add files that match the string (e.g., folder1*, folder2*)
  git add "national_ASHP_8000_all_unit_residence/run${item}/"*
  git add "national_ASHP_8000_all_unit_residence_ASHP/run${item}/"*

  if ((item%100==0)); then
    # Only commit if there are staged changes
    if git diff --cached --quiet; then
        echo "No changes to commit for $item"
    else
        git commit -m "Add until national_ASHP_8000_all_unit_residence/run$item"
        git push
    fi
  fi
done