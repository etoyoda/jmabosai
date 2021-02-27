#!/bin/bash
set -Ceuo pipefail
#
# ひまわり画像をダウンロードする
#
PATH=/bin:/usr/bin:/usr/local/bin:/sbin:/usr/sbin
LANG=C
TZ=UTC

# === 設定 ===
# 取得画種
products="B13/TBB B08/TBB"
# ズームレベル
z=5
# 取得間隔（秒）
# interval=3600
interval=10800

# データ保存場所は $JMADATADIR、未設定時はスクリプト設置場所
cd ${JMADATADIR:-$(dirname $0)}
mkdir -p himawari
cd himawari

root=https://www.jma.go.jp/bosai/himawari/data/satimg

# 時間リストを取得してプレーンテキストに変換する
# ひまわりの場合 basetime=validtime なので basetime だけを出力
wget -OtargetTimes_fd.json -q ${root}/targetTimes_fd.json
ruby -rjson -e 'JSON[File.read(ARGV.first)].each{|h| puts h["basetime"]}' \
  targetTimes_fd.json > targetTimes_fd.txt
rm -f targetTimes_fd.json

while read basetime
do
  validtime=$basetime

  itime=$(ruby -rtime -e 'puts Time.parse(ARGV.first).to_i' $basetime)
  if expr $itime \% $interval '!=' 0 >/dev/null
  then
    : skipping $basetime
    continue
  fi

  if test -d $basetime; then
    : $basetime already exists
    continue
  fi
  mkdir -p $basetime
  pushd $basetime

  for prod in $products
  do
    ruby -e '(25..30).each{|x|(10..15).each{|y|
      puts "#{ARGV[0]}/#{x}/#{y}.jpg"}}' \
      ${root}/${basetime}/fd/${validtime}/${prod}/${z} > ../zlist.txt
    wget -q -x -nH --cut-dirs=7 -i ../zlist.txt
    rm -f ../zlist.txt
    # タイルのまま連結表示するHTMLを書き出す
    ruby -e 'bt, pr = ARGV
      fn = pr.sub(/\//, "_") + ".html"
      $stdout = File.open(fn, "w")
      puts <<-HTML
        <html>
        <head><style type="text/css">
        table { border-collapse: collapse; }
        tr td { padding: 0; border: 0;}
        </style>
        </head>
        <body><table>
        HTML
      (10..15).each{|y|
        puts "<tr>"
        (25..30).each{|x|
          puts "<td><img src='\''#{pr}/5/#{x}/#{y}.jpg'\''></td>"
        }
        puts "</tr>"
      }
      puts "</table></body></html>"
    ' $basetime $prod
  done
  popd

done < targetTimes_fd.txt
rm -f targetTimes_fd.txt
