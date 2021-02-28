#!/bin/bash
set -Ceuo pipefail
# (C) TOYODA Eizi, 2021
# ひまわり画像をダウンロードする
# 定期的に起動されることを想定している。時刻は細かくチューニングしなくてよい。
#
PATH=/bin:/usr/bin:/usr/local/bin:/sbin:/usr/sbin
LANG=C
TZ=UTC

let 'hour = 3600'
let 'day = 24 * hour'
# === 設定 ===
# 取得画種
products="B13/TBB B08/TBB"
# ズームレベル
z=5
: TODO 取得領域も設定できるようにすべき
# 取得間隔（秒）
let 'interval = hour * 3'
# montage でタイル結合を行う場合 true
: ${do_montage:=true}
# タイルを zip でまとめて保存する場合 true
: ${do_zip:=true}
# タイルを montage/zip した後削除する場合 true
: ${do_rmtile:=true}
# 気象庁の時刻一覧から外れたあとの保存期間
: ${keep_days:=7}
# データ保存場所は $JMADATADIR、未設定時はスクリプト設置場所
: ${JMADATADIR:=$(dirname $0)}

cd $JMADATADIR
mkdir -p himawari
cd himawari

root=https://www.jma.go.jp/bosai/himawari/data/satimg

# 時間リストを取得してプレーンテキストに変換する
# ひまわりの場合 basetime=validtime なので basetime だけを出力
# targetTimes_fd.txt は以下重複起動を防止するロックとなるので、
# 終了時には必ず消えるように trap を設定する
wget -OtargetTimes_fd.json -q ${root}/targetTimes_fd.json
ruby -rjson -e 'JSON[File.read(ARGV.first)].each{|h| puts h["basetime"]}' \
  targetTimes_fd.json > targetTimes_fd.txt
trap "rm -f ${PWD}/targetTimes_fd.txt" EXIT
rm -f targetTimes_fd.json

while read basetime
do
  validtime=$basetime

  # ダウンロード対象の時刻を選ぶ
  # UNIX time 換算して interval の倍数でなければスキップ
  itime=$(ruby -rtime -e 'puts Time.parse(ARGV.first).to_i' $basetime)
  if expr $itime \% $interval '!=' 0 >/dev/null
  then
    : skipping $basetime
    continue
  fi
  # 重複ダウンロード回避
  if test -d $basetime; then
    : $basetime already exists
    # タイムスタンプだけは更新しておく
    touch $basetime
    continue
  fi

  mkdir -p $basetime
  cd $basetime
  for prod in $products
  do
    ruby -e '(25..30).each{|x|(10..15).each{|y|
      puts "#{ARGV[0]}/#{x}/#{y}.jpg"}}' \
      ${root}/${basetime}/fd/${validtime}/${prod}/${z} > ../zlist.txt
    wget -q -x -nH --cut-dirs=7 -i ../zlist.txt
    rm -f ../zlist.txt
    # タイルのまま連結表示するHTMLを書き出す
    htmlfile=$(echo $prod | sed 's:/:_:')${basetime}.html
    ruby -e 'pr = ARGV.first
      puts <<-HTML
        <html><head><style type="text/css">
        table { border-collapse: collapse; } tr td { padding: 0; border: 0;}
        </style></head><body><table>
        HTML
      (10..15).each{|y|
        puts "<tr>"
        (25..30).each{|x|
          puts "<td><img src='\''#{pr}/5/#{x}/#{y}.jpg'\''></td>"
        }
        puts "</tr>"
      }
      puts "</table></body></html>"
    ' $prod > $htmlfile
    if $do_zip; then
      zipfile=$(echo $prod | sed 's:/:_:')${basetime}.zip
      zip -0 -q -r $zipfile $htmlfile $prod
    fi
    if $do_montage; then
      montagefile=$(echo $prod | sed 's:/:_:')${basetime}
      montage ${prod}/5/*/10.jpg ${prod}/5/*/11.jpg ${prod}/5/*/12.jpg \
        ${prod}/5/*/13.jpg ${prod}/5/*/14.jpg ${prod}/5/*/15.jpg \
        -tile 6x -geometry 256x256 ${montagefile}.jpg
    fi
    if $do_rmtile; then
      pr=$(echo $prod | sed 's:/.*::')
      rm -rf $pr $htmlfile
    fi
  done
  cd ..

done < targetTimes_fd.txt

# 保存期間が過ぎたディレクトリを削除
find . -maxdepth 1 -ctime +${keep_days} | xargs -r rm -rf
