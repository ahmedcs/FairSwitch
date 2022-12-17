#!/bin/bash

# 1 : folder path
# 2 : tcp congestion used
# 3 : # of webpage requests
# 4 : # of concurrent connections
# 5 : # of repetation of apache test
# 6 : is FairSwitch or normal switch

echo $1 $2 $3 $4 $5 $6

path="$1/$2-$3-$4-$5/$6"


if [ $6 == "fairq*" ]; then
	path="$1/$2-$3-$4-$5/$6";
	#dsh -c -g cluster "cd /home/ahmed/IncastGuard/Endhost-WindScale/; make; rmmod tcp_scale.ko; insmod tcp_scale.ko"
	#dsh -c -g cluster "insmod /home/ahmed/IncastGuard/Endhost-WindScale/tcp_scale.ko"
fi

if [ $6 == "wnd*" ]; then
	path="$1/$2-$3-$4-$5/$6";
fi

echo $path

rm -rf $path;
dsh -c -g cluster-ahmed "rm -rf $path; sudo dmesg -c"
mkdir -p $path;
dsh -c -g cluster-ahmed "mkdir -p $path;"

#dsh -c -g cluster 'tc qdisc replace dev p1p2 root pfifo limit 1; tc qdisc replace dev p1p2 root bfifo limit 262144; ethtool -K p1p2 tso off gso off gro off; ethtool --offload  p1p2 sg off rx off  tx off; tc qdisc replace dev p1p3 root pfifo limit 1; tc qdisc replace dev p1p3 root bfifo limit 262144; ethtool -K p1p3 tso off gso off gro off; ethtool --offload  p1p3 sg off rx off  tx off; tc qdisc replace dev p1p4 root pfifo limit 1; tc qdisc replace dev p1p4 root bfifo limit 262144; ethtool -K p1p4 tso off gso off gro off; ethtool --offload  p1p4 sg off rx off  tx off;  tc qdisc replace dev em2 root pfifo limit 1; tc qdisc replace dev em2 root bfifo limit 262144; ethtool -K em2 tso off gso off gro off; ethtool --offload  em2 sg off rx off  tx off; ';

dsh -c -g cluster 'tc qdisc replace dev p1p2 root pfifo limit 1; tc qdisc replace dev p1p2 root bfifo limit 26214400; ethtool -K p1p2 tso off gso off gro off; ethtool --offload  p1p2 sg off rx off  tx off; tc qdisc replace dev p1p3 root pfifo limit 1; tc qdisc replace dev p1p3 root bfifo limit 26214400; ethtool -K p1p3 tso off gso off gro off; ethtool --offload  p1p3 sg off rx off  tx off; tc qdisc replace dev p1p4 root pfifo limit 1; tc qdisc replace dev p1p4 root bfifo limit 26214400; ethtool -K p1p4 tso off gso off gro off; ethtool --offload  p1p4 sg off rx off  tx off;  tc qdisc replace dev em2 root pfifo limit 1; tc qdisc replace dev em2 root bfifo limit 26214400; ethtool -K em2 tso off gso off gro off; ethtool --offload  em2 sg off rx off  tx off; ';

dsh -c -g cluster "sysctl -w net.ipv4.tcp_congestion_control=$2; sysctl -w net.ipv4.tcp_window_scaling=0; sysctl -w net.ipv4.tcp_ecn=0;";

if [ "$2" == "dctcp" ]; then
dsh -c -g cluster 'sysctl -w net.ipv4.tcp_ecn=1;'; #tc qdisc replace dev p1p2 root pfifo limit 1; tc qdisc replace dev p1p2 root red limit 100000 min 30000 max 30001 avpkt 1000  burst 33 ecn bandwidth 930Mbit;';
fi

#dsh -c -g cluster 'sysctl -w net.ipv4.tcp_early_retrans=0; sysctl -w net.ipv4.tcp_congestion_control=reno; sysctl -w net.ipv4.tcp_fack=0; sysctl -w net.ipv4.tcp_dsack=0;';
#sysctl -w net.ipv4.tcp_early_retrans=0; sysctl -w net.ipv4.tcp_congestion_control=reno; sysctl -w net.ipv4.tcp_fack=0; sysctl -w net.ipv4.tcp_dsack=0;


dsh -c -M -g cluster "for i in `pgrep iperf`; do kill -9 $i; done";
dsh -c -M -g cluster "for i in `pgrep ab`; do kill -9 $i; done";

for (( i=1; i<=1; i++ ));
do
dsh -c -M -g cluster "ovs-vsctl add-port ovsbr2 test22$i -- set interface test22$i type=internal; ethtool -K test22$i tso off gso off ";
dsh -c -M -g cluster "ovs-vsctl add-port ovsbr3 test23$i -- set interface test23$i type=internal; ethtool -K test23$i tso off gso off ";
dsh -c -M -g cluster "ovs-vsctl add-port ovsbr4 test24$i -- set interface test24$i type=internal; ethtool -K test24$i tso off gso off ";
dsh -c -M -g cluster "ovs-vsctl add-port ovsbr5 test25$i -- set interface test25$i type=internal; ethtool -K test25$i tso off gso off ";
done

echo "all set, start after 10";
sleep 1;

j=0
for ((i=7; i<=13; i++));
do
a=$(( $j+50 ));
ssh root@node$i "m=1; for (( x=22; x<=25; x++ )); do ifconfig test\$x\$m 172.\$x.1.$a up; done;";
j=$(( $j+1 ));
done


echo "all set, start after 5";
sleep 2;

for (( k=1; k<=$5; k++ )); do
j=0
for ((i=7; i<=13; i++));
do
a=$(( $j+50 ));
b=$(( $j+8 ));
ssh ahmed@node$i "for ((x=23; x<=25; x++)); do for ((y=8; y<=14; y++)); do if [ "$b" -ne "\$y" ]; then echo 172.22.1.$a:172.\$x.0.\$y time: `date +"%T"` :$(($(date +"%s%N")/1000000)); ab -n $3 -c $4 -B 172.22.1.$a http://172.\$x.0.\$y/ >> "$path/\$HOSTNAME-\$x-\$y.web" & fi done & done &" &
j=$(( $j+1 ));
done
done


sleep $(($5 * 35));

for ((i=7; i<=13; i++));
do
scp ahmed@node$i:$path/* $path/;
done
