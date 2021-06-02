#!/bin/bash
set -Ceuo pipefail
# (C) TOYODA Eizi, 2021
# ナウキャストのレーダー実況画像をダウンロードする
# 定期的に起動されることを想定している。時刻は細かくチューニングしなくてよい。
#
PATH=/bin:/usr/bin:/usr/local/bin:/sbin:/usr/sbin
LANG=C
TZ=UTC

let 'hour = 3600'
let 'day = 24 * hour'
# === 設定 ===
# 取得画種
products="surf/hrpns"
# ズームレベル
z=6
: TODO 取得領域も設定できるようにすべき
# 取得間隔（秒）
let 'interval = hour * 1'
# montage でタイル結合を行う場合 true
: ${do_montage:=true}
# タイルを zip でまとめて保存する場合 true
: ${do_zip:=true}
# タイルを montage/zip した後削除する場合 true
: ${do_rmtile:=true}
# 気象庁の時刻一覧から外れたあとの保存期間
: ${keep_days:=1}
# データ保存場所は $JMADATADIR、未設定時はスクリプト設置場所
: ${JMADATADIR:=$(dirname $0)}
# アーカイブ保存する場合
: ${do_archive:=true}

cd $JMADATADIR
mkdir -p nowc
cd nowc

root=https://www.jma.go.jp/bosai/jmatile/data/nowc

# times.txt は以下重複起動を防止するロックなのだが、不幸にして残った場合
if timestamp=$(stat --format=%Z times.txt 2>/dev/null) ; then
  limit=$(date --date='1 hour ago' '+%s')
  if [[ $timestamp -lt $limit ]] ; then
    rm -f times.txt targetTimes_N1.json
    date --date="@${timestamp}" +'Lock file at %c - removed'
  else
    date --date="@${timestamp}" +'Lock file at %c - aborted'
    false
  fi
fi

# 時間リストを取得してプレーンテキストに変換する
# 実況の場合 basetime=validtime なので basetime だけを出力
# times.txt は以下重複起動を防止するロックとなるので、
# 終了時に消えるように trap を設定する
wget -OtargetTimes_N1.json -q ${root}/targetTimes_N1.json
ruby -rjson -e 'JSON[File.read(ARGV.first)].each{|h| puts h["basetime"]}' \
  targetTimes_N1.json > times.txt
trap "rm -f ${PWD}/times.txt" EXIT
rm -f targetTimes_N1.json

while read basetime
do
  validtime=$basetime

  # ダウンロード対象の時刻を選ぶ
  # basetime を通算秒に換算して interval の倍数でなければスキップ
  # まずは年月日時分を GNU date が読める形式に変換
  isotime=$(echo $basetime | sed 's/\(....\)\(..\)\(..\)\(..\)\(..\)\(..\)/\1-\2-\3T\4:\5:\6/')
  # GNU date で 1970-01-01T00:00:00Z からの通算秒に換算
  itime=$(date --date=${isotime} +%s)
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
    rm -f urllist.txt
    for ((x=53; x<=58; x++))
    do
      for ((y=22; y<=27; y++))
      do
        echo "${root}/${basetime}/none/${validtime}/${prod}/${z}/${x}/${y}.png"  >> urllist.txt
      done
    done
    # 一度通信エラーで落ちたらリトライする
    if ! wget -q -x -nH --cut-dirs=7 -i urllist.txt
    then
      sleep 30
      wget -q -x -nH --cut-dirs=7 -i urllist.txt
    fi
    rm -f urllist.txt
    # タイルのまま連結表示するHTMLを書き出す
    htmlfile=$(echo $prod | sed 's:/:_:')${basetime}.html
    cat <<HEAD > $htmlfile
<html><head><style type="text/css">
table { border-collapse: collapse; } tr td { padding: 0; border: 0;}
</style></head><body><table>
HEAD
    for ((y=22; y<=27; y++))
    do
      echo '<tr>' >> $htmlfile
      for ((x=53; x<=58; x++))
      do
        echo "<td><img src=\"${prod}/6/${x}/${y}.png\"></td>" >> $htmlfile
      done
      echo '</tr>' >> $htmlfile
    done
    if $do_zip; then
      zipfile=$(echo $prod | sed 's:/:_:')${basetime}.zip
      zip -0 -q -r $zipfile $htmlfile $prod
      if $do_archive; then
        ym=$(ruby -rtime -e 'puts Time.parse(ARGV.first).strftime("%Y-%m %c")' $basetime)
        test ! -d /nwp/a1/$ym || mkdir -f /nwp/a1/$ym
        ln -f $zipfile /nwp/a1/$ym/$zipfile
      fi
    fi
    if $do_montage; then
      montagefile=$(echo $prod | sed 's:/:_:')${basetime}
      montage \
        ${prod}/6/*/22.png ${prod}/6/*/23.png ${prod}/6/*/24.png \
        ${prod}/6/*/25.png ${prod}/6/*/26.png ${prod}/6/*/27.png \
        -tile 6x -geometry 256x256 zzztmp.png
      convert zzztmp.png -transparent white ${montagefile}.png
      rm -f zzztmp.png
    fi
    if $do_rmtile; then
      pr=$(echo $prod | sed 's:/.*::')
      rm -rf $pr $htmlfile
    fi
  done
  cd ..

done < times.txt

# 保存期間が過ぎたディレクトリを削除
find . -maxdepth 1 -ctime +${keep_days} | xargs -r rm -rf
