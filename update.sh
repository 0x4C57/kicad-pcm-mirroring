#!/bin/bash

function update_package(){
    # $1: name(Unused since can contain bad characters for files)
    # $2: version
    # $3: address; return file URL on server to target_url
    # assume the first entry in the `versions` array is latest, if not match then delete old file
    pkg_filename=`echo "$3" | sed -E 's/.+\/([a-zA-Z0-9\-_.]+)/\1/g'`  # Extract file name
    if [ -e "versions/$pkg_filename" ]; then
        last_ver=`cat "versions/$pkg_filename"`
        if [ "$last_ver" = "$2" ]; then
            return 0
        fi
    fi
    curl -L "$3" -o "pkg_tmp/$pkg_filename"  # Download
    target_url="https://mirrors.4c57.org/kicadpcm/packages/$pkg_filename"  # Return URL
    file_path="/www/wwwroot/mirrors.4c57.org/kicadpcm/packages/$pkg_filename"
    cp "pkg_tmp/$pkg_filename" "$file_path"  # Copy file to Web Server
    # Check for old file and remove it
    last_file_name=`cat "lastfilename/$pkg_filename"`
    if [ -f "lastfilename/$pkg_filename" -a -f "/www/wwwroot/mirrors.4c57.org/kicadpcm/packages/$last_file_name" ]; then
        cat "lastfilename/$pkg_filename" | xargs rm
    fi
    echo "$file_path" > "lastfilename/$pkg_filename"  # Write this file path
    echo "$2" > "versions/$pkg_filename"
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

# ================ Download packages =================

# Build bash commands for downloading
jq -r 'reduce .packages[] as $item (
    "";
    . + "update_package \""
      + $item.name + "\" \""
      + $item.versions[0].version + "\" \""
      + $item.versions[0].download_url + "\"\n"
)' packages.json > update_commands.tmp

# Insert package.json filter builder
echo "jq '." > filter.jq
idx=0
while IFS= read -r line; do
    [ -z "$line" ] && continue
    echo "$line" >> update_filtering_commands.tmp
    echo 'echo '"'"'| .packages['"$idx"'].versions[0].download_url|='"'""'"'"'"'"'"''$target_url''"'"'"'"'"'"' >> filter.jq' >> update_filtering_commands.tmp
    idx=`expr $idx + 1`
done < update_commands.tmp
echo 'echo ' '"'"'"'"''"'' packages.json > packages_new.json''"' " >> filter.jq" >> update_filtering_commands.tmp

source update_filtering_commands.tmp

source filter.jq

cp packages_new.json /www/wwwroot/mirrors.4c57.org/kicadpcm/metadata/packages.json

# Make new metadata
jq '. | .maintainer|={contact:{mail:"riogligo@qq.com"},name:"RigoLigo"} | .name|="4C57 Mirror of KiCad official repository" | .packages.url|="https://mirrors.4c57.org/kicadpcm/metadata/packages.json" | .resources.url|="https://mirrors.4c57.org/kicadpcm/metadata/resources.zip" | .packages.sha256|="'"`sha256sum packages_new.json | head -c 64`"'"' repo_tmp.json > repo_release.json

# Deploy metadata
cp repo_release.json /www/wwwroot/mirrors.4c57.org/kicadpcm/metadata/repository.json
cp resources.zip /www/wwwroot/mirrors.4c57.org/kicadpcm/metadata/

# =============== Deploy packages ===============
cp -f pkg_tmp/*.* /www/wwwroot/mirrors.4c57.org/kicadpcm/packages

# Clean
rm repo_tmp.json repo_release.json resources.zip packages.json packages_new.json
rm update_commands.tmp update_filtering_commands.tmp filter.jq
rm -r pkg_tmp
