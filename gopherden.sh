#!/bin/bash

# A shell script for Go that does the following:
# 1. Installs versions of Go
# 2. Uninstall versions of Go
# 3. Switch between  installed versions of Go

install_go() {
    # Fetch all versions from the Golang website
    versions=$(gum spin --spinner dot --show-output --title "Grabing Go versions" -- curl -s https://go.dev/dl/ | grep -oE "go[0-9]+\.[0-9]+(\.[0-9]+)?\w*" | sort -u)

    # create an empty list of minor versions and major versions
    minor_versions=()
    major_versions=()

    # Iterate over the versions and determine which are major versions and which are minor versions
    for version in $versions; do
        if [[ $version == *.*.* ]] || [[ $version == *.*.*[a-zA-Z]* ]] || [[ $version == *.*[a-zA-Z]* ]]; then
            last_dot=$(expr index "$version" .)
            minor_versions+=("$version")
        else
            major_versions+=("$version")
            if [[ " ${minor_versions[@]} " =~ " $version " ]]; then
                minor_versions=("${minor_versions[@]/$version}")
            fi
        fi
    done

    # Double check that the minor versions list does not contain any major versions
    for minor_version in ${minor_versions[@]}; do
        if [[ $minor_version == *.*.*[a-zA-Z]* ]] || [[ $minor_version == *.*[a-zA-Z]* ]] || [[ $minor_version == *.*.* ]] || [[ $minor_version == *.* ]]; then
            version_before_letters=$(echo $minor_version | grep -oE "go[0-9]+\.[0-9]+")
            if [[ ! " ${major_versions[@]} " =~ " $version_before_letters " ]]; then
                major_versions+=("$minor_version")
                minor_versions=("${minor_versions[@]/$minor_version}")
            fi
        fi
        
    done    

    #sort the lists
    IFS=$'\n' minor_versions=($(sort -rV <<<"${minor_versions[*]}"))
    unset IFS
    IFS=$'\n' major_versions=($(sort -rV <<<"${major_versions[*]}"))
    unset IFS

    # Create a string of the major versions for gum choose
    major_versions_string=$(printf "%s " "${major_versions[@]}")
    major_versions_string="${major_versions_string%?}"
    while true; do
        major_version=$(gum choose $major_versions_string) 
        filtered_minor_versions=""

        # Create the string for gum choose again but for the minor versions this time
        for minor_version in "${minor_versions[@]}"; do
            if [[ $minor_version == $major_version* ]]; then
                filtered_minor_versions+="$minor_version "
            fi
        done

        filtered_minor_versions+="$major_version "
        filtered_minor_versions="${filtered_minor_versions%?}"

        # resort filtered_minor_versions
        IFS=$'\n' filtered_minor_versions=($(sort -rV <<<"${filtered_minor_versions[*]}"))
        unset IFS 

        # add "BACK" to the end of the list
        filtered_minor_versions+=" BACK"


        if [[ -z $filtered_minor_versions ]]; then
            final_version=$major_version
        elif [[ $filtered_minor_versions == $major_version ]]; then
            final_version=$major_version
        else
            final_version=$(gum choose $filtered_minor_versions)
        fi
        if [[ $final_version == "BACK" ]]; then
            continue
        else
            break
        fi
    done

    # check if ~/.gopherden directory exists. if it does not, create it
    if [ ! -d ~/.gopherden ]; then
        mkdir ~/.gopherden
    fi

    # check if final_version is empty
    if [[ -z $final_version ]]; then
        echo "No version selected to uninstall. Exiting..."
        exit
    fi

    gum spin --spinner points --title "Downloading https://go.dev/dl/$final_version.linux-amd64.tar.gz" -- wget -q https://go.dev/dl/$final_version.linux-amd64.tar.gz -P ~/.gopherden
    gum spin --spinner points --title "Extracting $final_version.linux-amd64.tar.gz" -- mkdir -p ~/.gopherden/$final_version && tar -xzf ~/.gopherden/$final_version.linux-amd64.tar.gz -C ~/.gopherden/$final_version --strip-components=1 go && rm ~/.gopherden/$final_version.linux-amd64.tar.gz


    # extract the tarball to ~/.gopherden and name it the version number
    # We want to avoid append the export to the end of the file
    # instead, we can search for the line that contains the export and replace it with the new export
    # this will allow the user to change the version of golang they are using by changing the export

    # first, check if the export exists
    if grep -q "export GOROOT" ~/.bashrc; then
        sed -i "s|export GOROOT.*|export GOROOT='$HOME/.gopherden/$final_version'|" ~/.bashrc
    else
        echo "export GOROOT='$HOME/.gopherden/$final_version'" >> ~/.bashrc
    fi

    # export PATH too but make sure to not just replace each PATH line with the new one, only fine line
    # that contains the export PATH and .gopherden
    if grep -q "export PATH.*.gopherden" ~/.bashrc; then
        sed -i "s|export PATH.*.gopherden.*|export PATH='$HOME/.gopherden/$final_version/bin':\$PATH|" ~/.bashrc
    else
        echo "export PATH='$HOME/.gopherden/$final_version/bin':\$PATH" >> ~/.bashrc
    fi

}

change_go_path() { 
    if grep -q "export GOROOT" ~/.bashrc; then
        current_version=$(grep "export GOROOT" ~/.bashrc | sed 's|export GOROOT=||' | sed "s|'$HOME/.gopherden/||" | sed "s|'||")
        
    else
        echo "No version of Go in PATH. Exiting..."
        exit
    fi
    echo "Current version of Go in PATH: $current_version"

    # ask which version of go to change the path for
    version=$(gum input --placeholder "go1.19.5")
    if [[ -z $version ]]; then
        # if so, exit the script
        echo "No version selected to change path. Exiting..."
        exit
    fi

    # if there is not, exit the script
    if [ ! -d ~/.gopherden/$version ]; then
        echo "No version of Go installed with the version number $version. Maybe you haven't install it yet..."
        exit
    fi

    echo "Changing $current_version to $version"

    if grep -q "export GOROOT" ~/.bashrc; then
        sed -i "s|export GOROOT.*|export GOROOT='$HOME/.gopherden/$version'|" ~/.bashrc
    else
        echo "export GOROOT='$HOME/.gopherden/$version'" >> ~/.bashrc
    fi

    # export PATH too but make sure to not just replace each PATH line with the new one, only fine line
    # that contains the export PATH and .gopherden
    if grep -q "export PATH.*.gopherden" ~/.bashrc; then
        sed -i "s|export PATH.*.gopherden.*|export PATH='$HOME/.gopherden/$version/bin':\$PATH|" ~/.bashrc
    else
        echo "export PATH='$HOME/.gopherden/$version/bin':\$PATH" >> ~/.bashrc
    fi
}

uninstall_go(){
    # get all the currently installed versions of go
    installed_versions=$(ls ~/.gopherden)
    # if the length of installed_versions is greater or equal to 1, then there is at least one version installed
    if [[ ${#installed_versions[@]} -ge 1  && ${installed_versions[0]} != "" ]]; then
        uninstall_version=$(gum choose $installed_versions)
        # if uninstall_version is empty exit
        if [[ -z $uninstall_version ]]; then
            echo "No version selected. Exiting..."
            exit
        fi
        # uninstall the version and remove the GOROOT and PATH exports
        confirm=$(gum confirm "Uninstall?") && echo "Uninstalling $uninstall_version..." && rm -rf ~/.gopherden/$uninstall_version && sed -i "/export GOROOT.*$uninstall_version/d" ~/.bashrc && sed -i "/export PATH.*$uninstall_version/d" ~/.bashrc || echo "Uninstall cancelled, exiting..." && exit
    else
        echo "No versions of Go installed. Exiting..."
        exit
    fi
}

choose_option() {
    # use gum choose to ask the user for which option to use
    option=$(gum choose "Install Go" "Uninstall Go" "Change Go Path")

      if [[ $option == "Install Go" ]]; then
        install_go
    elif [[ $option == "Change Go Path" ]]; then
        change_go_path
    elif [[ $option == "Uninstall Go" ]]; then
        uninstall_go
    fi
}

choose_option