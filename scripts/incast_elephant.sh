#!/bin/bash

# 1 : folder path
# 2 : experiment runtime
# 3 :  number of clients per host
# 4 : interval of iperf reporting
# 5 : tcp congestion used
# 6 : # of webpage requests
# 7 : # of concurrent connections
# 8 : # of repetition of apache test
# 9 : is FairSwitch or normal switch

path="$1/$2-$3-$4-$5-$6-$7-$8/nofariq"


if [ "$9" == "fairq" ]; then
	path="$1/$2-$3-$4-$5-$6-$7-$8/fairq";
	#dsh -c -g cluster "cd /home/ahmed/Wndhost-WindScale/; make; rmmod tcp_scale.ko; insmod tcp_scale.ko"
fi

if [ "$9" == "wnd" ]; then
	path="$1/$2-$3-$4-$5-$6-$7-$8/wnd";
fi

if [ "$9" == "nonce" ]; then
        path="$1/$2-$3-$4-$5-$6-$7-$8/nonce";
fi

rm -rf $path;
dsh -c -g cluster "rm -rf $path; dmesg -c"
mkdir -p $path;
dsh -c -g cluster "mkdir -p $path;"

dsh -c -g cluster 'tc qdisc replace dev p1p2 root pfifo limit 1; tc qdisc replace dev p1p2 root bfifo limit 262144; ethtool -K p1p2 tso off gso off gro off; ethtool --offload  p1p2 sg off rx off  tx off; tc qdisc replace dev p1p3 root pfifo limit 1; tc qdisc replace dev p1p3 root bfifo limit 262144; ethtool -K p1p3 tso off gso off gro off; ethtool --offload  p1p3 sg off rx off  tx off; tc qdisc replace dev p1p4 root pfifo limit 1; tc qdisc replace dev p1p4 root bfifo limit 262144; ethtool -K p1p4 tso off gso off gro off; ethtool --offload  p1p4 sg off rx off  tx off;  tc qdisc replace dev em2 root pfifo limit 1; tc qdisc replace dev em2 root bfifo limit 262144; ethtool -K em2 tso off gso off gro off; ethtool --offload  em2 sg off rx off  tx off; ';
dsh -c -g cluster "sysctl -w net.ipv4.tcp_congestion_control=$5; sysctl -w net.ipv4.tcp_window_scaling=0; sysctl -w net.ipv4.tcp_ecn=0;";

if [ "$5" == "dctcp" ]; then
dsh -c -g cluster 'sysctl -w net.ipv4.tcp_ecn=1;'; #tc qdisc replace dev p1p2 root pfifo limit 1; tc qdisc replace dev p1p2 root red limit 100000 min 30000 max 30001 avpkt 1000  burst 33 ecn bandwidth 930Mbit;';
fi

#dsh -c -g cluster 'sysctl -w net.ipv4.tcp_early_retrans=0; sysctl -w net.ipv4.tcp_congestion_control=reno; sysctl -w net.ipv4.tcp_fack=0; sysctl -w net.ipv4.tcp_dsack=0;';
#sysctl -w net.ipv4.tcp_early_retrans=0; sysctl -w net.ipv4.tcp_congestion_control=reno; sysctl -w net.ipv4.tcp_fack=0; sysctl -w net.ipv4.tcp_dsack=0;

#dsh -c -M -g cluster 'echo 1 > /sys/module/openvswitch/parameters/incast_enable';

dsh -c -M -g cluster "for i in `pgrep iperf`; do kill -9 $i; done";
dsh -c -M -g cluster "for i in `pgrep ab`; do kill -9 $i; done";

for (( i=1; i<=$3; i++ ));
do
dsh -c -M -g cluster "ovs-vsctl add-port ovsbr2 test22$i -- set interface test22$i type=internal; ethtool -K test22$i tso off gso off ";
#dsh -c -M -g cluster 'str=`sudo ovs-vsctl list-ports ovsbr2`; for i in $str ; do if [[ "$i" == test* ]]; then echo $i; sudo ovs-vsctl del-port ovsbr2 $i; fi done;'
dsh -c -M -g cluster "ovs-vsctl add-port ovsbr3 test23$i -- set interface test23$i type=internal; ethtool -K test23$i tso off gso off ";
#dsh -c -M -g cluster 'str=`sudo ovs-vsctl list-ports ovsbr3`; for i in $str ; do if [[ "$i" == test* ]]; then echo $i; sudo ovs-vsctl del-port ovsbr3 $i; fi done;'
dsh -c -M -g cluster "ovs-vsctl add-port ovsbr4 test24$i -- set interface test24$i type=internal; ethtool -K test24$i tso off gso off ";
#dsh -c -M -g cluster 'str=`sudo ovs-vsctl list-ports ovsbr4`; for i in $str ; do if [[ "$i" == test* ]]; then echo $i; sudo ovs-vsctl del-port ovsbr4 $i; fi done;'
dsh -c -M -g cluster "ovs-vsctl add-port ovsbr5 test25$i -- set interface test25$i type=internal; ethtool -K test25$i tso off gso off ";
#dsh -c -M -g cluster 'str=`sudo ovs-vsctl list-ports ovsbr5`; for i in $str ; do if [[ "$i" == test* ]]; then echo $i; sudo ovs-vsctl del-port ovsbr5 $i; fi done;'
done

echo "all set, start after 10";
sleep 5;

j=0
for ((i=7; i<=13; i++));
do
a=$(( $j+50 ));
ssh root@node$i "for (( k=1; k<=$3; k++ )); do ifconfig test22\$k 172.22.\$k.$a up; iperf -s -w 1M -B 172.22.\$k.$a & echo iperf -s -w 1M -B 172.22.\$k.$a; done;" &
j=$(( $j+1 ));
done


echo "all set, start after 5";
sleep 5;
#echo \$tim: ab -n $6 -c $7 -B 172.22.\$k.$a http://172.\$x.0.\$y/;

m=1
for ((i=7; i<=13; i++));
do
echo $j
a=$(( $j+50 )); b=$(( ($m%7)+50));
ssh root@node$i "for (( x=23; x<=25; x++ )); do for (( k=1; k<=$3; k++ )); do ifconfig test\$x\$k 172.\$x.\$k.$a up; iperf -B 172.\$x.\$k.$a -c 172.22.\$k.$b -t $2 -w 1M -y C -i $4 > "$path/\$HOSTNAME-\$x-\$k.iperf" & done & done;" &
j=$(( $j+1 ));
m=$(( $m+1 ));
done

for (( k=1; k<=$8; k++ )); do
tim=`date +"%T"`;
echo "sleeping $(( $2 / ($8 + 1))) at : $tim"

sleep $(( $2 / ($8 + 1)));
j=0
for ((i=7; i<=13; i++));
do
a=$(( $j+50 ));
b=$(( $j+8 ));
ssh root@node$i "for ((x=23; x<=25; x++)); do for ((y=8; y<=14; y++)); do if [ "$b" -ne "\$y" ]; then echo 172.22.1.$a:172.\$x.0.\$y time: `date +"%T"` :$(($(date +"%s%N")/1000000)); ab -n $6 -c $7 -B 172.22.1.$a http://172.\$x.0.\$y/ >> "$path/\$HOSTNAME-\$x-\$y.web" & fi done & done &" &
j=$(( $j+1 ));
done
done

#j=0
#for ((i=7; i<=13; i++));
#do
#a=$(( $j+50 ));
#ssh root@node$i "for (( k=1; k<=$3; k++ )); do ifconfig test22\$k 172.22.\$k.$a up; iperf -s -w 1M -B 172.22.\$k.$a & done;" &
#j=$(( $j+1 ));
#done

#echo "interfaces are up and iperf servers are ready, start after 5";
#dsh -c -M -g cluster "for (( k=1; k<=$3; k++ )); do ifconfig test22\$k; done";
#sleep 5;

#j=0
#for ((i=7; i<=13; i++));
#do
#a=$(( $j+50 ));
#ssh root@node$i "for (( k=1; k<=$8; k++ )); do sleep 11; for ((x=23; x<=25; x++)); do for ((y=8; y<=14; y++)); do ab -n $6 -c $7 -B 172.22.\$k.$a http://172.\$x.0.\$y/ >> "$path/\$HOSTNAME-\$x-\$y.web" & done; done; done;" &
#j=$(( $j+1 ));
#done

#echo "apache benchmark instructions are sent and will start within 9, start after 1";
#sleep 1;

#for ((i=7; i<=13; i++));
#do
#a=$(( $j+50 )); b=$(( $j+50-7));
#ssh root@node$i "for (( x=23; x<=25; x++ )); do for (( k=1; k<=$3; k++ )); do ifconfig test\$x\$k 172.\$x.\$k.$a up; iperf -B 172.\$x.\$k.$a -c 172.22.\$k.$b -t $2 -w 1M -y C -i $4 > "$path/\$HOSTNAME-\$x-\$k.iperf" & done; done;" &
#j=$(( $j+1 ));
#done



sleep $(( $2 + ($8 * 5) + 10)); #+ $7 * 10)  ));

for ((i=7; i<=13; i++));
do
scp root@node$i:$path/* $path/;
done

#getting drop information
