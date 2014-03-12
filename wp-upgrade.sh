#!/usr/bin/env bash

WP_LATEST="https://wordpress.org/latest.tar.gz"

# Disclamer and instructions
echo 'This software is release under The MIT License 
http://opensource.org/licenses/MIT

Copyright (c) 2014 Volt Grid Pty. Ltd. http://voltgrid.com/

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE
'

echo -n "Enter \"y\" to accept the license and warranty terms and continue. "
read -s -n1 accept
echo
[ "${accept}" == "y" ] || exit 0

die() {
  [ -n "$1" ] && echo $1
  rm -rf ${TMP_FOLDER}
  exit ${2-0}
}

get_ver() {
  sed -e 's/^\$wp_version.*'\''\(.*\)'\''.*/\1/' -e 'tx' -e 'd' -e ':x' wp-includes/version.php 2>/dev/null
}

# vercomp function by Dennis Williamson from http://stackoverflow.com/a/4025065
vercomp () {
    if [[ $1 == $2 ]]
    then
        echo "0"
        return 0
    fi
    local IFS=.
    local i ver1=($1) ver2=($2)
    # fill empty fields in ver1 with zeros
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++))
    do
        ver1[i]=0
    done
    for ((i=0; i<${#ver1[@]}; i++))
    do
        if [[ -z ${ver2[i]} ]]
        then
            # fill empty fields in ver2 with zeros
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]}))
        then
            echo "1"
            return 1
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]}))
        then
            echo "2"
            return 2
        fi
    done
    echo "0"
    return 0
}

check_git() {
  # Check git version version => 1.7, version =< 2.0
  git_ver=$(git --version | sed -e 's/git version //')
  { [ "$(vercomp ${git_ver} 1.7)" -ne 2 ] && [ "$(vercomp 2 ${git_ver})" -eq 1 ]; } || die "Unsupported git version" 1
}


case "$(uname -s)" in
  Linux)
    echo "Running on linux"
    TMP_FOLDER=$(mktemp -d -t $(basename $0).XXXXXXXXXX)
    check_git
    ;;
  Darwin)
    echo "Running on OSX"
    TMP_FOLDER=$(mktemp -d -t $(basename $0))
    check_git
    ;;
  MINGW32_NT*)
    echo "Running Git Shell"
    TMP_FOLDER=$(echo "${TMP}/$(basename $0).$(date +%Y%m%d%H%M%S)" | xargs -i% sh -c "echo %; mkdir %;")
    echo "Can't check git on this platform. Tested with git versions 1.7 to 1.8 only."
    git --version
    ;;
  *)
    echo "Unknown/Unsupported system. Exiting."
    exit 1
    ;;
esac

# Check working dir is actually a git repo
[ -d ".git" ] || die "Current directory does not appear to be a git repo" 1

# Get current wordpress version
from_ver=$(get_ver)
[ -n "${from_ver}" ] || die "Can not find current wordpress version" 1

echo "Getting latest version..."
curl "${WP_LATEST}" -s -o ${TMP_FOLDER}/wp.tar.gz || die "Unable to retrieve latest version" 1
#cp ~/wp.tar.gz ${TMP_FOLDER}/wp.tar.gz
tar -C ${TMP_FOLDER} -zxf ${TMP_FOLDER}/wp.tar.gz || die "Unable to extract latest version" 1
[ -d "${TMP_FOLDER}/wordpress" ] || die "Latest wordpress folder missing" 1
to_ver=$(cd ${TMP_FOLDER}/wordpress; get_ver)

# Can't get this to work on MINGW commeting out
#wp_vercomp="$(vercomp ${from_ver} ${to_ver})"
#case ${wp_vercomp} in
#  0)
#    die "Appears your already got the latest version" 1
#    ;;
#  1)
#    die "Current version is newer that downloaded" 1
#    ;;
#  2)
#    echo -n "Upgrading from ${from_ver} to ${to_ver}. Does this look correct? [Y/n] "
#    ;;
#  *)
#    die "Something unexpected happened" 1
#    ;;
#esac
#read -n1 continue
#echo 
#[ "${continue}" == y ] || [ -z "${continue}" ] || die "Exiting."

echo -n "Upgrading from ${from_ver} to ${to_ver}. Does this look correct? [Y/n] "
read -n1 continue
echo
[ "${continue}" == y ] || [ -z "${continue}" ] || die "Exiting."

echo 
echo "Removing wp-content/cache"
git rm -rf wp-content/cache >/dev/null 2>&1
echo "Removing wp-content/plugins/widgets"
git rm -rf wp-content/plugins/widgets >/dev/null 2>&1

echo
up_files='wp-admin wp-includes'
for item in $(ls ${TMP_FOLDER}/wordpress/)
do
  [ "${item}" == ".htaccess" ] || [ "${item}" == "wp-config.php" ] || [ -d "${TMP_FOLDER}/wordpress/${item}" ] && continue
  up_files="${up_files} ${item}"
done
for item in $(ls ${TMP_FOLDER}/wordpress/wp-content/plugins/)
do
  up_files="${up_files} wp-content/plugins/${item}"
done
for item in $(ls ${TMP_FOLDER}/wordpress/wp-content/themes/)
do
  up_files="${up_files} wp-content/themes/${item}"
done

for file in $up_files
do
  echo -n "${file}: "
  echo -n "removing old, "
  rm -rf ${file}
  echo -n "copying new, "
  cp -a ${TMP_FOLDER}/wordpress/${file} ${file}
  echo -n "adding to git, "
  git add --all ${file}
  echo "done"
done

echo
echo -n "Add git commit? [Y/n] "
read -n1 commit
echo 
if [ "${commit}" == "y" ] || [ -z "${commit}" ]
then
  git commit -m "Upgraded WordPress from version ${from_ver} to ${to_ver}"
  echo
fi

# Get current branch
branch_name="$(git symbolic-ref HEAD 2>/dev/null)" ||
branch_name="(unnamed branch)" # detached HEAD
branch_name=${branch_name##refs/heads/}

echo "If you need to make further changes do so and perform another git commit"
echo "Once you have tested your upgraded WordPress install you can push it with"
for remote in $(git remote -v | grep '(push)$' | cut -f1)
do
  echo "> git push ${remote} ${branch_name}"
done

die
