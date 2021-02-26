#!/bin/bash
set -Ceuo pipefail
PATH=/bin:/usr/bin:/usr/local/bin:/sbin:/usr/sbin
LANG=C
TZ=UTC

# products
products="B13/TBB "

# move to directory in which THIS script is located
cd $(dirname $0)

wget -Ozt-himawari.json -q \
  https://www.jma.go.jp/bosai/himawari/data/satimg/targetTimes_fd.json

set $(ruby -rjson -e 'h=JSON[File.read(ARGV.first)].last; puts h["basetime"]; puts h["validtime"]' zt-himawari.json)
basetime=$1
validtime=$2

if test -d $basetime; then
  echo $basetime already exists
  exit 0
fi
mkdir -p himawari/$basetime
cd himawari/$basetime

root=https://www.jma.go.jp/bosai/himawari/data/satimg
for prod in $products
do
  mkdir -p $prod/4
  pushd $prod/4
  ruby -e '(11..16).each{|x|(4..8).each{|y| puts "#{ARGV.first}/#{x}/#{y}.jpg"}}' ${root}/${prod} > ../zlist.txt
  wget -q -x -nH --cut-dirs=6 -i ../zlist.txt
  rm -f ../zlist.txt
  popd
done
