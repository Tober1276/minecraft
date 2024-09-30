#!/bin/bash
# shellcheck disable=SC2155
#
# Modrinth Installation Script
#
# Server Files: /mnt/server

: "${SERVER_DIR:=/mnt/server}"
: "${PROJECT_ID:=}"
: "${VERSION_ID:=}"

if [[ ! -d $SERVER_DIR ]]; then
    mkdir -p "$SERVER_DIR"
fi

if ! cd "$SERVER_DIR"; then
    echo -e "Failed to change directory to ${SERVER_DIR}"
    exit 1
fi

function install_required {
    echo -e "Installing required packages..."

    echo -e "\tRunning apt update"
    if ! apt update > /dev/null 2>&1; then
        echo -e "\tERROR: apt update failed!"
        exit 1
    fi

    echo -e "\tRunning apt install"
    if ! apt install -y wget jq unzip dos2unix > /dev/null 2>&1; then
        echo -e "\tERROR: apt install failed!"
        exit 1
    fi
}

MODRINTH_API_URL="https://api.modrinth.com/v2"

function get_download {
    echo -e "Retrieving Modrinth project information..."
    local PROJECT_DATA=$(wget -q "${MODRINTH_API_URL}/project/${PROJECT_ID}" -O -)
    local PROJECT_TITLE=$(echo "$PROJECT_DATA" | jq -r '.title // empty')
    local PROJECT_SUPPORTED=$(echo "$PROJECT_DATA" | jq -r '."server_side" // empty')

    if [[ -z "${PROJECT_DATA}" ]]; then
        echo -e "\tERROR: Failed to retrieve project data for project id '${PROJECT_ID}'"
        exit 1
    fi

    if [[ "${PROJECT_SUPPORTED}" == "unsupported" ]]; then
        echo -e "\tWARNING: The project '${PROJECT_TITLE}' is listed as unsupported for server use. Continuing anyway..."
    fi

    if [[ -z "${VERSION_ID}" || "${VERSION_ID}" == "latest" ]]; then
        echo -e "\tNo version ID specified, using latest version"
        VERSION_ID=$(echo "$PROJECT_DATA" | jq -r '.versions[-1] // empty')
    else
        echo -e "\tChecking if provided version id '${VERSION_ID}' exists"
        if [[ $(echo "$PROJECT_DATA" | jq -r --arg VERSION_ID "$VERSION_ID" '.versions[]? | select(. == $VERSION_ID)') != "${VERSION_ID}" ]]; then
            echo -e "\tERROR: Version id '${VERSION_ID}' not found for project '${PROJECT_TITLE}'"
            exit 1
        fi
    fi

    if [[ -z "${VERSION_ID}" ]]; then
        echo -e "\tERROR: No version id found for project '${PROJECT_TITLE}'"
        exit 1
    fi

    # get json data to work with
    echo -e "\tRetrieving version information for '${VERSION_ID}'"
    local JSON_DATA=$(wget -q "${MODRINTH_API_URL}/version/${VERSION_ID}" -O -)

    if [[ -z "${JSON_DATA}" ]]; then
        echo -e "\tERROR: Failed to retrieve version data for version id '${VERSION_ID}'"
        exit 1
    fi

    echo -e "\tParsing Modrinth pack download url"

    local DOWNLOAD_URL=$(echo "$JSON_DATA" | jq -r '.files[]? | select(.primary == true) | .url')

    if [[ -z "${DOWNLOAD_URL}" ]]; then
        echo -e "\tERROR: No download url found for version ${VERSION_ID}"
        exit 1
    fi

    ## download modpack files
    echo -e "\tDownloading ${DOWNLOAD_URL}"
    if ! wget -q "${DOWNLOAD_URL}" -O server.zip; then
        echo -e "\tERROR: Failed to download modpack files!"
        exit 1
    fi
}

function unpack_zip {
    unzip -o server.zip
    rm -rf server.zip
}

function json_download_mods {
    echo "Downloading mods..."

    local MANIFEST="${SERVER_DIR}/modrinth.index.json"
    jq -c '.files[]? | select(.env.server == "required") | {name: .path, url: .downloads[0]}' "${MANIFEST}" | while read -r mod; do
        local FILE_URL=$(echo "${mod}" | jq -r '.url // empty')
        local FILE_NAME=$(echo "${mod}" | jq -r '.name // empty')

        if [[ -z "${FILE_URL}" ]]; then
            echo -e "\tERROR: No download url found for mod '${mod}'"
            exit 1
        fi

        echo -e "\tDownloading ${FILE_URL}"
        
        if ! wget -q "${FILE_URL}" -P "${SERVER_DIR}/mods"; then
            echo -e "\tERROR: Failed to download mod '${FILE_NAME}'"
            exit 1
        fi
    done
}

function json_download_overrides {
    echo "Copying overrides..."
    if [[ -d "${SERVER_DIR}/overrides" ]]; then
        echo -e "\tCopying shared overrides"
        chmod -R 755 "${SERVER_DIR}/overrides/"*
        cp -r "${SERVER_DIR}/overrides/"* "${SERVER_DIR}"
        rm -r "${SERVER_DIR}/overrides"
    fi

    if [[ -d "${SERVER_DIR}/server-overrides" ]]; then
        echo -e "\tCopying server overrides"
        chmod -R 755 "${SERVER_DIR}/server-overrides/"*
        cp -r "${SERVER_DIR}/server-overrides/"* "${SERVER_DIR}"
        rm -r "${SERVER_DIR}/server-overrides"
    fi
}

FORGE_INSTALLER_URL="https://maven.minecraftforge.net/net/minecraftforge/forge/"

function json_download_forge {
    echo "Downloading Forge..."

    local MANIFEST="${SERVER_DIR}/modrinth.index.json"

    local MC_VERSION=$(jq -r '.dependencies.minecraft // empty' "${MANIFEST}")
    local FORGE_VERSION=$(jq -r '.dependencies.forge // empty' "${MANIFEST}")

    if [[ -z "${MC_VERSION}" ]]; then
        echo -e "\tERROR: No Minecraft version found in manifest '${MANIFEST}'"
        exit 1
    fi

    if [[ -z "${FORGE_VERSION}" ]]; then
        echo -e "\tERROR: No Forge version found in manifest '${MANIFEST}'"
        exit 1
    fi

    FORGE_VERSION="${MC_VERSION}-${FORGE_VERSION}"
    if [[ "${MC_VERSION}" == "1.7.10" || "${MC_VERSION}" == "1.8.9" ]]; then
        FORGE_VERSION="${FORGE_VERSION}-${MC_VERSION}"
    fi

    local FORGE_JAR="forge-${FORGE_VERSION}.jar"
    if [[ "${MC_VERSION}" == "1.7.10" ]]; then
        FORGE_JAR="forge-${FORGE_VERSION}-universal.jar"
    fi

    local FORGE_URL="${FORGE_INSTALLER_URL}${FORGE_VERSION}/forge-${FORGE_VERSION}"

    echo -e "\tUsing Forge ${FORGE_VERSION} from ${FORGE_URL}"

    local FORGE_INSTALLER="${FORGE_URL}-installer.jar"
    echo -e "\tDownloading Forge Installer ${FORGE_VERSION} from ${FORGE_INSTALLER}"

    if ! wget -q -O forge-installer.jar "${FORGE_INSTALLER}"; then
        echo -e "\tERROR: Failed to download Forge Installer ${FORGE_VERSION}"
        exit 1
    fi

    rm -rf libraries/net/minecraftforge/forge/
    rm -f unix_args.txt

    echo -e "\tInstalling Forge Server ${FORGE_VERSION}"
    if ! java -jar forge-installer.jar --installServer > /dev/null 2>&1; then
        echo -e "\tERROR: Failed to install Forge Server ${FORGE_VERSION}"
        exit 1
    fi

    if [[ $MC_VERSION =~ ^1\.(17|18|19|20|21|22|23) || $FORGE_VERSION =~ ^1\.(17|18|19|20|21|22|23) ]]; then
        echo -e "\tDetected Forge 1.17 or newer version. Setting up Forge Unix arguments"
        ln -sf libraries/net/minecraftforge/forge/*/unix_args.txt unix_args.txt
    else
        mv "$FORGE_JAR" forge-server-launch.jar
        echo "forge-server-launch.jar" > ".serverjar"
    fi

    rm -f forge-installer.jar
}

FABRIC_INSTALLER_URL="https://meta.fabricmc.net/v2/versions/installer"

function json_download_fabric {
    echo "Downloading Fabric..."

    local MANIFEST="${SERVER_DIR}/modrinth.index.json"

    local MC_VERSION=$(jq -r '.dependencies.minecraft // empty' "${MANIFEST}")
    local FABRIC_VERSION=$(jq -r '.dependencies."fabric-loader" // empty' "${MANIFEST}")

    if [[ -z "${MC_VERSION}" ]]; then
        echo -e "\tERROR: No Minecraft version found in manifest '${MANIFEST}'"
        exit 1
    fi

    if [[ -z "${FABRIC_VERSION}" ]]; then
        echo -e "\tERROR: No Fabric version found in manifest '${MANIFEST}'"
        exit 1
    fi

    local INSTALLER_JSON=$(wget -q -O - ${FABRIC_INSTALLER_URL} )
    local INSTALLER_VERSION=$(echo "$INSTALLER_JSON" | jq -r '.[0].version // empty')
    local INSTALLER_URL=$(echo "$INSTALLER_JSON" | jq -r '.[0].url // empty')

    if [[ -z "${INSTALLER_VERSION}" ]]; then
        echo -e "\tERROR: No Fabric installer version found in manifest!"
        exit 1
    fi

    if [[ -z "${INSTALLER_URL}" ]]; then
        echo -e "\tERROR: No Fabric installer url found in manifest!"
        exit 1
    fi

    echo -e "\tDownloading Fabric Installer ${MC_VERSION}-${FABRIC_VERSION} (${INSTALLER_VERSION}) from ${INSTALLER_URL}"

    if ! wget -q -O fabric-installer.jar "${INSTALLER_URL}"; then
        echo -e "\tERROR: Failed to download Fabric Installer ${MC_VERSION}-${FABRIC_VERSION} (${INSTALLER_VERSION})"
        exit 1
    fi

    echo -e "\tInstalling Fabric Server ${MC_VERSION}-${FABRIC_VERSION} (${INSTALLER_VERSION})"
    if ! java -jar fabric-installer.jar server -mcversion "${MC_VERSION}" -loader "${FABRIC_VERSION}" -downloadMinecraft; then
        echo -e "\tERROR: Failed to install Fabric Server ${MC_VERSION}-${FABRIC_VERSION} (${INSTALLER_VERSION})"
        exit 1
    fi

    echo "fabric-server-launch.jar" > ".serverjar"

    rm -f fabric-installer.jar
}

QUILT_INSTALLER_URL="https://meta.quiltmc.org/v3/versions/installer"

function json_download_quilt {
    echo "Downloading Quilt..."

    local MANIFEST="${SERVER_DIR}/modrinth.index.json"

    local MC_VERSION=$(jq -r '.dependencies.minecraft // empty' "${MANIFEST}")
    local QUILT_VERSION=$(jq -r '.dependencies."quilt-loader" // empty' "${MANIFEST}")

    if [[ -z "${MC_VERSION}" ]]; then
        echo -e "\tERROR: No Minecraft version found in manifest!"
        exit 1
    fi

    if [[ -z "${QUILT_VERSION}" ]]; then
        echo -e "\tERROR: No Quilt version found in manifest!"
        exit 1
    fi

    local INSTALLER_JSON=$(wget -q -O - ${QUILT_INSTALLER_URL} )
    local INSTALLER_VERSION=$(echo "$INSTALLER_JSON" | jq -r '.[0].version // empty')
    local INSTALLER_URL=$(echo "$INSTALLER_JSON" | jq -r '.[0].url // empty')

    if [[ -z "${INSTALLER_JSON}" ]]; then
        echo -e "\tERROR: Failed to retrieve Quilt installer information from manifest!"
        exit 1
    fi

    if [[ -z "${INSTALLER_VERSION}" ]]; then
        echo -e "\tERROR: No Quilt installer version found in manifest!"
        exit 1
    fi

    if [[ -z "${INSTALLER_URL}" ]]; then
        echo -e "\tERROR: No Quilt installer URL found in manifest!"
        exit 1
    fi

    echo -e "\tDownloading Quilt Installer ${MC_VERSION}-${QUILT_VERSION} (${INSTALLER_VERSION}) from ${INSTALLER_URL}"

    if ! wget -q -O quilt-installer.jar "${INSTALLER_URL}"; then
        echo -e "\tERROR: Failed to download Quilt installer ${MC_VERSION}-${QUILT_VERSION} (${INSTALLER_VERSION})"
        exit 1
    fi

    echo -e "\tInstalling Quilt Server ${MC_VERSION}-${QUILT_VERSION} (${INSTALLER_VERSION})"
    if ! java -jar quilt-installer.jar install server "${MC_VERSION}" "${QUILT_VERSION}" --download-server --install-dir=./; then
        echo -e "\tERROR: Failed to install Quilt Server ${MC_VERSION}-${QUILT_VERSION} (${INSTALLER_VERSION})"
        exit 1
    fi

    echo "quilt-server-launch.jar" > ".serverjar"

    rm quilt-installer.jar
}

NEOFORGE_INSTALLER_URL="https://maven.neoforged.net/releases/net/neoforged/neoforge/"

function json_download_neoforge {
    echo "Downloading NeoForge..."

    local MANIFEST="${SERVER_DIR}/modrinth.index.json"

    local MC_VERSION=$(jq -r '.dependencies.minecraft // empty' "${MANIFEST}")
    local NEOFORGE_VERSION=$(jq -r '.dependencies.neoforge // empty' "${MANIFEST}")

    if [[ -z "${MC_VERSION}" ]]; then
        echo -e "\tERROR: No Minecraft version found in manifest '${MANIFEST}'"
        exit 1
    fi

    if [[ -z "${NEOFORGE_VERSION}" ]]; then
        echo -e "\tERROR: No NeoForge version found in manifest '${MANIFEST}'"
        exit 1
    fi

    local DOWNLOAD_LINK
    local ARTIFACT_NAME

    # The 1.20.1 release lives in a different repository and is called "forge" instead of "neoforge"
    if [[ "${MC_VERSION}" == "1.20.1" ]]; then
        DOWNLOAD_LINK="https://maven.neoforged.net/releases/net/neoforged/forge/${MC_VERSION}-${NEOFORGE_VERSION}/forge-${MC_VERSION}-${NEOFORGE_VERSION}"
        ARTIFACT_NAME="forge"
    else
        DOWNLOAD_LINK="https://maven.neoforged.net/releases/net/neoforged/neoforge/${NEOFORGE_VERSION}/neoforge-${NEOFORGE_VERSION}"
        ARTIFACT_NAME="neoforge"
    fi

    echo -e "\tDownloading NeoForge Installer ${NEOFORGE_VERSION} from ${DOWNLOAD_LINK}-installer.jar"

    if ! wget -q -O neoforge-installer.jar "${DOWNLOAD_LINK}-installer.jar"; then
        echo -e "\tERROR: Failed to download NeoForge Installer ${NEOFORGE_VERSION}"
        exit 1
    fi

    # Remove old NeoForge files so we can safely update
    rm -rf libraries/net/neoforged/${ARTIFACT_NAME}/
    rm -f unix_args.txt

    # Install the NeoForge server
    echo -e "\tInstalling NeoForge Server ${NEOFORGE_VERSION}"
    if ! java -jar neoforge-installer.jar --installServer > /dev/null 2>&1; then
        echo -e "\tERROR: Failed to install NeoForge Server ${NEOFORGE_VERSION}"
        exit 1
    fi

    # Symlink the startup arguments to the server directory
    echo -e "\tSetting up NeoForge Unix arguments"
    ln -sf libraries/net/neoforged/${ARTIFACT_NAME}/*/unix_args.txt unix_args.txt

    rm -f neoforge-installer.jar
}

install_required

if [[ -z "${PROJECT_ID}" ]]; then
    echo "ERROR: You must specify a PROJECT_ID environment variable!"
    exit 1
fi

if [[ ! "${PROJECT_ID}" = "zip" ]]; then
	get_download
	unpack_zip
else
	unpack_zip
fi

if [[ -f "${SERVER_DIR}/modrinth.index.json" ]]; then
    echo "Found modrinth.index.json, installing mods"
    json_download_mods
    json_download_overrides
fi

if [[ -f "${SERVER_DIR}/modrinth.index.json" ]]; then
    MANIFEST="${SERVER_DIR}/modrinth.index.json"

    if [[ $(jq -r '.dependencies.forge' "${MANIFEST}") != "null" ]]; then
        json_download_forge
    fi

    if [[ $(jq -r '.dependencies."fabric-loader"' "${MANIFEST}") != "null" ]]; then
        json_download_fabric
    fi

    if [[ $(jq -r '.dependencies."quilt-loader"' "${MANIFEST}") != "null" ]]; then
        json_download_quilt
    fi
    
    if [[ $(jq -r '.dependencies."neoforge"' "${MANIFEST}") != "null" ]]; then
        json_download_neoforge
    fi
fi

echo -e "\nInstall completed succesfully, enjoy!"