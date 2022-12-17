# FairSwitch
FairSwitch is a Switch design for equal-share buffer allocation scheme targeted for Data Centre Networks. The idea is to allow the switch allocate equal share of buffer space to maintain a target queue occupancy for all competing flows.  

It is implemented as a load-able Linux-Kernel Module and as a Patch applicable to OpenvSwitch datapath module

# Installation Guide
Please Refer to the [[InstallME](InstallME.md)] file for more information about installation and possible usage scenarios.

# Running experiments

To run an experiment of HSCC, install endhost-wndscale module on the end-hosts then run the following scripts:

```
cd scripts
./incast.sh $p1 $p2 $p3 $p4 $p5 $p6 $p7 $p8 $p9
```
Or to an experiment involving elephants
```
cd scripts
./incast_elephant.sh $p1 $p2 $p3 $p4 $p5 $p6 $p7 $p8 $p9
```
The scripts requires the following inputs:
```
# 1 : folder path
# 2 : experiment runtime
# 3 : number of clients per host
# 4 : interval of iperf reporting
# 5 : tcp congestion used
# 6 : # of webpage requests
# 7 : # of concurrent connections
# 8 : # of repetation of apache test
# 9 : is FairSwitch or normal switch
```

#Feedback
I always welcome and love to have feedback on the program or any possible improvements, please do not hesitate to contact me by commenting on the code [Here](https://ahmedcs.github.io/RWNDQ-post/) or dropping me an email at ahmedcs982@gmail.com. **PS: this is one of the reasons for me to share the software.**  

**This software will be constantly updated as soon as bugs, fixes and/or optimization tricks have been identified.**


# License
This software including (source code, scripts, .., etc) within this repository and its subfolders are licensed under CRAPL license.

**Please refer to the LICENSE file \[[CRAPL LICENCE](LICENSE)\] for more information**


# CopyRight Notice
The Copyright of this repository and its subfolders are held exclusively by "Ahmed Mohamed Abdelmoniem Sayed", for any inquiries contact me at (ahmedcs982@gmail.com).

Any USE or Modification to the (source code, scripts, .., etc) included in this repository has to cite the following PAPER:  

```bibtex
@INPROCEEDINGS{RWNDQ_CloudNet_2015,
  author={Abdelmoniem, Ahmed M. and Bensaou, Brahim},
  booktitle={IEEE 4th International Conference on Cloud Networking (CloudNet)}, 
  title={Reconciling mice and elephants in data center networks}, 
  year={2015},
  volume={},
  number={},
  pages={119-124},
  doi={10.1109/CloudNet.2015.7335293}
}
```

**Notice, the COPYRIGHT and/or Author Information notice at the header of the (source, header and script) files can not be removed or modified.**


# Published Paper
To understand the framework and proposed solution, please read the paper **"Reconciling Mice and Elephants in Data Center Networks"** which contains the modeling and simulation analysis of  [[FairQ Analysis and Simulation](download/Model_Sim.pdf)]
