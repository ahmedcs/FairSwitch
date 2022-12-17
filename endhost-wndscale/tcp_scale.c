#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/types.h>
#include <linux/netfilter.h>
#include <linux/skbuff.h>
#include <linux/ip.h>
#include <linux/netdevice.h>
#include <linux/if_ether.h>
#include <linux/if_packet.h>
#include <linux/inet.h>
#include <net/tcp.h>
#include <net/udp.h>
#include <net/icmp.h>
#include <net/checksum.h>
#include <linux/netfilter_ipv4.h>
#include <linux/string.h>
#include <linux/time.h>
#include <linux/ktime.h>
#include <linux/fs.h>
#include <linux/random.h>
#include <linux/errno.h>
#include <linux/timer.h>
#include <linux/vmalloc.h>
#include <asm/uaccess.h> /* copy_from/to_user */
#include <asm/byteorder.h>

//#define MSS 1460
//#define MIN_RWND 1

#define DEV_MAX 1000

static int srccount, dstcount;
static __u8 scale[DEV_MAX][DEV_MAX];
static __be32 srcip[DEV_MAX];
static __be32 dstip[DEV_MAX];

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Ahmed Sayed ahmedcs982@gmail.com");
MODULE_VERSION("1.0");
MODULE_DESCRIPTION("Kernel module to include window scaling along with TCP receive window");

//Outgoing packets POSTROUTING
static struct nf_hook_ops nfho_outgoing;

//incoming packets PRETROUTING
static struct nf_hook_ops nfho_incoming;


//Function: Add scale factor to Reserved bits of TCP header
static unsigned int tcp_modify_outgoing(struct sk_buff *skb, __u8 scaleval)
{
	struct iphdr *ip_header=NULL;         //IP  header structure
	struct tcphdr *tcp_header=NULL;       //TCP header structure
	int tcplen=0;                    //Length of TCP

	if (skb_linearize(skb)!= 0)
	{
		return 0;
	}

	ip_header=(struct iphdr *)skb_network_header(skb);
	tcp_header = (struct tcphdr *)((__u32 *)ip_header+ ip_header->ihl);

	 if(scaleval > 0)
	 {
		tcp_header->res1 = scaleval;
		printk(KERN_INFO "[WND_SCALE_MOD->%pI4:%pI4]  Scaling : %d res:%d win:%d checksum:%d \n", &ip_header->saddr, &ip_header->daddr, scaleval, tcp_header->res1, tcp_header->window, tcp_header->check);
	 }

	/*//Modify TCP window
	tcp_header->window=htons(win*MSS);
	//TCP length=Total length - IP header length
	tcplen=skb->len-(ip_header->ihl<<2);
	tcp_header->check=0;
	tcp_header->check = csum_tcpudp_magic(ip_header->saddr, ip_header->daddr,
						tcplen, ip_header->protocol,
						csum_partial((char *)tcp_header, tcplen, 0));
	skb->ip_summed = CHECKSUM_UNNECESSARY;*/

	return 1;
}

//Find scaling value for this connection
bool find_scale(struct iphdr *ip_header, __u8 *scaleval)//, struct tcphdr * tcp_header)
{
	    int k=0;
            int i=-1;
            int j=-1;
            while(k < srccount)
            {
                if(srcip[k] == ip_header->saddr)
		{
                    i=k;
		    break;
		}
                k++;
            }
	    k=0;
	    while(k < dstcount)
	    {
		if(dstip[k] == ip_header->daddr)
	    	{
			j=k;
			break;
		}
		k++;
	    }
	    if(i!=-1 && j!=-1)
	    {
		 *(scaleval)=scale[i][j];
		 return true;
	    }
	    else
		return false;
}

void store_scale(struct sk_buff *skb, struct iphdr * ip_header)
{
	struct tcp_options_received opt;
	tcp_clear_options(&opt);
	opt.wscale_ok = opt.snd_wscale = 0;
	tcp_parse_options(skb, &opt, 0, NULL);
	int k=0;
	int i=-1;
	int j=-1;
	while(k < srccount)
	{
		if(srcip[k] == ip_header->saddr)
		{
			i=k;
			break;
		}
		k++;
	}
	k=0;
	while(k < dstcount)
	{
		if(dstip[k] == ip_header->daddr)
		{
			j=k;
			break;
		}
		k++;
	}
	if(i==-1)
	{
		i=srccount;
		srcip[i] = ip_header->saddr;
		srccount++;
	}
	if(j==-1)
	{
		j=dstcount;
		dstip[j] = ip_header->daddr;
		dstcount++;
	}
	if(opt.wscale_ok) //&& !scale[i][j])
	{
		 scale[i][j]=opt.snd_wscale;
		 //printk(KERN_INFO "[WND_SCALE->%pI4:%pI4] New Scaling arrived : %d snd:%d rcv:%d \n", &srcip[i], &dstip[j], opt.wscale_ok, opt.snd_wscale, opt.rcv_wscale);
	 }
	else
		 scale[i][j]=0;
}

//POSTROUTING for outgoing packets
static unsigned int hook_func_out(unsigned int hooknum, struct sk_buff *skb, const struct net_device *in, const struct net_device *out, int (*okfn)(struct sk_buff *))
{
	struct iphdr *ip_header=NULL;         //IP  header structure
	struct tcphdr *tcp_header=NULL;       //TCP header structure
	unsigned short int dst_port,src_port;     	  //TCP destination port

	ip_header=(struct iphdr *)skb_network_header(skb);

	//The packet is not ip packet (e.g. ARP or others)
	if (!ip_header)
	{
		return NF_ACCEPT;
	}

	if(ip_header->protocol==IPPROTO_TCP) //TCP
	{
		tcp_header = (struct tcphdr *)((__u32 *)ip_header+ ip_header->ihl);

		//Get source and destination TCP port
		src_port=htons((unsigned short int) tcp_header->source);
		dst_port=htons((unsigned short int) tcp_header->dest);

		//We only use ICTCP to control incast traffic (tcp port 5001)
		if(src_port==5001 || dst_port==5001 || src_port==80 || dst_port==80)
		{
			if(tcp_header->syn) //&& !tcp_header->ack)
			{
				store_scale(skb, ip_header);
			}
			else if(tcp_header->ack)
			{
				__u8 scaleval;
				bool isok = find_scale(ip_header, &scaleval); //, tcp_header);
				if(isok)
				{
					tcp_modify_outgoing(skb, scaleval);
					//printk(KERN_INFO "[WND_SCALE_MOD->%pI4:%pI4]  Scaling : %d res:%d win:%d \n", &ip_header->saddr, &ip_header->daddr, scaleval, tcp_header->res1, tcp_header->window);
				}
			}
		}

	}
	return NF_ACCEPT;
}


//Called when module loaded using 'insmod'
int init_module()
{
	//POSTROUTING - for outgoing
	nfho_outgoing.hook = hook_func_out;                 //function to call when conditions below met
	nfho_outgoing.hooknum = NF_INET_POST_ROUTING;       //called in post_routing
	nfho_outgoing.pf = PF_INET;                         //IPV4 packets
	nfho_outgoing.priority = NF_IP_PRI_FIRST;           //set to highest priority over all other hook functions
	nf_register_hook(&nfho_outgoing);                   //register hook*/

	/*//PRETROUTING - for incoming
	nfho_incoming.hook = hook_func_in;                 //function to call when conditions below met
	nfho_incoming.hooknum = NF_INET_PRE_ROUTING;       //called in post_routing
	nfho_incoming.pf = PF_INET;                         //IPV4 packets
	nfho_incoming.priority = NF_IP_PRI_FIRST;           //set to highest priority over all other hook functions
	//nf_register_hook(&nfho_incoming);                   //register hook*/

	srccount=0;
	dstcount=0;
	int i=0,j;
	printk(KERN_INFO "[Init] Intializing States : %d \n", DEV_MAX);
	while( i < DEV_MAX)
	{
			 srcip[i]=htons(0);
			 dstip[i]=htons(0);
			 for(j=0; j<DEV_MAX; j++)
			 	scale[i][j]=htons(0);
			 i++;

	 }

	printk(KERN_INFO "Start IncastGuard kernel module\n");

	return 0;
}

//Called when module unloaded using 'rmmod'
void cleanup_module()
{
	//Unregister the hook
	nf_unregister_hook(&nfho_outgoing);
	//nf_unregister_hook(&nfho_incoming);
	printk(KERN_INFO "Stop IncastGuard kernel module\n");
}


/*//Function: Add scale factor to Reserved bits of TCP header
static void tcp_modify_incoming(struct tcphdr *tcp_header, struct iphdr *ip_header )
{
	__u8 oldres1 = tcp_header->res1;
	//tcp_header->res1 = 0; //htons(0);
	__sum16 oldcheck = tcp_header->check;
	//csum_replace2(&tcp_header->check, oldres1, tcp_header->res1);
	printk(KERN_INFO "[WND_SCALE_RESET->%pI4:%pI4] RESET : old:%d:%d new:%d:%d \n", &ip_header->saddr, &ip_header->daddr, oldres1, oldcheck, tcp_header->res1, tcp_header->check);

}

//PRETROUTING for incoming packets
static unsigned int hook_func_in(unsigned int hooknum, struct sk_buff *skb, const struct net_device *in, const struct net_device *out, int (*okfn)(struct sk_buff *))
{
	struct iphdr *ip_header=NULL;         //IP  header structure
	struct tcphdr *tcp_header=NULL;       //TCP header structure
	unsigned short int dst_port,src_port;     	  //TCP destination port

	ip_header=(struct iphdr *)skb_network_header(skb);

	//The packet is not ip packet (e.g. ARP or others)
	if (!ip_header)
	{
		return NF_ACCEPT;
	}

	if(ip_header->protocol==IPPROTO_TCP) //TCP
	{
		tcp_header = (struct tcphdr *)((__u32 *)ip_header+ ip_header->ihl);
		
		if (!tcp_header)
		{
			return NF_ACCEPT;
		}
		//Get source and destination TCP port
		src_port=htons((unsigned short int) tcp_header->source);
		dst_port=htons((unsigned short int) tcp_header->dest);

		//We only use ICTCP to control incast traffic (tcp port 5001)
		if(src_port==5001 || dst_port==5001 || src_port==80 || dst_port==80)
		{
			if(tcp_header->ack && tcp_header->res1 > 0)
			{
				tcp_modify_incoming(tcp_header, ip_header);				
			}
		}

	}
	return NF_ACCEPT;
}*/
