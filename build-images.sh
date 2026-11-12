#!/bin/bash

#
# Copyright (C) 2026 Nethesis S.r.l.
# SPDX-License-Identifier: GPL-3.0-or-later
#

# Terminate on error
set -e

# Prepare variables for later use
images=()
# The image will be pushed to GitHub container registry
repobase="${REPOBASE:-ghcr.io/nethserver}"
# Configure the image name
reponame="privatebin"
# Node.js 25+ no longer ships Corepack, install it from npm
# renovate: datasource=npm packageName=corepack
corepack_version=0.36.0
privatebin_image="docker.io/privatebin/nginx-fpm-alpine:2.1.1"
auth_image="${repobase}/${reponame}-auth"

# Show the PrivateBin version in the About page, restore the metadata on exit
metadata_file="ui/public/metadata.json"
metadata_backup=$(mktemp)
cleanup() {
    cp "${metadata_backup}" "${metadata_file}"
    rm -f "${metadata_backup}"
}
cp "${metadata_file}" "${metadata_backup}"
trap cleanup EXIT
jq --arg v "${privatebin_image##*:}" \
   '.upstream_name |= gsub("version set automatically"; $v)' \
   "${metadata_file}" > "${metadata_file}.tmp" && mv "${metadata_file}.tmp" "${metadata_file}"

# Build the LDAP login sidecar
buildah build --layers --force-rm --tag "${auth_image}" auth-app
images+=("${auth_image}")

# Create a new empty container image
container=$(buildah from scratch)

# Reuse existing nodebuilder-privatebin container, to speed up builds
if ! buildah containers --format "{{.ContainerName}}" | grep -q nodebuilder-privatebin; then
    echo "Pulling NodeJS runtime..."
    buildah from --name nodebuilder-privatebin -v "${PWD}:/usr/src:Z" docker.io/library/node:26.13.0-slim
    buildah run nodebuilder-privatebin sh -c "npm install -g corepack@${corepack_version} && corepack enable"
fi

echo "Build static UI files with node..."
buildah run \
    --workingdir=/usr/src/ui \
    --env="NODE_OPTIONS=--openssl-legacy-provider" \
    nodebuilder-privatebin \
    sh -c "yarn install && yarn build"

# Add imageroot directory to the container image
buildah add "${container}" imageroot /imageroot
buildah add "${container}" ui/dist /ui

buildah config --entrypoint=/ \
    --label="org.nethserver.authorizations=traefik@node:routeadm cluster:accountconsumer" \
    --label="org.nethserver.tcp-ports-demand=1" \
    --label="org.nethserver.rootfull=0" \
    --label="org.nethserver.min-core=3.20.1" \
    --label="org.nethserver.images=${privatebin_image} ${auth_image}:${IMAGETAG:-latest}" \
    --label="org.nethserver.volumes=privatebin-data" \
    "${container}"
# Commit the image
buildah commit "${container}" "${repobase}/${reponame}"

# Append the image URL to the images array
images+=("${repobase}/${reponame}")

#
# NOTICE:
#
# It is possible to build and publish multiple images.
#
# 1. create another buildah container
# 2. add things to it and commit it
# 3. append the image url to the images array
#

#
# Setup CI when pushing to Github. 
# Warning! docker::// protocol expects lowercase letters (,,)
if [[ -n "${CI}" ]]; then
    # Set output value for Github Actions
    printf "images=%s\n" "${images[*],,}" >> "${GITHUB_OUTPUT}"
else
    # Just print info for manual push
    printf "Publish the images with:\n\n"
    for image in "${images[@],,}"; do printf "  buildah push %s docker://%s:%s\n" "${image}" "${image}" "${IMAGETAG:-latest}" ; done
    printf "\n"
fi
