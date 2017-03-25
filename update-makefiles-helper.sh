#!/bin/bash

#TODO(b/35570956): Do with Soong instead.

#Note: see do_makefiles_update below.

function package_root_to_package() {
  echo $1 | cut -f1 -d:
}

function package_root_to_root() {
  echo $1 | cut -f2 -d:
}

##
# Makes sure the appropriate directories are visible.
# Usage: check_dirs [package:root ...]
function check_dirs() {
  for package_root in "$@"; do
      dir=$(package_root_to_root $package_root)
      if [ ! -d $dir ] ; then
        echo "Where is $dir?";
        return 1;
      fi
  done
}

##
# Gets all packages in a directory.
# Usage: get_packages package root
function get_packages() {
  local current_dir=$1
  local current_package=$2
  pushd $current_dir > /dev/null;
  find . -type f -name \*.hal -exec dirname {} \; | sort -u | \
    cut -c3- | \
    awk -F'/' \
    '{printf("'$current_package'"); for(i=1;i<NF;i++){printf(".%s", $i);}; printf("@%s\n", $NF);}';
  popd > /dev/null;
}

##
# Package roots to arguments.
# Usage: get_root_arguments [package:root ...]
function get_root_arguments() {
  for package_root in "$@"; do
      echo "-r $package_root"
  done
}

##
# Subdirectories of a directory which contain Android.bps
# Note, does not return Android.bp in the current directory.
#
# Usage: get_bp_dirs dir
function get_bp_dirs() {
  find $1/*/                         \
    -name "Android.bp"               \
    -printf "%h\n"                   \
    | cut -d "/" -f1-3               \
    | sort | uniq
}

##
# Helps manage the package root of a HAL directory.
# Should be called from the android root directory.
#
# Usage: do_makefiles_update [package:root ...]
# Where the first package root is the current one.
#
function do_makefiles_update() {
  local current_package=$(package_root_to_package $1)
  local current_dir=$(package_root_to_root $1)

  echo "Updating makefiles for $current_package in $current_dir."

  check_dirs $@ || return 1

  local packages=$(get_packages $current_dir $current_package) || return 1
  local root_arguments=$(get_root_arguments $@) || return 1

  for p in $packages; do
    echo "Updating $p";
    rc=$?; if [[ $rc != 0 ]]; then return $rc; fi
    hidl-gen -Landroidbp $root_arguments $p;
    rc=$?; if [[ $rc != 0 ]]; then return $rc; fi
  done

  local android_dirs=$(get_bp_dirs $current_dir) || return 1

  echo "Updating Android.bp files."

  for bp_dir in $android_dirs; do
    bp="$bp_dir/Android.bp"
    # locations of Android.bp files in specific subdirectory of frameworks/hardware/interfaces
    android_bps=$(find $bp_dir                   \
                  -name "Android.bp"             \
                  ! -path $bp_dir/Android.bp     \
                  -printf "%h\n"                 \
                  | sort)

    echo "// This is an autogenerated file, do not edit." > "$bp";
    echo "subdirs = [" >> "$bp";
    for a in $android_bps; do
      echo "    \"${a#$bp_dir/}\"," >> "$bp";
    done
    echo "]" >> "$bp";
  done
}