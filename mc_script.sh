#!/bin/bash
#
# mincraft_server start/stop/backup script
#

set -ue -o pipefail
 
# mincraft_server.jar 実行ユーザ
USERNAME='normal'
 
# screen名
SCNAME='minecraft'
 
# minecraft_serverディレクトリ
MC_PATH=$(cd $(dirname "${0}"); pwd)


SERVER_PROPERTIES="${MC_PATH}/server.properties"

# 実行するminecraft_server.jar
# SERVICE='minecraft_server.1.12.2.jar'
SERVICE='forge-1.12.2-14.23.5.2772-universal.jar'
 
# メモリ設定
XMX='1024M'
XMS='1024M'
 
## バックアップ用設定
# バックアップ格納ディレクトリ
BK_DIR="/home/$USERNAME/minecraft_backup"
 
# バックアップ取得時間
BK_TIME=`date +%Y%m%d-%H%M%S`
 
# 完全バックアップデータ名
FULL_BK_NAME="$BK_DIR/mc_backup_full_${SERVICE}_${BK_TIME}.tar.gz"
 
# 簡易パックアップデータ名
HOUR_BK_NAME="$BK_DIR/mc_backup_hourly_${SERVICE}_${BK_TIME}.tar"
 
# 簡易バックアップ対象データ
BK_FILE="$MC_PATH/world \
  $MC_PATH/banned-ips.json \
  $MC_PATH/banned-players.json \
  $MC_PATH/ops.json \
  $MC_PATH/server.properties \
  $MC_PATH/usercache.json \
  $MC_PATH/whitelist.json"
 
# バックアップデータ保存数
BK_GEN="3"
 
cd $MC_PATH
 
if [ ! -d $BK_DIR ]; then
  mkdir $BK_DIR
fi
 
ME=`whoami`
 
if [ $ME != $USERNAME ]; then
  echo "Please run the $USERNAME user."
  exit
fi
 
start() {
  if pgrep -u $USERNAME -f $SERVICE > /dev/null; then
    echo "$SERVICE is already running!"
    exit
  fi
  echo "Starting $SERVICE..."
  screen -AmdS $SCNAME java -Xmx$XMX -Xms$XMS -jar $SERVICE nogui
}
 
stop() {
  if pgrep -u $USERNAME -f $SERVICE > /dev/null; then
    echo "Stopping $SERVICE"
    screen -p 0 -S $SCNAME -X eval 'stuff "say SERVER SHUTTING DOWN IN 3 SECONDS. Saving map..."\015'
    screen -p 0 -S $SCNAME -X eval 'stuff "save-all"\015'
    sleep 3
    screen -p 0 -S $SCNAME -X eval 'stuff "stop"\015'
    sleep 10
    echo "Stopped minecraftserver"
  else
    echo "$SERVICE is not running!"
  fi
}

reload() {
    stop
    start
}
 
h_backup() {
  if pgrep -u $USERNAME -f $SERVICE > /dev/null; then
    echo "Backup start minecraft data..."
    screen -p 0 -S $SCNAME -X eval 'stuff "save-all"\015'
    sleep 10
    screen -p 0 -S $SCNAME -X eval 'stuff "save-off"\015'
    tar cfv $HOUR_BK_NAME $BK_FILE
    sleep 10
    screen -p 0 -S $SCNAME -X eval 'stuff "save-on"\015'
    echo "minecraft_server backup compleate!"
    gzip -f $HOUR_BK_NAME
    find $BK_DIR -name "mc_backup_hourly_*.tar.gz" -type f -mtime +$BK_GEN -exec rm {} \;
  else
    echo "$SERVICE was not runnning."
  fi
}
 
f_backup() {
  if pgrep -u $USERNAME -f $SERVICE > /dev/null; then
    echo "Full backup start minecraft data..."
    screen -p 0 -S $SCNAME -X eval 'stuff "say サーバーの再起動が約 10 秒後に行われます。"\015'
    screen -p 0 -S $SCNAME -X eval 'stuff "save-all"\015'
    sleep 10
    screen -p 0 -S $SCNAME -X eval 'stuff "stop"\015'
    echo "Stopped minecraft_server"
    echo "Full Backup start ..."
    screen -ls
    tar cfvz $FULL_BK_NAME $MC_PATH
    sleep 10
    echo "Full Backup compleate!"
    find $BK_DIR -name "mc_backup_full*.tar.gz" -type f -mtime +$BK_GEN -exec rm {} \;
    echo "Starting $SERVICE..."
    screen -AmdS $SCNAME java -Xmx$XMX -Xms$XMS -jar $SERVICE nogui
  else
    echo "$SERVICE was not runnning."
  fi
}
 
status() {
  if pgrep -u $USERNAME -f $SERVICE > /dev/null; then
    echo "$SERVICE is already running!"
    exit
  else
    echo "$SERVICE is not running!"
    exit
  fi
}

get_motd() {
    cat server.properties | grep -e "^motd" | python3.5 -c 'from sys import stdin; import codecs; print(codecs.decode(stdin.readline(), "unicode-escape"))'
}

set_motd() {
    NEW_MOTD=$(echo $@ | python3.5 -c 'from sys import stdin; print(str(stdin.readline().encode("unicode-escape"))[2:-4])' | sed -e s@\\\\\\\\\\\\\\\\n@\\\\\\\\n@)
    perl -pi -e "s|(?<=^motd\=).*|${NEW_MOTD}|" "${SERVER_PROPERTIES}"
}


 
case "$1" in
  start)
    start
    ;;
  stop)
    stop
    ;;
  reload)
    reload
    ;;
  h_backup)
    h_backup
    ;;
  f_backup)
    f_backup
    ;;
  status)
    status
    ;;
  get_motd)
    get_motd
    ;;
  set_motd)
    set_motd "$2"
    ;;
  *)
    echo  $"Usage: $0 {start|stop|reload|h_backup|f_backup|status|(get|set)_motd}"
esac
