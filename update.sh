#!/bin/bash

function update_package(){
    # $1: name $2: version $3: address; return file URL on server to target_url
    # assume the first entry in the `versions` array is latest, if not match then delete old file
    if [ -e "versions/$1" ]; then
        last_ver=`cat "versions/$1"`
        if [ $[last_ver] -eq $2 ]; then
            return 0
        fi
    fi
    pkg_filename=`echo "$3" | sed -E 's/.+\/([a-zA-Z0-9\-_.]+)/\1/g'`  # Extract file name
    curl -L "$3" -o "pkg_tmp/$pkg_filename"  # Download
    target_url="https://mirrors.4c57.org/kicadpcm/packages/$pkg_filename"  # Return URL
    file_path="/www/mirrors.4c57.org/kicadpcm/packages/$pkg_filename"
    cp "pkg_tmp/$pkg_filename" "$file_path"  # Copy file to Web Server
    # Check for old file and remove it
    if [ -f "lastfilename/$1" -a -f "/www/mirrors.4c57.org/kicadpcm/packages/`cat lastfilename/$1`" ]; then
        cat "lastfilename/$1" | xargs rm
    fi
    echo "$file_path" > "lastfilename/$1"  # Write this file path
    echo "$2" > "versions/$1"
}

# Ensure versions & lastfilename directory exists and isn't a fucking file
[ -f versions ]   && rm    versions
[ ! -e versions ] && mkdir versions
[ -f lastfilename ]   && rm    lastfilename
[ ! -e lastfilename ] && mkdir lastfilename

# Ensure pkg_tmp directory exists
mkdir pkg_tmp

curl 'https://gitlab.com/kicad/addons/repository/-/raw/main/repository.json' -o repo_tmp.json
[ $? -ne $[0] ] && exit 10

# If the file has not changed, exit the script
if [ -e repo_last.json ]; then
    diff repo_tmp.json repo_last.json
    [ $? -eq $[0] ] && rm repo_tmp.json; exit 0
fi

rm repo_last.json
cp repo_tmp.json repo_last.json

# Download packages
curl -L `jq -r '.packages.url' repo_tmp.json` -o packages.json
[ $? -ne $[0] ] && exit 20

# Download resources
curl -L `jq -r '.resources.url' repo_tmp.json` -o resources.zip
[ $? -ne $[0] ] && exit 30

# TODO: verify

# Make new metadata
jq '. | .maintainer|={contact:{mail:"riogligo@qq.com"},name:"RigoLigo"} | .name|="4C57 Mirror of KiCad official repository" | .packages.url|="https://mirrors.4c57.org/kicadpcm/metadata/packages.json" | .resources.url|="https://mirrors.4c57.org/kicadpcm/metadata/resources.zip"' repo_tmp.json > repo_release.json

# Deploy
cp repo_release.json /www/wwwroot/mirrors.4c57.org/kicadpcm/metadata/repository.json
cp resources.zip packages.json /www/wwwroot/mirrors.4c57.org/kicadpcm/metadata/

# Clean
rm repo_tmp.json repo_release.json resources.zip packages.json
