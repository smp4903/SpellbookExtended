#!/bin/sh
# Fetches the three data sources and regenerates Data/<Class>.lua.
set -e
cd "$(dirname "$0")"
mkdir -p .sources
cd .sources
for repo in MAF2414/wow-forever-talents alcaras/forever-ref fusionpit/WhatsTraining; do
    name=${repo#*/}
    if [ -d "$name" ]; then
        git -C "$name" pull -q --ff-only
    else
        git clone -q --depth 1 "https://github.com/$repo.git"
    fi
done
cd ..
items=$(ls .sources/forever-ref/builds/*.json.gz | sort | tail -n 1)
python3 build_data.py \
    --forever .sources/wow-forever-talents/docs/index.html \
    --items "$items" \
    --wt .sources/WhatsTraining/Classes/Vanilla \
    "$@"
