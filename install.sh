#!/bin/bash

# exit on fail
set -e

#chromebrew directories
: "${OWNER:=skycocker}"
: "${REPO:=chromebrew}"
: "${BRANCH:=master}"
URL="https://raw.githubusercontent.com/${OWNER}/${REPO}/${BRANCH}"
: "${CREW_PREFIX:=/usr/local}"
CREW_LIB_PATH="${CREW_PREFIX}/lib/crew"
CREW_CONFIG_PATH="${CREW_PREFIX}/etc/crew"
CREW_BREW_DIR="${CREW_PREFIX}/tmp/crew"
CREW_DEST_DIR="${CREW_BREW_DIR}/dest"
CREW_PACKAGES_PATH="${CREW_LIB_PATH}/packages"
: "${CURL:=/usr/bin/curl}"
: "${CREW_CACHE_DIR:=$CREW_PREFIX/tmp/packages}"
# For container usage, where we want to specify i686 arch
# on a x86_64 host by setting ARCH=i686.
: "${ARCH:=$(uname -m)}"
# For container usage, when we are emulating armv7l via linux32
# uname -m reports armv8l.
ARCH="${ARCH/armv8l/armv7l}"

# BOOTSTRAP_PACKAGES cannot depend on crew_profile_base for their core operations (completion scripts are fine)
BOOTSTRAP_PACKAGES="musl_zstd pixz ca_certificates git gmp ncurses xxhash lz4 popt libyaml openssl zstd rsync ruby"

# Add musl bin to path
PATH=/usr/local/share/musl/bin:$PATH

RED='\e[1;91m';    # Use Light Red for errors.
YELLOW='\e[1;33m'; # Use Yellow for informational messages.
GREEN='\e[1;32m';  # Use Green for success messages.
BLUE='\e[1;34m';   # Use Blue for intrafunction messages.
GRAY='\e[0;37m';   # Use Gray for program output.
MAGENTA='\e[1;35m';
RESET='\e[0m'

# simplify colors and print errors to stderr (2)
echo_error() { echo -e "${RED}${*}${RESET}" >&2; }
echo_info() { echo -e "${YELLOW}${*}${RESET}" >&1; }
echo_success() { echo -e "${GREEN}${*}${RESET}" >&1; }
echo_intra() { echo -e "${BLUE}${*}${RESET}" >&1; }
echo_out() { echo -e "${GRAY}${*}${RESET}" >&1; }

# skip all checks if running on a docker container
[[ -f "/.dockerenv" ]] && CREW_FORCE_INSTALL=1

# reject crostini
if [[ -d /opt/google/cros-containers && "${CREW_FORCE_INSTALL}" != '1' ]]; then
  echo_error "Crostini containers are not supported by Chromebrew :/"
  echo_info "Run 'curl -Ls git.io/vddgY | CREW_FORCE_INSTALL=1 bash' to perform install anyway"
  exit 1
fi

# disallow non-stable channels Chrome OS
if [ -f /etc/lsb-release ]; then
  if [[ ! "$(< /etc/lsb-release)" =~ CHROMEOS_RELEASE_TRACK=stable-channel$'\n' && "${CREW_FORCE_INSTALL}" != '1' ]]; then
    echo_error "The beta, dev, and canary channel are unsupported by Chromebrew"
    echo_info "Run 'curl -Ls git.io/vddgY | CREW_FORCE_INSTALL=1 bash' to perform install anyway"
    exit 1
  fi
else
  echo_info "Unable to detect system information, installation will continue."
fi

if [ "${EUID}" == "0" ]; then
  echo_error "Chromebrew should not be installed or run as root."
  exit 1;
fi

echo_success "Welcome to Chromebrew!"

# prompt user to enter the sudo password if it set
# if the PASSWD_FILE specified by chromeos-setdevpasswd exist, that means a sudo password is set
if [[ "$(< /usr/sbin/chromeos-setdevpasswd)" =~ PASSWD_FILE=\'([^\']+) ]] && [ -f "${BASH_REMATCH[1]}" ]; then
  echo_intra "Please enter the developer mode password"
  # reset sudo timeout
  sudo -k
  sudo /bin/true
fi

# force curl to use system libraries
function curl () {
  # retry if download failed
  # the --retry/--retry-all-errors parameter in curl will not work with the 'curl: (7) Couldn't connect to server'
  # error, a for loop is used here
  for (( i = 0; i < 4; i++ )); do
    env LD_LIBRARY_PATH='' ${CURL} --ssl -C - "${@}" && \
      return 0 || \
      echo_info "Retrying, $((3-$i)) retries left."
  done
  # the download failed if we're still here
  echo_error "Download failed :/ Please check your network settings."
  return 1
}

case "${ARCH}" in
"i686"|"x86_64"|"armv7l"|"aarch64")
  LIB_SUFFIX=
  [ "${ARCH}" == "x86_64" ] && LIB_SUFFIX='64'
  ;;
*)
  echo_error "Your device is not supported by Chromebrew yet :/"
  exit 1;;
esac

echo_info "\n\nDoing initial setup for install in ${CREW_PREFIX}."
echo_info "This may take a while if there are preexisting files in ${CREW_PREFIX}...\n"

# This will allow things to work without sudo
crew_folders="bin cache doc docbook etc include lib lib$LIB_SUFFIX libexec man sbin share tmp var"
for folder in $crew_folders
do
  if [ -d "${CREW_PREFIX}"/"${folder}" ]; then
    echo_intra "Resetting ownership of ${CREW_PREFIX}/${folder}"
    sudo chown -R "$(id -u)":"$(id -g)" "${CREW_PREFIX}"/"${folder}"
  fi
done
sudo chown "$(id -u)":"$(id -g)" "${CREW_PREFIX}"

# Delete ${CREW_PREFIX}/{var,local} symlink on some Chromium OS distro if exist
[ -L ${CREW_PREFIX}/var ] && sudo rm -f "${CREW_PREFIX}/var"
[ -L ${CREW_PREFIX}/local ] && sudo rm -f "${CREW_PREFIX}/local"

# prepare directories
for dir in "${CREW_CONFIG_PATH}/meta" "${CREW_DEST_DIR}" "${CREW_PACKAGES_PATH}" "${CREW_CACHE_DIR}" ; do
  if [ ! -d "${dir}" ]; then
    mkdir -p "${dir}"
  fi
done

echo_info "\nDownloading information for Bootstrap packages..."
echo -en "${GRAY}"
# use parallel mode if available
if [[ "$(curl --help curl)" =~ --parallel ]]; then
  (cd "${CREW_LIB_PATH}"/packages && curl -OLZ "${URL}"/packages/{"${BOOTSTRAP_PACKAGES// /,}"}.rb)
else
  (cd "${CREW_LIB_PATH}"/packages && curl -OL "${URL}"/packages/{"${BOOTSTRAP_PACKAGES// /,}"}.rb)
fi
echo -e "${RESET}"

# prepare url and sha256
urls=()
sha256s=()

case "${ARCH}" in
"armv7l"|"aarch64")
  if ! type "xz" > /dev/null; then
    urls+=('https://github.com/snailium/chrome-cross/releases/download/v1.8.1/xz-5.2.3-chromeos-armv7l.tar.gz')
    sha256s+=('4dc9f086ee7613ab0145ec0ed5ac804c80c620c92f515cb62bae8d3c508cbfe7')
  fi
  ;;
esac

# create the device.json file if it doesn't exist
cd "${CREW_CONFIG_PATH}"
if [ ! -f device.json ]; then
  echo_info "\nCreating new device.json."
  jq --arg key0 'architecture' --arg value0 "${ARCH}" \
    --arg key1 'installed_packages' \
    '. | .[$key0]=$value0 | .[$key1]=[]' <<<'{}' > device.json
fi

for package in $BOOTSTRAP_PACKAGES; do
  pkgfile="${CREW_PACKAGES_PATH}/${package}.rb"

  [[ "$(sed -n '/binary_sha256/,/}/p' "${pkgfile}")" =~ .*${ARCH}:[[:blank:]]*[\'\"]([^\'\"]*) ]]
    sha256s+=("${BASH_REMATCH[1]}")

  [[ "$(sed -n '/binary_url/,/}/p' "${pkgfile}")" =~ .*${ARCH}:[[:blank:]]*[\'\"]([^\'\"]*) ]]
    urls+=("${BASH_REMATCH[1]}")
done

# functions to maintain packages
function download_check () {
    cd "$CREW_BREW_DIR"
    # use cached file if available and caching enabled
    if [ -n "$CREW_CACHE_ENABLED" ] && [[ -f "$CREW_CACHE_DIR/${3}" ]] ; then
      echo_intra "Verifying cached ${1}..."
      echo_success "$(echo "${4}" "$CREW_CACHE_DIR/${3}" | sha256sum -c -)"
      case "${?}" in
      0)
        ln -sf "$CREW_CACHE_DIR/${3}" "$CREW_BREW_DIR/${3}" || true
        return
        ;;
      *)
        echo_error "Verification of cached ${1} failed, downloading."
      esac
    fi
    #download
    echo_intra "Downloading ${1}..."
    curl '-#' -L "${2}" -o "${3}"

    #verify
    echo_intra "Verifying ${1}..."
    echo_success "$(echo "${4}" "${3}" | sha256sum -c -)"
    case "${?}" in
    0)
      if [ -n "$CREW_CACHE_ENABLED" ] ; then
        cp "${3}" "$CREW_CACHE_DIR/${3}" || true
      fi
      return
      ;;
    *)
      echo_error "Verification failed, something may be wrong with the download."
      exit 1;;
    esac
}

function extract_install () {
    # Start with a clean slate
    rm -rf "${CREW_DEST_DIR}"
    mkdir "${CREW_DEST_DIR}"
    cd "${CREW_DEST_DIR}"

    #extract and install
    echo_intra "Extracting ${1} ..."
    if [[ "$2" == *".zst" ]];then
      LD_LIBRARY_PATH=${CREW_PREFIX}/lib${LIB_SUFFIX}:/lib${LIB_SUFFIX} tar -Izstd -xpf ../"${2}"
    elif [[ "$2" == *".tpxz" ]];then
      if ! LD_LIBRARY_PATH=${CREW_PREFIX}/lib${LIB_SUFFIX}:/lib${LIB_SUFFIX} pixz -h &> /dev/null; then
        tar xpf ../"${2}"
      else
        LD_LIBRARY_PATH=${CREW_PREFIX}/lib${LIB_SUFFIX}:/lib${LIB_SUFFIX} tar -Ipixz -xpf ../"${2}"
      fi
    else
      tar xpf ../"${2}"
    fi
    echo_intra "Installing ${1} ..."
    tar cpf - ./*/* | (cd /; tar xp --keep-directory-symlink -f -)
    mv ./dlist "${CREW_CONFIG_PATH}/meta/${1}.directorylist"
    mv ./filelist "${CREW_CONFIG_PATH}/meta/${1}.filelist"
}

function update_device_json () {
  cd "${CREW_CONFIG_PATH}"

  if [[ $(jq --arg key "$1" -e '.installed_packages[] | select(.name == $key )' device.json) ]]; then
    echo_intra "Updating version number of ${1} in device.json..."
    cat <<< $(jq --arg key0 "$1" --arg value0 "$2" '(.installed_packages[] | select(.name == $key0) | .version) |= $value0' device.json) > device.json
  else
    echo_intra "Adding new information on ${1} to device.json..."
    cat <<< $(jq --arg key0 "$1" --arg value0 "$2" '.installed_packages |= . + [{"name": $key0, "version": $value0}]' device.json ) > device.json
  fi
}
echo_info "Downloading Bootstrap packages...\n"
# extract, install and register packages
for i in $(seq 0 $((${#urls[@]} - 1))); do
  url="${urls["${i}"]}"
  sha256="${sha256s["${i}"]}"
  tarfile="$(basename ${url})"
  name="${tarfile%%-*}"   # extract string before first '-'
  rest="${tarfile#*-}"    # extract string after first '-'
  version="${rest%%-chromeos*}"
                          # extract string between first '-' and "-chromeos"

  download_check "${name}" "${url}" "${tarfile}" "${sha256}"
  extract_install "${name}" "${tarfile}"
  update_device_json "${name}" "${version}"
done

## workaround https://github.com/skycocker/chromebrew/issues/3305
sudo ldconfig &> /dev/null || true
echo_info "\nCreating symlink to 'crew' in ${CREW_PREFIX}/bin/"
echo -e "${GRAY}"
ln -sfv "../lib/crew/bin/crew" "${CREW_PREFIX}/bin/"
echo -e "${RESET}"

echo_info "Setup and synchronize local package repo..."
echo -e "${GRAY}"

# Remove old git config directories if they exist
rm -rf "${CREW_LIB_PATH}"

# Do a minimal clone, which also sets origin to the master/main branch
# by default. For more on why this setup might be useful see:
# https://github.blog/2020-01-17-bring-your-monorepo-down-to-size-with-sparse-checkout/
# If using alternate branch don't use depth=1
[[ "$BRANCH" == "master" ]] && GIT_DEPTH="--depth=1" || GIT_DEPTH=
git clone $GIT_DEPTH --filter=blob:none --no-checkout "https://github.com/${OWNER}/${REPO}.git" "${CREW_LIB_PATH}"

cd "${CREW_LIB_PATH}"

# Checkout, overwriting local files.
[[ "$BRANCH" != "master" ]] && git fetch --all
git checkout "${BRANCH}"

# Set sparse-checkout folders and include install.sh for use in reinstalls
# or to fix problems.
git sparse-checkout set packages lib bin crew tools install.sh
git reset --hard origin/"${BRANCH}"
echo -e "${RESET}"

echo_info "Updating crew package information...\n"
# Without setting LD_LIBRARY_PATH, the mandb postinstall fails
# from not being able to find the gdbm library.
export LD_LIBRARY_PATH=$(crew const CREW_LIB_PREFIX | sed -e 's:CREW_LIB_PREFIX=::g')
# Since we just ran git, just update package compatibility information.
crew update compatible

echo_info "Installing core Chromebrew packages...\n"
yes | crew install core

echo_info "\nRunning Bootstrap package postinstall scripts...\n"
crew postinstall $BOOTSTRAP_PACKAGES

echo "                       . .
                   ..,:;;;::'..
                 .':lllllllool,.
                ...cl;..... ,::;'.
               .'oc...;::::..0KKo.
               .'od: .:::::, lolc.
             .'lNMMMO ;ooc.,XMMWx;:;.
            .dMMMMMMXkMMMMxoMMMMMMMMO.
            .:O0NMMMMMMMMMM0MMMMMN0Oc.
              .:xdloddddddoXMMMk:x:....
              .xMNOKX0OOOOxcodlcXMN0O0XKc.
              .OMXOKXOOOOOk;ol:OXMK...;N0.
              'XMKOXXOOOOOk:docOKMW,  .kW;
             .cMMKOXXOOOOOOOOOOO0MM;  .lMc.
             .cMM00XKOOOOkkkkkkOOWMl. .cMo.
             .lMWO0XKOOOkkkkkkkkONMo.  ;Wk.
             .oMNO0X0OOkkkkkkkkkOXMd..,oW0'
             .xMNO0X0OOkkkkkkkkkkXMWKXKOx;.
             .0MXOOOOOOkkkkkkkkkOKM0..
             'NMWNXXKK000000KKXNNMMX.
             .;okk0XNWWMMMMWWNKOkdc'.
                .....'cc:cc:''..."
echo "  ___ _                               _
 / (_)|\                              |\\
|     ||__    ,_    __  _  _  _    __ |/_  ,_    __  _   _   _
|     |/  |  /  |  /  \/ |/ |/ |  |_/ |  \/  |  |_/ /|   |   |\_
 \___/|   |_/   |_/\__/  |  |  |_/|__/\__/   |_/|__/  \_/ \_/
"

if [[ "${CREW_PREFIX}" != "/usr/local" ]]; then
  echo_info "\n$
Since you have installed Chromebrew in a directory other than '/usr/local',
you need to run these commands to complete your installation:
"

  echo_intra "
echo 'export CREW_PREFIX=${CREW_PREFIX}' >> ~/.bashrc
echo 'export PATH=\"\${CREW_PREFIX}/bin:\${CREW_PREFIX}/sbin:\${PATH}\"' >> ~/.bashrc
echo 'export LD_LIBRARY_PATH=${CREW_PREFIX}/lib${LIB_SUFFIX}' >> ~/.bashrc
source ~/.bashrc"
fi
echo_intra "
Edit ${CREW_PREFIX}/etc/env.d/02-pager to change the default PAGER.
more is used by default

You may wish to edit the ${CREW_PREFIX}/etc/env.d/01-editor file for an editor default.

Chromebrew provides nano, vim and emacs as default TUI editor options."

echo_success "Chromebrew installed successfully and package lists updated."
