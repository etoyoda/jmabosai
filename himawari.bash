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
z=5

for prod in $products
do
  ruby -e '(25..30).each{|x|(10..15).each{|y| puts "#{ARGV[0]}/#{x}/#{y}.jpg"}}' ${root}/${basetime}/fd/${validtime}/${prod}/${z} > ../zlist.txt
  wget -q -x -nH --cut-dirs=7 -i ../zlist.txt
  rm -f ../zlist.txt
done
rm -f zt-himawari.json
