#!/bin/sh

##TODO: プロバイダゲートウェイIPと品質を記録
##TODO: プロバイダゲートウェイのIP指定
###TODO: 品質カスタムのコマンドラインオプション

#TODO
USAGE="
USAGE: not implemented yet
$0 xxx
"

[ `whoami` = "root" ] || exit 1
[ `command -v ip` ] || exit 1
[ `command -v ifup` ] || exit 1
[ `command -v ifdown` ] || exit 1
[ `command -v pon` ] || exit 1
[ `command -v poff` ] || exit 1
PPPOE_IF=`ip address | grep "POINTOPOINT" | cut -d ':' -f 2 | sed -e "s/^ //g"`
[ -n "${PPPOE_IF}" ] || exit 1
#TODO: netplan対応
PPPOE_SCRIPT=`cat /etc/network/interfaces | grep "iface" | grep "inet ppp" | cut -d ' ' -f 2`
[ -n "${PPPOE_SCRIPT}" ] || exit 1

# Command Line Option
while [ $# -gt 0 ]
do
    case $1 in
	    -d | --download-only)
		    OPT_DOWNLOAD_ONLY="true"
		    ;;
	    -q | --quality)
		    OPT_QUALITY=$2
		    shift
		    ;;
	    -r | --repeat)
		    OPT_SPEED_TEST_NUM=$2
		    shift
		    ;;
	    -s | --server)
		    OPT_SPECIFY_SPEEDTEST_SERVER="true"
		    ;;
	    -h | --help)
		    echo "${USAGE}"
		    exit 0
		    ;;
	    -*)
		    echo "ERROR: Invalid option"
		    exit 1
		    ;;
	    *)
		    if [ -n "${OPT_SPEED_TEST_APP}" ]; then
			    echo "ERROR: Invalid argument"
			    exit 1
		    fi
		    OPT_SPEED_TEST_APP=$1
		    ;;
    esac
    shift
done

# 回線速度計測プログラムの選択
# fast | speedtest
SPEED_TEST_APP="fast"
[ -n "${OPT_SPEED_TEST_APP}" ] && SPEED_TEST_APP="${OPT_SPEED_TEST_APP}"

# PPPoE再接続を実行する品質
# BAD | NORMAL | GOOD
THRESHOLD_QUALITY="NORMAL"
[ -n "${OPT_QUALITY}" ] && THRESHOLD_QUALITY="${OPT_QUALITY}"

# PPPoE再接続実行閾値
case "${THRESHOLD_QUALITY}" in
	BAD | bad | b)
		THRESHOLD_PN="45"
		THRESHOLD_DL="25"
		THRESHOLD_UL="10"
		;;
	NORMAL | normal | n)
		THRESHOLD_PN="30"
		THRESHOLD_DL="50"
		THRESHOLD_UL="20"
		;;
	GOOD | good | g)
		THRESHOLD_PN="15"
		THRESHOLD_DL="75"
		THRESHOLD_UL="30"
		;;
	*)
		THRESHOLD_PN="36"
		THRESHOLD_DL="25"
		THRESHOLD_UL="10"
		;;
esac

# PPPoE IF再起動インターバル(sec)
PPPOE_RESTART_INTERVAL="2"

# PPPoE Interface Timeout(sec)
PPPOE_IF_TIMEOUT="30"

# PPPoE再接続最大回数(無限ループ防止)
PPPOE_MAX_RETRY="50"

# 処理省略による高速化
DOWNLOAD_ONLY="false"
[ -n "${OPT_DOWNLOAD_ONLY}" ] && DOWNLOAD_ONLY="${OPT_DOWNLOAD_ONLY}"

# 回線速度計測回数
SPEED_TEST_NUM="1"
[ -n "${OPT_SPEED_TEST_NUM}" ] && SPEED_TEST_NUM="${OPT_SPEED_TEST_NUM}"
# 数値判定(計算結果は0にならないため、戻り値1は考慮しない)
[ `expr "${SPEED_TEST_NUM}" + 1` ] || exit 1

# Speedtest.netサーバの指定
SPECIFY_SPEEDTEST_SERVER="false"
[ -n "${OPT_SPECIFY_SPEEDTEST_SERVER}" ] && SPECIFY_SPEEDTEST_SERVER="${OPT_SPECIFY_SPEEDTEST_SERVER}"
SPEEDTEST_SERVER_OPEN_PROJECT="true"
SPEEDTEST_SERVER_IPA="true"
SPEEDTEST_SERVER_SOFTETHER="false"
if [ "${SPEEDTEST_SERVER_OPEN_PROJECT}" = "true" ]; then
	speedtest_server_search="OPEN Project"
elif [ "${SPEEDTEST_SERVER_IPA}" = "true" ]; then
	speedtest_server_search="IPA CyberLab"
elif [ "${SPEEDTEST_SERVER_OPEN_PROJECT}" = "true" ]; then
	speedtest_server_search="SoftEther Corporation"
else
	# default
	speedtest_server_search="OPEN Project"
fi


# ネット回線速度計測(fast.com)
speed_test_once_fast()
{
	speed_test_result=`fast` || exit 1
	# 小数点以下切り捨て
	cmd_ping_avg=`ping -4 -c 5 8.8.8.8 | tail -n 1 | cut -d '/' -f 5 | cut -d '.' -f 1`
	ping="${cmd_ping_avg}"
	# Mbps前提
	# 小数点以下切り捨て
	download=`echo "${speed_test_result}" | rev | cut -d ' ' -f 2 | rev | cut -d '.' -f 1`
	upload="999999"
}

# ネット回線速度計測(speedtest.net)
speed_test_once_speedtest()
{
	if [ "${SPECIFY_SPEEDTEST_SERVER}" = "true" ]; then
		# サーバ指定済みであればスキップ
		if [ ! -n "${speedtest_server}" ]; then
			speedtest_server_id=`speedtest --list | grep "Japan" | grep "${speedtest_server_search}" | tr -s ' ' | sed -e "s/^ //g" | cut -d ' ' -f 1 | rev | cut -c 2- | rev`
			# 数値判定(計算結果は0にならないため、戻り値1は考慮しない)
			if [ `expr "${speedtest_server_id}" + 1` ]; then
				speedtest_server="--server ${speedtest_server_id}"
			else
				speedtest_server=""
			fi
		fi
	else
		speedtest_server=""
	fi
	if [ "${DOWNLOAD_ONLY}" = "true" ]; then
		# Uploadを計測しない
		speedtest_no_ul="--no-upload"
	else
		speedtest_no_ul=""
	fi
	speed_test_result=`speedtest --simple ${speedtest_no_ul} ${speedtest_server}` || exit 1

	# 小数点以下切り捨て
	ping=`echo "${speed_test_result}" | grep "Ping:" | cut -d ' ' -f 2 | cut -d '.' -f 1`
	cmd_ping_avg=`ping -4 -c 5 8.8.8.8 | tail -n 1 | cut -d '/' -f 5 | cut -d '.' -f 1`
	# Ping値精度向上のため、pingコマンド結果を優先
	ping="${cmd_ping_avg}"
	# Mbps前提
	# 小数点以下切り捨て
	download=`echo "${speed_test_result}" | grep "Download:" | cut -d ' ' -f 2 | cut -d '.' -f 1`
	upload=`echo "${speed_test_result}" | grep "Upload:" | cut -d ' ' -f 2 | cut -d '.' -f 1`
	# TODO: アップロード計測値の修正
	# speedtestのアップロード計測値がWeb版と比較して悪すぎるため判定から除外
	upload="999999"
}

# ネット回線速度計測
speed_test_once()
{
	# 計測アプリを決定
	if [ -n "$1" ]; then
		test_app="$1"
	else
		test_app="${SPEED_TEST_APP}"
	fi

	# 計測値を初期化
	ping="999"
	download="0"
	upload="0"

	case "${test_app}" in
		fast)
			[ `which "${test_app}"` ] || exit 1
			speed_test_once_fast
			echo "${speed_test_result}"
			echo "ping average = ${cmd_ping_avg}"
			;;
		speedtest | speedtest-cli)
			[ `which "${test_app}"` ] || exit 1
			speed_test_once_speedtest
			echo "${speed_test_result}"
			echo "ping average = ${cmd_ping_avg}"
			;;
		*)
			echo "ERROR: Use supported speed test applications"
			exit 1
			;;
	esac
}

# 指定回数ネット回線速度計測し、最悪値を算出
speed_test()
{
	# 計測回数を決定
	if [ -n "$1" ]; then
		test_num="$1"
	else
		test_num="${SPEED_TEST_NUM}"
	fi

	# 最悪値を初期化
	worst_ping="0"
	worst_download="999999"
	worst_upload="999999"

	for speed_test_cnt in `seq 1 ${test_num}`
	do
		# 回線速度計測
		speed_test_once

		# 最悪値更新
		[ ${ping} -gt ${worst_ping} ] && worst_ping=${ping}
		[ ${download} -lt ${worst_download} ] && worst_download=${download}
		[ ${upload} -lt ${worst_upload} ] && worst_upload=${upload}

		# 最悪値がPPPoE再接続閾値より悪ければ回線速度計測を中断して高速化
		if [ "${worst_ping}" -ge "${THRESHOLD_PN}" ] || [ "${worst_download}" -lt "${THRESHOLD_DL}" ] || [ "${worst_upload}" -lt "${THRESHOLD_UL}" ]; then
			break
		fi
	done
}

# PPPoE IF再起動
restart_pppoe()
{
	echo -n "Disconnecting PPPoE: "
	ifdown ${PPPOE_SCRIPT}
	#poff ${PPPOE_SCRIPT}
	echo "OK"
	echo "Waiting ${PPPOE_RESTART_INTERVAL} sec"
	sleep ${PPPOE_RESTART_INTERVAL}
	echo -n "Connecting PPPoE: "
	ifup ${PPPOE_SCRIPT}
	#pon ${PPPOE_SCRIPT}
	echo "OK"

	echo -n "Waiting ifup ${PPPOE_IF}: Checking Global IP Address (IPv4): "
	for i in `seq 1 ${PPPOE_IF_TIMEOUT}`
	do
		if [ `ip -o address show ${PPPOE_IF} | grep -c "inet "` -eq 0 ]; then
			sleep 1
			if [ ${i} -eq ${PPPOE_IF_TIMEOUT} ]; then
				echo "NG"
				# タイムアウトの場合はPPPoE IF再起動(再帰呼び出し)
				restart_pppoe
				break
			fi
		else
			echo "OK"
			break
		fi
	done
}

# PPPoE再接続
retry_pppoe()
{
	# PPPoE再接続回数をカウント
	[ -n "${pppoe_retry_cnt}" ] || pppoe_retry_cnt="0"
	pppoe_retry_cnt=`expr ${pppoe_retry_cnt} + 1`

	# 無限ループ防止
	if [ "${pppoe_retry_cnt}" -gt "${PPPOE_MAX_RETRY}" ]; then
		echo "ABORT: Reached to PPPoE max retry count"
		exit 0
	fi

	# 低速なプロバイダゲートウェイを記録する一時ファイルを作成
	[ -e "${provider_gateway_bad_list}" ] || provider_gateway_bad_list=`mktemp`

	# PPPoE再接続前のプロバイダゲートウェイのIPアドレスを取得
	cur_provider_gateway=`ip route show | grep "${PPPOE_IF}" | grep "src" | cut -d ' ' -f 1`
	if [ -n "${cur_provider_gateway}" ]; then
		# PPPoE再接続実行＝低速なプロバイダゲートウェイのIPアドレスを記録
		echo "${cur_provider_gateway}" >> ${provider_gateway_bad_list}
	else
		# 条件を満たすことはないはず
		echo "WARNING: Not connected to PPPoE gateway"
	fi

	# PPPoE IF再起動
	restart_pppoe

	# PPPoE再接続後のプロバイダゲートウェイのIPアドレスを取得
	new_provider_gateway=`ip route show | grep "${PPPOE_IF}" | grep "src" | cut -d ' ' -f 1`
	if [ `cat ${provider_gateway_bad_list} | grep -c "${new_provider_gateway}"` -gt 0 ]; then
		# PPPoE再接続後のプロバイダゲートウェイが重複した場合、高速化のため回線速度計測を省略しPPPoE再接続(再帰呼び出し)
		echo "Reconnect PPPoE due to duplicate gateway"
		retry_pppoe
	fi
}


# ネット回線速度計測
echo "Checking Internet Speed"
speed_test 1

# 閾値より測定値が悪ければPPPoE再接続
while [ "${worst_ping}" -ge "${THRESHOLD_PN}" ] || [ "${worst_download}" -lt "${THRESHOLD_DL}" ] || [ "${worst_upload}" -lt "${THRESHOLD_UL}" ]
do
	# PPPoE再接続
	echo "Reconnect PPPoE due to poor mesurement results"
	retry_pppoe

	# ネット回線速度計測
	echo "Checking Internet Speed"
	speed_test ${SPEED_TEST_NUM}
done

# 一時ファイルを削除
[ -e "${provider_gateway_bad_list}" ] && rm -f ${provider_gateway_bad_list}

exit 0

