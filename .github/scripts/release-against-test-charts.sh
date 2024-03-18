#!/bin/bash
#
# Submit new Fleet version against a test fork of rancher/charts

set -ue

PREV_FLEET_VERSION="$1"   # e.g. 0.5.2-rc.3
NEW_FLEET_VERSION="$2"
PREV_CHART_VERSION="$3"   # e.g. 101.2.0
NEW_CHART_VERSION="$4"
UUID="$5" 		  # for ttl.sh image resolution

if [ -z "${GITHUB_WORKSPACE:-}" ]; then
    CHARTS_DIR="$(dirname -- "$0")/../../../charts"
else
    CHARTS_DIR="${GITHUB_WORKSPACE}/charts"
fi

pushd "${CHARTS_DIR}" > /dev/null

if [ ! -e ~/.gitconfig ]; then
    git config --global user.name "fleet-bot"
    git config --global user.email fleet@suse.de
fi

if [ ! -f bin/charts-build-scripts ]; then
    make pull-scripts
fi

if grep -q "version: ${PREV_CHART_VERSION}" ./packages/fleet/fleet/package.yaml && grep -q "${PREV_FLEET_VERSION}" ./packages/fleet/fleet/package.yaml; then

    find ./packages/fleet/ -type f -exec sed -i -e "s/${PREV_FLEET_VERSION}/${NEW_FLEET_VERSION}/g" {} \;
    find ./packages/fleet/ -type f -exec sed -i -e "s/version: ${PREV_CHART_VERSION}/version: ${NEW_CHART_VERSION}/g" {} \;
else
    echo "Previous Fleet version references do not exist in ./packages/fleet/ so replacing it with the new version is not possible. Exiting..."
    exit 1
fi

for i in fleet fleet-crd fleet-agent; do
    yq --inplace "del( .${i}.[] | select(. == \"${PREV_CHART_VERSION}+up${PREV_FLEET_VERSION}\") )" release.yaml
    yq --inplace ".${i} += [\"${NEW_CHART_VERSION}+up${NEW_FLEET_VERSION}\"]" release.yaml
done

git add packages/fleet release.yaml
git commit -m "Updating to Fleet v${NEW_FLEET_VERSION}"

NEW_FULL_VERSION=${NEW_CHART_VERSION}+up${NEW_FLEET_VERSION}

for suffix in '' '-agent' '-crd'; do
    chart_dir=charts/fleet$suffix/${NEW_FULL_VERSION}
    mkdir -p $chart_dir
    cp -r ../fleet/charts/fleet$suffix/* $chart_dir
    cd $chart_dir

    sed -i \
      -e "s@repository:.*@repository: ttl.sh/rancher-fleet$suffix-$UUID@" \
      -e "s/tag:.*/tag: 1h/" \
      values.yaml

    cd -

    helm package \
        --version="$NEW_FULL_VERSION" \
        --app-version="$NEW_FLEET_VERSION" \
        -d ./assets/fleet$suffix \
        $chart_dir
done

make index # Merge new chart entries into `index.yaml`

git add assets/fleet* charts/fleet* index.yaml
git commit -m "Autogenerated changes for Fleet v${NEW_FLEET_VERSION}"

popd > /dev/null
