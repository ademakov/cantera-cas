#!/bin/sh

set -e
set -x

repo=`mktemp -d`

trap 'rm -rf "$repo"' EXIT

fatal_error() {
  echo "$@" >&2
  exit 1
}

put() {
  DIGEST=`echo "$1" | sha1sum | cut -d' ' -f1`
  if ! echo "$1" | ./ca-cas -c PUT "$repo" >/dev/null
  then
    fatal_error "Inserting $1 failed"
  fi
}

test_200() {
  DIGEST=`echo "$1" | sha1sum | cut -d' ' -f1`
  LENGTH=`expr 1 + length "$1"`
  if ! ./ca-cas -c "GET $DIGEST" "$repo" \
    | cmp /proc/self/fd/3 3<<EOF
200 $LENGTH
$1
EOF
  then
    fatal_error "Retrieving $1 failed"
  fi
}

test_404() {
  DIGEST=`echo "$1" | sha1sum | cut -d' ' -f1`
  if ! ./ca-cas -c "GET $DIGEST" "$repo" \
    | cmp /proc/self/fd/3 3<<EOF
404 Entity not found
EOF
  then
    fatal_error "Retrieving $1 succeeded unexpectedly"
  fi
}

expect_n_packs() {
  NPACKS="`find "$repo" -type f -name \*.pack | wc -l`"
  if [ $1 != $NPACKS ]
  then
    fatal_error "Expected $1 pack files, found $NPACKS"
  fi
}

expect_n_unpacked_objects() {
  NOBJECTS="`find "$repo" -type f -not -name \*.pack | wc -l`"

  if [ $1 != $NOBJECTS ]
  then
    fatal_error "Expected $1 unpacked objects, found $NOBJECTS"
  fi
}

test_404 "data000000"
put "data000000"
test_200 "data000000"

test_404 "missing"

expect_n_packs 0
expect_n_unpacked_objects 1
./ca-cas-repack "$repo"
expect_n_packs 1
expect_n_unpacked_objects 0

test_200 "data000000"
test_404 "missing"

put "data000001"
expect_n_packs 1
expect_n_unpacked_objects 1

./ca-cas-repack "$repo"
expect_n_packs 2
expect_n_unpacked_objects 0

put "data000002"
expect_n_packs 2
expect_n_unpacked_objects 1

for pass in 1 2
do
  ./ca-cas-repack --full --delete "$repo"
  expect_n_packs 1
  expect_n_unpacked_objects 0

  test_200 "data000000"
  test_200 "data000001"
  test_200 "data000002"
done